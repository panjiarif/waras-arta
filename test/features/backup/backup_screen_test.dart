import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:waras_arta/app/theme.dart';
import 'package:waras_arta/data/backup/backup_file_gateway.dart';
import 'package:waras_arta/data/backup/backup_service.dart';
import 'package:waras_arta/data/backup/encrypted_backup_codec.dart';
import 'package:waras_arta/domain/backup.dart';
import 'package:waras_arta/domain/finance.dart';
import 'package:waras_arta/features/backup/view_models/backup_view_model.dart';
import 'package:waras_arta/features/backup/views/backup_screen.dart';

void main() {
  setUpAll(() => initializeDateFormatting('id_ID'));

  testWidgets('new backup requires matching strong password and saves once', (
    tester,
  ) async {
    final operations = _FakeBackupOperations();
    final files = _FakeBackupFileGateway();
    await _pumpBackupScreen(tester, operations: operations, files: files);

    await tester.tap(find.byKey(const Key('create-backup')));
    await tester.pumpAndSettle();
    expect(
      find.textContaining('Kata sandi ini tidak disimpan'),
      findsOneWidget,
    );

    await tester.enterText(find.byKey(const Key('backup-password')), 'pendek');
    await tester.enterText(
      find.byKey(const Key('backup-password-confirmation')),
      'pendek',
    );
    await tester.tap(find.byKey(const Key('submit-backup-password')));
    await tester.pump();
    expect(
      find.text('Gunakan minimal $minimumBackupPasswordLength karakter.'),
      findsOneWidget,
    );
    expect(operations.createCount, 0);

    await tester.enterText(
      find.byKey(const Key('backup-password')),
      'kalimat-rahasia',
    );
    await tester.enterText(
      find.byKey(const Key('backup-password-confirmation')),
      'tidak-sama-sekali',
    );
    await tester.tap(find.byKey(const Key('submit-backup-password')));
    await tester.pump();
    expect(find.text('Kata sandi tidak sama.'), findsOneWidget);
    expect(operations.createCount, 0);

    await tester.enterText(
      find.byKey(const Key('backup-password-confirmation')),
      'kalimat-rahasia',
    );
    await tester.tap(find.byKey(const Key('submit-backup-password')));
    await tester.pumpAndSettle();

    expect(operations.createCount, 1);
    expect(operations.lastPassword, 'kalimat-rahasia');
    expect(files.saveCount, 1);
    expect(files.savedName, startsWith('waras-arta-backup-'));
    expect(find.textContaining('Backup berhasil disimpan'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('restore previews counts, saves safety backup, then restores', (
    tester,
  ) async {
    final operations = _FakeBackupOperations();
    final files = _FakeBackupFileGateway(
      picked: PickedBackupFile(
        name: 'catatan.warasarta',
        bytes: Uint8List.fromList([4, 5, 6]),
      ),
    );
    await _pumpBackupScreen(tester, operations: operations, files: files);

    await tester.ensureVisible(find.byKey(const Key('restore-backup')));
    await tester.tap(find.byKey(const Key('restore-backup')));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const Key('backup-password')),
      'kalimat-rahasia',
    );
    await tester.tap(find.byKey(const Key('submit-backup-password')));
    await tester.pumpAndSettle();

    expect(find.text('Ganti seluruh data?'), findsOneWidget);
    expect(find.text('catatan.warasarta'), findsOneWidget);
    expect(find.text('4'), findsOneWidget);
    expect(
      find.textContaining('backup pengaman data saat ini'),
      findsOneWidget,
    );

    await tester.tap(find.byKey(const Key('confirm-restore-backup')));
    await tester.pumpAndSettle();

    expect(files.pickCount, 1);
    expect(operations.inspectCount, 1);
    expect(operations.createCount, 1);
    expect(files.saveCount, 1);
    expect(files.savedName, contains('sebelum-restore'));
    expect(operations.restoreCount, 1);
    expect(find.text('Beranda pengujian'), findsOneWidget);
    expect(find.textContaining('Data berhasil dipulihkan'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('canceling safety backup leaves current data untouched', (
    tester,
  ) async {
    final operations = _FakeBackupOperations();
    final files = _FakeBackupFileGateway(
      saveResult: false,
      picked: PickedBackupFile(
        name: 'catatan.warasarta',
        bytes: Uint8List.fromList([4, 5, 6]),
      ),
    );
    await _pumpBackupScreen(tester, operations: operations, files: files);

    await tester.ensureVisible(find.byKey(const Key('restore-backup')));
    await tester.tap(find.byKey(const Key('restore-backup')));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const Key('backup-password')),
      'kalimat-rahasia',
    );
    await tester.tap(find.byKey(const Key('submit-backup-password')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('confirm-restore-backup')));
    await tester.pumpAndSettle();

    expect(operations.createCount, 1);
    expect(files.saveCount, 1);
    expect(files.savedName, contains('sebelum-restore'));
    expect(operations.restoreCount, 0);
    expect(
      find.textContaining('backup pengaman belum disimpan'),
      findsOneWidget,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('invalid password or corrupt backup never reaches restore', (
    tester,
  ) async {
    final operations = _FakeBackupOperations(
      inspectError: const BackupFormatException(
        'Kata sandi salah atau file backup rusak.',
      ),
    );
    final files = _FakeBackupFileGateway(
      picked: PickedBackupFile(
        name: 'rusak.warasarta',
        bytes: Uint8List.fromList([7, 8, 9]),
      ),
    );
    await _pumpBackupScreen(tester, operations: operations, files: files);

    await tester.ensureVisible(find.byKey(const Key('restore-backup')));
    await tester.tap(find.byKey(const Key('restore-backup')));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const Key('backup-password')),
      'kata-sandi-salah',
    );
    await tester.tap(find.byKey(const Key('submit-backup-password')));
    await tester.pumpAndSettle();

    expect(
      find.text('Kata sandi salah atau file backup rusak.'),
      findsOneWidget,
    );
    expect(operations.inspectCount, 1);
    expect(operations.createCount, 0);
    expect(operations.restoreCount, 0);
    expect(tester.takeException(), isNull);
  });

  testWidgets('canceling the restore preview makes no backup or mutation', (
    tester,
  ) async {
    final operations = _FakeBackupOperations();
    final files = _FakeBackupFileGateway(
      picked: PickedBackupFile(
        name: 'catatan.warasarta',
        bytes: Uint8List.fromList([4, 5, 6]),
      ),
    );
    await _pumpBackupScreen(tester, operations: operations, files: files);

    await tester.ensureVisible(find.byKey(const Key('restore-backup')));
    await tester.tap(find.byKey(const Key('restore-backup')));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const Key('backup-password')),
      'kalimat-rahasia',
    );
    await tester.tap(find.byKey(const Key('submit-backup-password')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Batal'));
    await tester.pumpAndSettle();

    expect(find.text('Jaga catatan keuanganmu'), findsOneWidget);
    expect(operations.inspectCount, 1);
    expect(operations.createCount, 0);
    expect(operations.restoreCount, 0);
    expect(files.saveCount, 0);
    expect(tester.takeException(), isNull);
  });

  testWidgets('back navigation is blocked while a backup is running', (
    tester,
  ) async {
    final createGate = Completer<void>();
    final operations = _FakeBackupOperations(createGate: createGate);
    final files = _FakeBackupFileGateway();
    final router = await _pumpBackupScreen(
      tester,
      operations: operations,
      files: files,
      initialLocation: '/',
    );
    router.push('/backup');
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('create-backup')));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const Key('backup-password')),
      'kalimat-rahasia',
    );
    await tester.enterText(
      find.byKey(const Key('backup-password-confirmation')),
      'kalimat-rahasia',
    );
    await tester.tap(find.byKey(const Key('submit-backup-password')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expect(operations.createCount, 1);

    await tester.binding.handlePopRoute();
    await tester.pump();
    expect(find.text('Jaga catatan keuanganmu'), findsOneWidget);

    createGate.complete();
    await tester.pumpAndSettle();
    expect(files.saveCount, 1);
    expect(tester.takeException(), isNull);
  });

  testWidgets('backup screen and password dialog fit narrow enlarged text', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(320, 640));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final operations = _FakeBackupOperations();
    final files = _FakeBackupFileGateway();
    await _pumpBackupScreen(
      tester,
      operations: operations,
      files: files,
      textScale: 1.8,
    );

    await tester.ensureVisible(find.byKey(const Key('create-backup')));
    await tester.tap(find.byKey(const Key('create-backup')));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('backup-password')), findsOneWidget);
    expect(
      find.byKey(const Key('backup-password-confirmation')),
      findsOneWidget,
    );
    expect(tester.takeException(), isNull);
  });
}

