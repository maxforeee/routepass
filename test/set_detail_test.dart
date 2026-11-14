import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:routepass/core/kv_store.dart';
import 'package:routepass/core/theme.dart';
import 'package:routepass/models/answer_record.dart';
import 'package:routepass/models/bank_manifest.dart';
import 'package:routepass/models/stats.dart';
import 'package:routepass/pages/bank/module_list_page.dart';
import 'package:routepass/pages/bank/quiz_page.dart';
import 'package:routepass/pages/bank/set_detail_page.dart';
import 'package:routepass/services/bank/answer_record_service.dart';
import 'package:routepass/services/mock/mock_bank_manifest_service.dart';
import 'package:routepass/services/mock/mock_question_repository.dart';
import 'package:routepass/widgets/answer_records_card.dart';
import 'package:routepass/widgets/capsule_nav_bar.dart';
import 'package:routepass/widgets/reserved_slot.dart';
import 'package:routepass/widgets/set_row_card.dart';

import 'test_helpers.dart';

Finder _navTab(String label) =>
    find.descendant(of: find.byType(CapsuleNavBar), matching: find.text(label));

/// F10：练习 tab 唯一一张套卷卡（线上 practiceByModule = H3CNE / 100 题）。
/// 卡片标签里也有 “H3CNE”，首页精选题库也渲染 SetRowCard，所以限定在题库页
/// 内按卡片定位。
Finder get _practiceCard => find.descendant(
  of: find.byType(BankModuleListPage),
  matching: find.widgetWithText(SetRowCard, 'H3CNE'),
);

/// 考试 tab 第一张模拟卷卡（同样限定在题库页内）。
Finder get _paperCard => find.descendant(
  of: find.byType(BankModuleListPage),
  matching: find.widgetWithText(SetRowCard, 'H3CNE 模拟卷 A'),
);

/// 2026-11-14 实测线上清单（curl GET /api/v1/bank/manifest）：
/// practiceByModule 与 kModuleOrder 重叠 VLAN / OSPF / ACL 各 100 题，
/// NAT / SUBNET 无数据；H3CNE / 基础知识 不在五模块展示序内。
const Map<String, dynamic> _liveManifestJson = <String, dynamic>{
  'bankId': 'bank_default',
  'version': '1.0.0',
  'questionCount': 650,
  'exams': <Map<String, dynamic>>[
    <String, dynamic>{
      'id': 'h3cne-2026-01',
      'title': 'H3CNE 模拟卷 A',
      'questionCount': 100,
    },
    <String, dynamic>{
      'id': 'h3cne-2026-02',
      'title': 'H3CNE 模拟卷 B',
      'questionCount': 100,
    },
  ],
  'practiceByModule': <String, dynamic>{
    'ACL': 100,
    'H3CNE': 100,
    'OSPF': 100,
    'VLAN': 100,
    '基础知识': 50,
  },
};

/// F16 预留套卷统计接口的测试替身：模拟后端就绪后返回真实套卷级统计。
class _SetStatsRepository extends MockQuestionRepository {
  @override
  Future<List<ModuleStat>> getSetModuleStats({required String setId}) async {
    if (setId != 'h3cne-2026-01') return const <ModuleStat>[];
    return const <ModuleStat>[
      ModuleStat(module: 'VLAN', total: 40, answered: 10, correctRate: 0.8),
    ];
  }
}

