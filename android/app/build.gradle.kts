import java.io.File
import java.util.Properties

plugins {
    id("com.android.application")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

val keystorePropertiesFile = rootProject.file("key.properties")
val releaseBuildRequested = gradle.startParameter.taskNames.any { requestedTask ->
    val taskName = requestedTask.substringAfterLast(':')
    taskName.contains("release", ignoreCase = true) ||
        taskName.equals("build", ignoreCase = true) ||
        taskName.equals("assemble", ignoreCase = true) ||
        taskName.equals("bundle", ignoreCase = true) ||
        taskName.equals("buildNeeded", ignoreCase = true) ||
        taskName.equals("buildDependents", ignoreCase = true)
}
if (releaseBuildRequested && !keystorePropertiesFile.isFile) {
    throw GradleException(
        "android/key.properties tidak ditemukan. Salin dari " +
            "android/key.properties.example lalu isi kredensial signing lokal.",
    )
}

val keystoreProperties = Properties().apply {
    if (keystorePropertiesFile.isFile) {
        try {
            keystorePropertiesFile.inputStream().use { load(it) }
        } catch (exception: Exception) {
            throw GradleException(
                "android/key.properties tidak dapat dibaca.",
                exception,
            )
        }
    }
}

fun requiredSigningProperty(
    name: String,
    preserveWhitespace: Boolean = false,
): String {
    val value = keystoreProperties.getProperty(name)
        ?: throw GradleException(
            "Properti signing '$name' belum diisi di android/key.properties.",
        )
    val normalized = value.trim()
    if (normalized.isEmpty() || normalized.startsWith("REPLACE_WITH_")) {
        throw GradleException(
            "Properti signing '$name' belum diisi di android/key.properties.",
        )
    }
    return if (preserveWhitespace) value else normalized
}

android {
    namespace = "io.github.panjiarif.waras_arta"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    defaultConfig {
        // TODO: Specify your own unique Application ID (https://developer.android.com/studio/build/application-id.html).
        applicationId = "io.github.panjiarif.waras_arta"
        // You can update the following values to match your application needs.
        // For more information, see: https://flutter.dev/to/review-gradle-config.
        minSdk = flutter.minSdkVersion
        targetSdk = flutter.targetSdkVersion
        // Uses the version code from pubspec.yaml. When using split APKs, 1000 * ABI_VERSION
        // is added automatically by Flutter. (https://developer.android.com/studio/build/configure-apk-splits#configure-APK-versions)
        // You can force using the value of versionCode by specifying the `-P force-version-code-ignoring-abi=true`
        // flag during build.
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    signingConfigs {
        create("release") {
            if (keystorePropertiesFile.isFile) {
                keyAlias = requiredSigningProperty("keyAlias")
                keyPassword = requiredSigningProperty(
                    "keyPassword",
                    preserveWhitespace = true,
                )
                storePassword = requiredSigningProperty(
                    "storePassword",
                    preserveWhitespace = true,
                )
                val configuredStoreFile = File(
                    requiredSigningProperty("storeFile"),
                )
                if (!configuredStoreFile.isAbsolute) {
                    throw GradleException(
                        "Properti 'storeFile' harus berupa path absolut. " +
                            "Di Windows gunakan format C:/Users/.../file.jks.",
                    )
                }
                if (!configuredStoreFile.isFile) {
                    throw GradleException(
                        "Keystore release tidak ditemukan: $configuredStoreFile",
                    )
                }
                storeFile = configuredStoreFile
            }
        }
    }

    buildTypes {
        release {
            signingConfig = signingConfigs.getByName("release")
        }
    }
}

kotlin {
    compilerOptions {
        jvmTarget = org.jetbrains.kotlin.gradle.dsl.JvmTarget.JVM_17
    }
}

flutter {
    source = "../.."
}