Future<GoRouter> _pumpBackupScreen(
  WidgetTester tester, {
  required _FakeBackupOperations operations,
  required _FakeBackupFileGateway files,
  double textScale = 1,
  String initialLocation = '/backup',
}) async {
  final router = GoRouter(
    initialLocation: initialLocation,
    routes: [
      GoRoute(
        path: '/',
        builder: (context, state) =>
            const Scaffold(body: Text('Beranda pengujian')),
      ),
      GoRoute(
        path: '/backup',
        builder: (context, state) => const BackupScreen(),
      ),
    ],
  );
  addTearDown(router.dispose);
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        backupOperationsProvider.overrideWithValue(operations),
        backupFileGatewayProvider.overrideWithValue(files),
        backupClockProvider.overrideWithValue(
          () => DateTime(2026, 9, 6, 14, 30),
        ),
      ],
      child: MaterialApp.router(
        theme: buildAppTheme(),
        locale: const Locale('id', 'ID'),
        supportedLocales: const [Locale('id', 'ID')],
        localizationsDelegates: GlobalMaterialLocalizations.delegates,
        routerConfig: router,
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context)
              .copyWith(textScaler: TextScaler.linear(textScale)),
          child: child!,
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
  return router;
}

class _FakeBackupOperations implements BackupOperations {
  _FakeBackupOperations({this.createGate, this.inspectError});