/// F19 套卷概览接口替身：后端就绪后返回真实 done/remaining 与题型分布。
class _OverviewRepository extends MockQuestionRepository {
  @override
  Future<BankSetOverview?> getSetOverview({required String setId}) async {
    return BankSetOverview(
      setId: setId,
      total: 650,
      done: 120,
      remaining: 530,
      byType: QuestionTypeStat(setId: setId, single: 90, multiple: 30),
    );
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  initTestServices();

  testWidgets('套卷详情页 100 题渲染完整', (tester) async {
    await loginToHome(tester);

    await tester.tap(_navTab('题库'));
    await tester.pumpAndSettle();
    await tester.tap(_practiceCard);
    await tester.pumpAndSettle();

    expect(find.byType(SetDetailPage), findsOneWidget);
    expect(find.text('100 题套卷'), findsOneWidget);
    expect(find.text('H3CNE-RS+ 模拟套卷 · 含解析'), findsOneWidget);
    expect(find.text('共 100 题'), findsOneWidget);

    // 知识点考察：20px 粗体标题 + 5 个模块行。F16：题量/进度来自真实
    // 数据——默认 Mock 清单只有 H3CNE（与五模块无重叠）、Mock 进度 0/0，
    // 所以五行都显示“待接口”，不再是 drawCount 均分的假数字。
    final sectionTitle = tester.widget<Text>(find.text('知识点考察'));
    expect(sectionTitle.style?.fontSize, AppFontSizes.detailSectionTitle);
    expect(sectionTitle.style?.fontWeight, FontWeight.bold);
    expect(sectionTitle.style?.color, AppColors.brandTitle);
    expect(find.text('VLAN'), findsOneWidget);
    expect(find.text('OSPF'), findsOneWidget);
    expect(find.text('ACL'), findsOneWidget);
    expect(find.text('NAT'), findsOneWidget);
    expect(find.text('子网划分'), findsOneWidget);
    expect(find.text('题量待接口 · 进度待接口'), findsNWidgets(5));
    final progressBars = find.descendant(
      of: find.byType(SetDetailPage),
      matching: find.byType(FractionallySizedBox),
    );
    expect(progressBars, findsNWidgets(5));
    for (final element in progressBars.evaluate()) {
      expect((element.widget as FractionallySizedBox).widthFactor, 0.0);
    }

    expect(find.byType(ReservedSlot), findsOneWidget);
    expect(find.text('预留容器 · 以后在这里加内容'), findsOneWidget);
    // F16：这是练习 tab 进入的 practice 前置页，答题说明卡只属于考试页。
    expect(find.text('答题说明'), findsNothing);
    expect(find.text('限时 60 分钟，超时自动交卷'), findsNothing);
    expect(find.text('交卷后可查看解析与得分'), findsNothing);
    expect(find.text('做错的题自动收入错题本'), findsNothing);
    expect(find.text('开始练习'), findsOneWidget);
  });

  testWidgets('开始答题固定在屏幕底部且不随内容滚动', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light,
        home: SetDetailPage(
          args: <String, Object?>{'mode': 'exam', 'drawCount': 100},
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(
      find.descendant(
        of: find.byType(SingleChildScrollView),
        matching: find.text('开始答题'),
      ),
      findsNothing,
    );
    final pinned = tester.widget<Positioned>(
      find.descendant(
        of: find.byType(SetDetailPage),
        matching: find.byType(Positioned),
      ),
    );
    expect(pinned.bottom, AppSpacing.md);

    final button = tester.widget<FilledButton>(
      find.widgetWithText(FilledButton, '开始答题'),
    );
    expect(
      button.style?.backgroundColor?.resolve(<WidgetState>{}),
      AppColors.brandPrimary,
    );
    final shape = button.style?.shape?.resolve(<WidgetState>{});
    expect(shape, isA<RoundedRectangleBorder>());
    expect(
      (shape! as RoundedRectangleBorder).borderRadius,
      BorderRadius.circular(AppRadii.setDetailStartButton),
    );
  });

  testWidgets('套卷详情页 开始答题 进答题页', (tester) async {
    await loginToHome(tester);

    await tester.tap(_navTab('题库'));
    await tester.pumpAndSettle();
    // F19：练习卡与考试卷一都进新的 QuizPage，练习不再按 exam 进。
    for (var i = 0; i < 2; i++) {
      if (i == 1) {
        await tester.tap(find.text('考试'));
        await tester.pumpAndSettle();
      }
      final card = i == 0 ? _practiceCard : _paperCard;
      await tester.tap(card);
      await tester.pumpAndSettle();
      // F16：练习前置页无答题说明卡，考试前置页有。
      expect(find.text('答题说明'), i == 0 ? findsNothing : findsOneWidget);
      await tester.tap(
        find.widgetWithText(FilledButton, i == 0 ? '开始练习' : '开始答题'),
      );
      await tester.pumpAndSettle();
      final quiz = tester.widget<QuizPage>(find.byType(QuizPage));
      expect(quiz.args['mode'], i == 0 ? 'practice' : 'exam');
      expect(quiz.args['drawCount'], 100);
      expect(find.text(i == 0 ? '第 1/20 题' : '第 1/100 题'), findsOneWidget);
      // 未作答直接返回：QuizPage 的返回箭头不弹确认，直接回详情页。
      await tester.tap(find.byTooltip('返回'));
      await tester.pumpAndSettle();
      expect(find.byType(SetDetailPage), findsOneWidget);
      await tester.tap(find.byTooltip('返回'));
      await tester.pumpAndSettle();
    }
  });

  testWidgets('套卷详情页 200 题推导正确', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light,
        home: SetDetailPage(
          args: <String, Object?>{'mode': 'exam', 'drawCount': 200},
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('200 题套卷'), findsOneWidget);
    expect(find.text('H3CNE-RS+ 模拟套卷 · 含解析'), findsOneWidget);
    expect(find.text('共 200 题'), findsOneWidget);
    // F16：模块题量不再按 drawCount 均分，缺真实数据显示“待接口”。
    expect(find.text('题量待接口 · 进度待接口'), findsNWidgets(5));
    expect(find.text('限时 120 分钟，超时自动交卷'), findsOneWidget);
  });

