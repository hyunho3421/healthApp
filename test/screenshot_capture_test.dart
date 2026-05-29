import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:muscle_growth_diary/core/db/app_database.dart';
import 'package:muscle_growth_diary/features/database/providers/app_database_provider.dart';
import 'package:muscle_growth_diary/main.dart';

void main() {
  late AppDatabase database;

  setUp(() async {
    database = AppDatabase.forTesting(NativeDatabase.memory());
    await database.seedInitialData();
  });

  tearDown(() async {
    await database.close();
  });

  testWidgets('capture current screens', (tester) async {
    await _loadAppFonts();
    await tester.binding.setSurfaceSize(const Size(390, 844));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(
      ProviderScope(
        overrides: [appDatabaseProvider.overrideWithValue(database)],
        child: const MyApp(),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('이번 주 부위별 운동'), findsOneWidget);
    expect(find.widgetWithText(FilledButton, '빠른 기록 시작'), findsOneWidget);

    await tester.tap(find.byTooltip('운동 통계'));
    await tester.pumpAndSettle();

    expect(find.text('운동 통계'), findsOneWidget);
    expect(find.text('관심 운동'), findsOneWidget);

    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();

    await tester.tap(find.widgetWithText(FilledButton, '빠른 기록 시작'));
    await tester.pumpAndSettle();

    expect(find.text('운동 기록 추가'), findsOneWidget);
    expect(find.text('세트 추가'), findsOneWidget);
  });
}

Future<void> _loadAppFonts() async {
  final fontData = await rootBundle.load('assets/fonts/NotoSansKR[wght].ttf');
  await (FontLoader('Noto Sans KR')..addFont(Future.value(fontData))).load();

  final flutterRoot = Platform.environment['FLUTTER_ROOT'];
  if (flutterRoot == null) {
    return;
  }
  final iconFont = File(
    '$flutterRoot/bin/cache/artifacts/material_fonts/MaterialIcons-Regular.otf',
  );
  final iconFontData = iconFont.readAsBytesSync().buffer.asByteData();
  await (FontLoader(
    'MaterialIcons',
  )..addFont(Future<ByteData>.value(iconFontData))).load();
}