  final Completer<void>? createGate;
  final Object? inspectError;
  int createCount = 0;
  int inspectCount = 0;
  int restoreCount = 0;
  String? lastPassword;

  final BackupDocument document = _backupDocument();

  @override
  Future<CreatedBackup> create({
    required String password,
    required DateTime now,
  }) async {
    createCount++;
    lastPassword = password;
    await createGate?.future;
    return CreatedBackup(
      bytes: Uint8List.fromList([1, 2, 3]),
      suggestedName: backupFileName(now),
      summary: document.summary,
    );
  }

  @override
  Future<BackupRestorePlan> inspect({
    required Uint8List bytes,
    required String password,
  }) async {
    inspectCount++;
    lastPassword = password;
    if (inspectError != null) throw inspectError!;
    return BackupRestorePlan(document: document);
  }

  @override
  Future<void> restore(BackupRestorePlan plan) async {
    restoreCount++;
  }
}

class _FakeBackupFileGateway implements BackupFileGateway {
  _FakeBackupFileGateway({this.saveResult = true, this.picked});

  final bool saveResult;
  final PickedBackupFile? picked;
  int saveCount = 0;
  int pickCount = 0;
  String? savedName;

  @override
  Future<PickedBackupFile?> pick() async {
    pickCount++;
    return picked;
  }

  @override
  Future<bool> save({
    required String suggestedName,
    required Uint8List bytes,
  }) async {
    saveCount++;
    savedName = suggestedName;
    return saveResult;
  }
}

BackupDocument _backupDocument() {
  final createdAt = DateTime.utc(2026, 9, 6, 7, 30);
  return BackupDocument(
    databaseSchemaVersion: 4,
    createdAtUtc: createdAt,
    sequences: const BackupSequences(
      accounts: 1,
      categories: 4,
      ledgerEntries: 1,
    ),
    accounts: [
      BackupAccount(
        id: 1,
        name: 'Dompet',
        normalizedName: 'dompet',
        type: AccountType.cash,
        isArchived: false,
        createdAtUtc: createdAt,
      ),
    ],
    categories: [
      BackupCategory(
        id: 1,
        parentId: null,
        kind: CategoryKind.income,
        name: 'Pemasukan',
        normalizedName: 'pemasukan',
        iconKey: 'work',
        isArchived: false,
        sortOrder: 0,
        systemKey: null,
        createdAtUtc: createdAt,
        updatedAtUtc: createdAt,
      ),
      BackupCategory(
        id: 2,
        parentId: 1,
        kind: CategoryKind.income,
        name: 'Gaji',
        normalizedName: 'gaji',
        iconKey: 'work',
        isArchived: false,
        sortOrder: 0,
        systemKey: null,
        createdAtUtc: createdAt,
        updatedAtUtc: createdAt,
      ),
      BackupCategory(
        id: 3,
        parentId: null,
        kind: CategoryKind.expense,
        name: 'Pengeluaran',
        normalizedName: 'pengeluaran',
        iconKey: 'restaurant',
        isArchived: false,
        sortOrder: 0,
        systemKey: null,
        createdAtUtc: createdAt,
        updatedAtUtc: createdAt,
      ),
      BackupCategory(
        id: 4,
        parentId: 3,
        kind: CategoryKind.expense,
        name: 'Makan',
        normalizedName: 'makan',
        iconKey: 'restaurant',
        isArchived: false,
        sortOrder: 0,
        systemKey: null,
        createdAtUtc: createdAt,
        updatedAtUtc: createdAt,
      ),
    ],
    ledgerEntries: [
      BackupLedgerEntry(
        id: 1,
        kind: EntryKind.income,
        accountId: 1,
        destinationAccountId: null,
        amount: 100000,
        allocations: const [
          BackupLedgerAllocation(position: 0, categoryId: 2, amount: 100000),
        ],
        note: 'Rahasia gaji September',
        occurredDay: 20260906,
        createdAtUtc: createdAt,
      ),
    ],
  );
}