  testWidgets('套卷详情页 50 题推导正确', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light,
        home: SetDetailPage(
          args: <String, Object?>{'mode': 'exam', 'drawCount': 50},
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('50 题套卷'), findsOneWidget);
    expect(find.text('H3CNE-RS+ 模拟套卷 · 含解析'), findsOneWidget);
    expect(find.text('共 50 题'), findsOneWidget);
    // F16：模块题量不再按 drawCount 均分，缺真实数据显示“待接口”。
    expect(find.text('题量待接口 · 进度待接口'), findsNWidgets(5));
    expect(find.text('限时 30 分钟，超时自动交卷'), findsOneWidget);
  });

  testWidgets('四套卷共用模板，规模数字由 drawCount 推导', (tester) async {
    // 100/200/50/10 同一模板：标题、单选多选、时长按 drawCount 公式推导，
    // 不许出现写死的单套数字。F16：每模块题量改由真实数据决定，不再随
    // drawCount 均分——默认 Mock 清单无重叠模块，五行恒为“待接口”。
    for (final (count, meta, minutes) in <(int, String, String)>[
      (100, '共 100 题', '限时 60 分钟，超时自动交卷'),
      (200, '共 200 题', '限时 120 分钟，超时自动交卷'),
      (50, '共 50 题', '限时 30 分钟，超时自动交卷'),
      (10, '共 10 题', '限时 6 分钟，超时自动交卷'),
    ]) {
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.light,
          home: SetDetailPage(
            args: <String, Object?>{'mode': 'exam', 'drawCount': count},
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(
        find.text('$count 题套卷'),
        findsOneWidget,
        reason: 'drawCount=$count 标题',
      );
      expect(find.text(meta), findsOneWidget, reason: 'drawCount=$count 元信息');
      expect(
        find.text('题量待接口 · 进度待接口'),
        findsNWidgets(5),
        reason: 'drawCount=$count 模块行（与 drawCount 无关）',
      );
      expect(find.text(minutes), findsOneWidget, reason: 'drawCount=$count 时长');
    }
  });

  testWidgets('410×890 视口无溢出且开始答题按钮可见', (tester) async {
    await tester.binding.setSurfaceSize(const Size(410, 890));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await loginToHome(tester);

    await tester.tap(_navTab('题库'));
    await tester.pumpAndSettle();
    await tester.tap(_practiceCard);
    await tester.pumpAndSettle();

    expect(find.byType(SetDetailPage), findsOneWidget);
    expect(tester.takeException(), isNull);

    final buttonRect = tester.getRect(
      find.widgetWithText(FilledButton, '开始练习'),
    );
    final screenRect = tester.getRect(find.byType(SetDetailPage));
    expect(screenRect.overlaps(buttonRect), isTrue);
    expect(buttonRect.bottom, lessThanOrEqualTo(screenRect.bottom));
    // F13：按钮是标题以下的内容元素，左右各 md + contentInset。
    expect(
      buttonRect.left,
      closeTo(screenRect.left + AppSpacing.md + AppSpacing.contentInset, 1),
    );
    expect(
      buttonRect.right,
      closeTo(screenRect.right - AppSpacing.md - AppSpacing.contentInset, 1),
    );
    expect(screenRect.bottom - buttonRect.bottom, closeTo(AppSpacing.md, 1));
  });

  testWidgets('深色模式下元信息文字使用品牌说明色', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.dark,
        home: SetDetailPage(
          args: <String, Object?>{'mode': 'exam', 'drawCount': 100},
        ),
      ),
    );
    await tester.pumpAndSettle();

    final statText = tester.widget<Text>(find.text('共 100 题'));
    final statColor = statText.style?.color;
    expect(statColor, isNotNull);
    expect(statColor, isNot(const Color(0xFF334155)));
    expect(statColor, const Color(0xFFD2D2D2));
  });

  testWidgets('深色模式下套卷详情标题使用自适应浅色', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.dark,
        home: SetDetailPage(
          args: <String, Object?>{'mode': 'exam', 'drawCount': 100},
        ),
      ),
    );
    await tester.pumpAndSettle();

    final BuildContext context = tester.element(find.text('100 题套卷'));
    for (final title in <String>['100 题套卷', '知识点考察', 'VLAN', '答题说明']) {
      final text = tester.widget<Text>(find.text(title));
      expect(text.style?.color, AppColors.title(context));
      expect(text.style?.color, isNot(AppColors.brandTitle));
    }
    expect(AppColors.title(context), const Color(0xFFFFFFFF));
  });

  testWidgets('F16 答题说明卡只在考试前置页显示', (tester) async {
    for (final mode in <String>['practice', 'exam']) {
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.light,
          home: SetDetailPage(
            args: <String, Object?>{'mode': mode, 'drawCount': 100},
          ),
        ),
      );
      await tester.pumpAndSettle();

      final expected = mode == 'exam' ? findsOneWidget : findsNothing;
      expect(find.text('答题说明'), expected, reason: 'mode=$mode');
      expect(find.text('限时 60 分钟，超时自动交卷'), expected, reason: 'mode=$mode');
      expect(find.text('交卷后可查看解析与得分'), expected, reason: 'mode=$mode');
      expect(find.text('做错的题自动收入错题本'), expected, reason: 'mode=$mode');
      // 其余内容两种 mode 完全一致。
      expect(find.text('100 题套卷'), findsOneWidget);
      expect(find.text('知识点考察'), findsOneWidget);
      expect(find.text('开始练习'), mode == 'exam' ? findsNothing : findsOneWidget);
      expect(find.text('开始答题'), mode == 'exam' ? findsOneWidget : findsNothing);
    }
  });

  testWidgets('F16 答题说明卡深浅色都跟随主题（深色不再白底白字）', (tester) async {
    for (final theme in <ThemeData>[AppTheme.light, AppTheme.dark]) {
      await tester.pumpWidget(
        MaterialApp(
          theme: theme,
          home: SetDetailPage(
            args: <String, Object?>{'mode': 'exam', 'drawCount': 100},
          ),
        ),
      );
      await tester.pumpAndSettle();

      final context = tester.element(find.text('答题说明'));
      final card = tester.widget<Container>(
        find
            .ancestor(of: find.text('答题说明'), matching: find.byType(Container))
            .first,
      );
      final decoration = card.decoration! as BoxDecoration;
      final borderColor = (decoration.border! as Border).top.color;
      final isDark = theme.brightness == Brightness.dark;
      // 卡面 / 边框用亮度感知 token；浅色值与旧 brandSurface/brandBorder 相同。
      expect(decoration.color, AppColors.cardSurface(context));
      expect(borderColor, AppColors.cardBorder(context));
      expect(
        decoration.color,
        isDark ? const Color(0xFF2B2B2B) : const Color(0xFFFFFFFF),
      );
      expect(
        borderColor,
        isDark ? const Color(0xFF4D4D4D) : const Color(0xFFE9E9E9),
      );
      // 深色下标题白字对 #2B2B2B 卡面、正文 #D2D2D2，均可读。
      final title = tester.widget<Text>(find.text('答题说明'));
      expect(
        title.style?.color,
        isDark ? const Color(0xFFFFFFFF) : const Color(0xFF111111),
      );
      final body = tester.widget<Text>(find.text('限时 60 分钟，超时自动交卷'));
      expect(
        body.style?.color,
        isDark ? const Color(0xFFD2D2D2) : const Color(0xFF2B2B2B),
      );
    }
  });

  testWidgets('F16 知识点考察题量来自清单重叠模块，缺数据显示待接口', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light,
        home: SetDetailPage(
          args: <String, Object?>{
            'mode': 'exam',
            'drawCount': 100,
            'setId': 'h3cne-2026-01',
          },
          manifestService: MockBankManifestService(
            manifest: BankManifest.fromJson(_liveManifestJson),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    // VLAN / OSPF / ACL 与清单重叠 → 真实题量 100；进度无真实数据 → 待接口。
    expect(find.text('100 题 · 进度待接口'), findsNWidgets(3));
    // NAT / 子网划分 清单里没有 → 题量也待接口，绝不均分虚构。
    expect(find.text('题量待接口 · 进度待接口'), findsNWidgets(2));
    final progressBars = find.descendant(
      of: find.byType(SetDetailPage),
      matching: find.byType(FractionallySizedBox),
    );
    expect(progressBars, findsNWidgets(5));
    for (final element in progressBars.evaluate()) {
      expect((element.widget as FractionallySizedBox).widthFactor, 0.0);
    }
  });

  testWidgets('F16 预留套卷统计接口就绪后优先于清单', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light,
        home: SetDetailPage(
          args: <String, Object?>{
            'mode': 'exam',
            'drawCount': 100,
            'setId': 'h3cne-2026-01',
          },
          manifestService: MockBankManifestService(
            manifest: BankManifest.fromJson(_liveManifestJson),
          ),
          questionRepository: _SetStatsRepository(),
        ),
      ),
    );
    await tester.pumpAndSettle();

    // VLAN 用套卷级统计：40 题、10/40 = 25%。
    expect(find.text('40 题 · 25%'), findsOneWidget);
    // OSPF / ACL 仍回退清单题量；NAT / 子网划分 仍待接口。
    expect(find.text('100 题 · 进度待接口'), findsNWidgets(2));
    expect(find.text('题量待接口 · 进度待接口'), findsNWidgets(2));
    final vlanBar = tester.widget<FractionallySizedBox>(
      find
          .descendant(
            of: find.byType(SetDetailPage),
            matching: find.byType(FractionallySizedBox),
          )
          .first,
    );
    expect(vlanBar.widthFactor, 0.25);
  });

  test('F16 预留套卷统计接口默认返回空（后端未就绪，不虚构数字）', () async {
    final repo = MockQuestionRepository();
    expect(await repo.getSetModuleStats(setId: 'h3cne-2026-01'), isEmpty);
    expect(await repo.getSetModuleStats(setId: 'VLAN'), isEmpty);
    expect(await repo.getSetOverview(setId: 'VLAN'), isNull);
  });

  testWidgets('F19 概览接口就绪：题型标签与已答题数显示真实值（练习）', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light,
        home: SetDetailPage(
          args: <String, Object?>{
            'mode': 'practice',
            'drawCount': 100,
            'setId': 'VLAN',
            'setTitle': 'VLAN',
          },
          questionRepository: _OverviewRepository(),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('单选 90 题'), findsOneWidget);
    expect(find.text('多选 30 题'), findsOneWidget);
    // 用户 2026-11-14 要求：练习前置页用“已答题数：X”。
    expect(find.text('已答题数：120'), findsOneWidget);
    expect(find.text('练习目标'), findsOneWidget);
    expect(find.text('20 题'), findsOneWidget);
    expect(find.text('开始练习'), findsOneWidget);
  });

  testWidgets('F19 概览接口就绪：考试前置页显示已完成/剩余且无练习目标', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light,
        home: SetDetailPage(
          args: <String, Object?>{
            'mode': 'exam',
            'drawCount': 100,
            'setId': 'h3cne-2026-01',
            'setTitle': 'A卷',
          },
          questionRepository: _OverviewRepository(),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('已完成 120 题 · 剩余 530 题'), findsOneWidget);
    expect(find.text('练习目标'), findsNothing);
    expect(find.text('开始答题'), findsOneWidget);
  });

  testWidgets('F19 概览接口未就绪：题型与完成情况显示待接口，不写 0', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light,
        home: SetDetailPage(
          args: <String, Object?>{
            'mode': 'practice',
            'drawCount': 100,
            'setId': 'VLAN',
          },
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('题型待接口'), findsOneWidget);
    expect(find.text('完成情况待接口'), findsOneWidget);
    expect(find.textContaining('单选 0'), findsNothing);
    expect(find.textContaining('多选 0'), findsNothing);
  });

  testWidgets('F19 答题记录卡是最后一个内容块且与前置页同宽', (tester) async {
    await tester.binding.setSurfaceSize(const Size(410, 890));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    final kv = InMemoryKvStore();
    final recordService = KvAnswerRecordService(kvStore: kv);
    final now = DateTime.now().millisecondsSinceEpoch;
    recordService.upsert(
      AnswerRecord(
        id: 'rec-1',
        setId: 'VLAN',
        setTitle: 'VLAN',
        mode: 'practice',
        kind: 'completion',
        targetCount: 20,
        answeredCount: 20,
        totalCount: 100,
        correctCount: 16,
        durationMs: 60000,
        createdAt: now,
        updatedAt: now,
      ),
    );

    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light,
        home: SetDetailPage(
          args: <String, Object?>{
            'mode': 'practice',
            'drawCount': 100,
            'setId': 'VLAN',
            'setTitle': 'VLAN',
          },
          recordService: recordService,
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('答题记录'), findsOneWidget);
    expect(find.text('已完成 · 20/20 题'), findsOneWidget);
    expect(find.text('正确率 80%'), findsOneWidget);
    expect(tester.takeException(), isNull);

    final cardRect = tester.getRect(find.byType(AnswerRecordsCard));
    final targetRect = tester.getRect(find.text('练习目标'));
    expect(cardRect.width, closeTo(348, 1));
    expect(cardRect.top, greaterThan(targetRect.bottom));
  });
}
