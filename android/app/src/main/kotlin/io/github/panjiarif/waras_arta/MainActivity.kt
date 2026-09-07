package io.github.panjiarif.waras_arta

import android.app.Activity
import android.content.Intent
import android.net.Uri
import android.provider.OpenableColumns
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import java.io.ByteArrayOutputStream
import java.io.IOException
import java.security.MessageDigest
import java.util.Locale
import java.util.concurrent.ExecutorService
import java.util.concurrent.Executors

class MainActivity : FlutterActivity() {
    private enum class Operation {
        SAVE,
        PICK,
    }

    private data class PendingOperation(
        val type: Operation,
        val result: MethodChannel.Result,
        val bytes: ByteArray? = null,
    )

    private data class DocumentMetadata(
        val name: String?,
        val size: Long?,
    )

    private class FileTooLargeException : IOException()
    private class VerificationException : IOException()

    private var channel: MethodChannel? = null
    private var pendingOperation: PendingOperation? = null
    private val fileExecutor: ExecutorService = Executors.newSingleThreadExecutor()

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        channel = MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            BACKUP_FILE_CHANNEL,
        ).also { methodChannel ->
            methodChannel.setMethodCallHandler(::handleMethodCall)
        }
    }

    override fun cleanUpFlutterEngine(flutterEngine: FlutterEngine) {
        pendingOperation?.let { operation ->
            operation.result.error(
                "activity_unavailable",
                "Operasi file dihentikan karena layar Android ditutup.",
                null,
            )
        }
        pendingOperation = null
        channel?.setMethodCallHandler(null)
        channel = null
        super.cleanUpFlutterEngine(flutterEngine)
    }

    override fun onDestroy() {
        fileExecutor.shutdownNow()
        super.onDestroy()
    }

    @Suppress("DEPRECATION")
    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?) {
        super.onActivityResult(requestCode, resultCode, data)
        val operation = pendingOperation ?: return
        val expectedCode = when (operation.type) {
            Operation.SAVE -> SAVE_BACKUP_REQUEST
            Operation.PICK -> PICK_BACKUP_REQUEST
        }
        if (requestCode != expectedCode) return

        if (resultCode != Activity.RESULT_OK) {
            finishSuccess(operation, if (operation.type == Operation.SAVE) false else null)
            return
        }
        val uri = data?.data
        if (uri == null) {
            finishError(
                operation,
                "file_access_failed",
                "Lokasi file yang dipilih tidak dapat dibuka.",
            )
            return
        }

        when (operation.type) {
            Operation.SAVE -> verifyAndSave(operation, uri)
            Operation.PICK -> readPickedFile(operation, uri)
        }
    }

    private fun handleMethodCall(call: MethodCall, result: MethodChannel.Result) {
        if (call.method != "saveBackup" && call.method != "pickBackup") {
            result.notImplemented()
            return
        }
        if (pendingOperation != null) {
            result.error(
                "busy",
                "Pemilih file sedang digunakan.",
                null,
            )
            return
        }
        val requestedLimit = call.argument<Number>("maxBytes")?.toLong()
        if (requestedLimit != MAX_BACKUP_FILE_BYTES.toLong()) {
            result.error(
                "invalid_arguments",
                "Batas ukuran file tidak valid.",
                null,
            )
            return
        }

        when (call.method) {
            "saveBackup" -> startSave(call, result)
            "pickBackup" -> startPick(result)
        }
    }

    @Suppress("DEPRECATION")
    private fun startSave(call: MethodCall, result: MethodChannel.Result) {
        val suggestedName = call.argument<String>("suggestedName")
        val bytes = call.argument<ByteArray>("bytes")
        if (
            suggestedName.isNullOrBlank() ||
            suggestedName.length > MAX_FILE_NAME_LENGTH ||
            !suggestedName.lowercase(Locale.ROOT).endsWith(BACKUP_FILE_SUFFIX) ||
            suggestedName.contains('/') ||
            suggestedName.contains('\\') ||
            bytes == null
        ) {
            result.error(
                "invalid_arguments",
                "Data penyimpanan backup tidak valid.",
                null,
            )
            return
        }
        if (bytes.size > MAX_BACKUP_FILE_BYTES) {
            result.error(
                "file_too_large",
                "Backup terlalu besar untuk disimpan.",
                null,
            )
            return
        }

        val operation = PendingOperation(Operation.SAVE, result, bytes)
        pendingOperation = operation
        val intent = Intent(Intent.ACTION_CREATE_DOCUMENT).apply {
            addCategory(Intent.CATEGORY_OPENABLE)
            type = BACKUP_MIME_TYPE
            putExtra(Intent.EXTRA_TITLE, suggestedName)
            addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
            addFlags(Intent.FLAG_GRANT_WRITE_URI_PERMISSION)
        }
        try {
            startActivityForResult(intent, SAVE_BACKUP_REQUEST)
        } catch (_: Exception) {
            finishError(
                operation,
                "file_access_failed",
                "Tidak ada pemilih file yang tersedia.",
            )
        }
    }

    @Suppress("DEPRECATION")
    private fun startPick(result: MethodChannel.Result) {
        val operation = PendingOperation(Operation.PICK, result)
        pendingOperation = operation
        val intent = Intent(Intent.ACTION_OPEN_DOCUMENT).apply {
            addCategory(Intent.CATEGORY_OPENABLE)
            type = "*/*"
            addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
        }
        try {
            startActivityForResult(intent, PICK_BACKUP_REQUEST)
        } catch (_: Exception) {
            finishError(
                operation,
                "file_access_failed",
                "Tidak ada pemilih file yang tersedia.",
            )
        }
    }

    private fun verifyAndSave(operation: PendingOperation, uri: Uri) {
        val bytes = operation.bytes
        if (bytes == null) {
            finishError(
                operation,
                "invalid_arguments",
                "Data penyimpanan backup tidak valid.",
            )
            return
        }
        try {
            fileExecutor.execute {
                try {
                    val output = contentResolver.openOutputStream(uri, "wt")
                        ?: throw IOException("Output stream unavailable")
                    output.use {
                        it.write(bytes)
                        it.flush()
                    }
                    verifySavedBytes(uri, bytes)
                    runOnUiThread { finishSuccess(operation, true) }
                } catch (_: Exception) {
                    runOnUiThread {
                        finishError(
                            operation,
                            "write_verification_failed",
                            "File backup tidak dapat ditulis dan diverifikasi.",
                        )
                    }
                } finally {
                    bytes.fill(0)
                }
            }
        } catch (_: Exception) {
            bytes.fill(0)
            finishError(
                operation,
                "file_access_failed",
                "Penyimpanan backup sedang tidak tersedia.",
            )
        }
    }

    private fun verifySavedBytes(uri: Uri, expected: ByteArray) {
        val digest = MessageDigest.getInstance("SHA-256")
        var total = 0L
        val input = contentResolver.openInputStream(uri)
            ?: throw VerificationException()
        input.use {
            val buffer = ByteArray(STREAM_BUFFER_BYTES)
            while (true) {
                val amount = it.read(buffer)
                if (amount < 0) break
                if (amount == 0) continue
                total += amount
                if (total > expected.size.toLong()) throw VerificationException()
                digest.update(buffer, 0, amount)
            }
        }
        val expectedDigest = MessageDigest.getInstance("SHA-256").digest(expected)
        if (
            total != expected.size.toLong() ||
            !MessageDigest.isEqual(expectedDigest, digest.digest())
        ) {
            throw VerificationException()
        }
    }

    private fun readPickedFile(operation: PendingOperation, uri: Uri) {
        fileExecutor.execute {
            try {
                val metadata = readMetadata(uri)
                val knownSize = metadata.size
                if (knownSize != null && knownSize > MAX_BACKUP_FILE_BYTES) {
                    throw FileTooLargeException()
                }
                val displayName = metadata.name
                    ?.takeIf { it.isNotBlank() }
                    ?: "backup.warasarta"
                if (displayName.length > MAX_FILE_NAME_LENGTH) {
                    throw IOException("Display name is too long")
                }
                val bytes = readBounded(uri, knownSize)
                val response = hashMapOf<String, Any>(
                    "name" to displayName,
                    "bytes" to bytes,
                )
                runOnUiThread { finishSuccess(operation, response) }
            } catch (_: FileTooLargeException) {
                runOnUiThread {
                    finishError(
                        operation,
                        "file_too_large",
                        "File backup melebihi batas 16 MB.",
                    )
                }
            } catch (_: Exception) {
                runOnUiThread {
                    finishError(
                        operation,
                        "file_read_failed",
                        "File backup tidak dapat dibaca.",
                    )
                }
            }
        }
    }

    private fun readBounded(uri: Uri, knownSize: Long?): ByteArray {
        val initialCapacity = knownSize
            ?.takeIf { it in 1..MAX_BACKUP_FILE_BYTES.toLong() }
            ?.toInt()
            ?: STREAM_BUFFER_BYTES
        val output = ByteArrayOutputStream(initialCapacity)
        val input = contentResolver.openInputStream(uri)
            ?: throw IOException("Input stream unavailable")
        input.use {
            val buffer = ByteArray(STREAM_BUFFER_BYTES)
            var total = 0
            while (true) {
                val amount = it.read(buffer)
                if (amount < 0) break
                if (amount == 0) continue
                if (amount > MAX_BACKUP_FILE_BYTES - total) {
                    throw FileTooLargeException()
                }
                output.write(buffer, 0, amount)
                total += amount
            }
        }
        return output.toByteArray()
    }

    private fun readMetadata(uri: Uri): DocumentMetadata {
        var name: String? = null
        var size: Long? = null
        contentResolver.query(
            uri,
            arrayOf(OpenableColumns.DISPLAY_NAME, OpenableColumns.SIZE),
            null,
            null,
            null,
        )?.use { cursor ->
            if (cursor.moveToFirst()) {
                val nameIndex = cursor.getColumnIndex(OpenableColumns.DISPLAY_NAME)
                if (nameIndex >= 0 && !cursor.isNull(nameIndex)) {
                    name = cursor.getString(nameIndex)
                }
                val sizeIndex = cursor.getColumnIndex(OpenableColumns.SIZE)
                if (sizeIndex >= 0 && !cursor.isNull(sizeIndex)) {
                    size = cursor.getLong(sizeIndex).takeIf { it >= 0 }
                }
            }
        }
        return DocumentMetadata(name, size)
    }

    private fun finishSuccess(operation: PendingOperation, value: Any?) {
        if (pendingOperation !== operation) return
        operation.bytes?.fill(0)
        pendingOperation = null
        operation.result.success(value)
    }

    private fun finishError(
        operation: PendingOperation,
        code: String,
        message: String,
    ) {
        if (pendingOperation !== operation) return
        operation.bytes?.fill(0)
        pendingOperation = null
        operation.result.error(code, message, null)
    }

    companion object {
        private const val BACKUP_FILE_CHANNEL =
            "io.github.panjiarif.waras_arta/backup_files"
        private const val BACKUP_MIME_TYPE = "application/octet-stream"
        private const val BACKUP_FILE_SUFFIX = ".warasarta"
        private const val MAX_BACKUP_FILE_BYTES = 16 * 1024 * 1024
        private const val MAX_FILE_NAME_LENGTH = 180
        private const val STREAM_BUFFER_BYTES = 8 * 1024
        private const val SAVE_BACKUP_REQUEST = 0x5741
        private const val PICK_BACKUP_REQUEST = 0x5742
    }
}
