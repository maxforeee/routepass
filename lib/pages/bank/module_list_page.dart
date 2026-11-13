/// 题库页（规格文档第 3 章 §22.5：Q-01–Q-09；R4 按 04_bank mockup 重绘）。
///
/// 页头只有「题库」标题，下面是搜索条（保留的既有功能），再下面是「练习 /
/// 考试」切换行（F5 按用户 1:1 参考稿新增，只做排版）：练习 tab 显示 4 张
/// 套卷卡，考试 tab 显示 6 张模拟卷占位卡；输入搜索后切换为题目结果列表。
/// （G2b：筛选 chips 已按 canva 参考移除，文本搜索行为不变。F8：标题改为与
/// 知识库 / 工具箱相同的 PageHeader（22 粗体 + 副标题），与搜索条左缘对齐，
/// 头像只在首页，模块标签按 canva 参考排成 3 列两行。）
library;

import 'package:flutter/material.dart';

import '../../core/service_locator.dart';
import '../../core/modules.dart';
import '../../core/theme.dart';
import '../../models/question.dart';
import '../../models/stats.dart';
import '../../router/app_router.dart';
import '../../widgets/page_header.dart';
import '../../widgets/set_row_card.dart';
import '../../widgets/set_row_tags.dart';

/// 题库页的两个 tab（练习 / 考试）。
enum _BankTab { practice, exam }

class BankModuleListPage extends StatefulWidget {
  const BankModuleListPage({super.key});

  @override
  State<BankModuleListPage> createState() => BankModuleListPageState();
}

class BankModuleListPageState extends State<BankModuleListPage> {
  List<ModuleStat> _modules = const <ModuleStat>[];
  List<Question> _samples = const <Question>[];
  String _query = '';
  _BankTab _tab = _BankTab.practice;

  @override
  void initState() {
    super.initState();
    _load();
  }

  /// tab 切回时刷新（重拉模块 / 样题）。
  Future<void> refresh() => _load();

  Future<void> _load() async {
    try {
      final modules = await ServiceLocator.questionRepository.getModules();
      final samples = await ServiceLocator.questionRepository.drawQuestions(
        mode: 'practice',
        drawCount: 100,
      );
      if (!mounted) return;
      setState(() {
        _modules = modules;
        _samples = samples;
      });
    } catch (_) {}
  }

  List<Question> get _filtered => _query.isEmpty
      ? _samples
      : _samples.where((q) => q.stem.contains(_query)).toList();

  void _openSetDetail(int drawCount) {
    Navigator.of(context).pushNamed(
      AppRoutes.bankSetDetail,
      arguments: <String, Object?>{'mode': 'exam', 'drawCount': drawCount},
    );
  }

  String _typeLabel(String type) {
    return switch (type) {
      'single' => '单选',
      'multiple' => '多选',
      'judge' => '判断',
      'fill' => '填空',
      _ => type,
    };
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      backgroundColor: AppColors.pageBackground(context),
      body: SafeArea(
        child: Column(
          // stretch：页头块宽度撑满，标题左缘与搜索条 / 卡片同为 16px。
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(
                AppSpacing.md,
                AppSpacing.sm,
                AppSpacing.md,
                AppSpacing.xs,
              ),
              child: const PageHeader(title: '题库', subtitle: '练习考试'),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(
                AppSpacing.md,
                AppSpacing.xxs,
                AppSpacing.md,
                AppSpacing.cardGap,
              ),
              child: _buildSearchBar(theme),
            ),
            if (_query.isEmpty) _buildTabs(),
            Expanded(
              child: _query.isNotEmpty ? _buildResults(theme) : _buildSets(),
            ),
          ],
        ),
      ),
    );
  }

  /// 搜索条（canva 参考：白色胶囊，高 48，全圆角；右端蓝色圆形搜索按钮）。
  Widget _buildSearchBar(ThemeData theme) {
    return Container(
      height: AppSizes.bankSearchBarHeight,
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.md,
        AppSpacing.xxs,
        AppSpacing.xxs,
        AppSpacing.xxs,
      ),
      decoration: BoxDecoration(
        color: AppColors.cardSurface(context),
        borderRadius: BorderRadius.circular(AppRadii.searchPill),
        border: Border.all(
          color: AppColors.cardBorder(context),
          width: AppSizes.borderWidth,
        ),
      ),
      child: Row(
        children: [
          Expanded(
            child: TextField(
              style: theme.textTheme.labelLarge?.copyWith(
                color: AppColors.cardTitle(context),
              ),
              decoration: InputDecoration(
                isDense: true,
                border: InputBorder.none,
                contentPadding: EdgeInsets.zero,
                hintText: '搜索题目',
                hintStyle: theme.textTheme.labelLarge?.copyWith(
                  color: AppColors.cardCaption(context),
                ),
              ),
              onChanged: (v) => setState(() => _query = v.trim()),
            ),
          ),
          Container(
            width: AppSizes.bankSearchButtonSize,
            height: AppSizes.bankSearchButtonSize,
            decoration: const BoxDecoration(
              color: AppColors.brandPrimary,
              shape: BoxShape.circle,
            ),
            child: const Icon(
              Icons.search,
              size: AppSizes.icon,
              color: AppColors.brandOnPrimary,
            ),
          ),
        ],
      ),
    );
  }

  /// 「练习 / 考试」切换行：两个 tab 居中、间距 72，上下留 12 / 18。
  Widget _buildTabs() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.md,
        AppSpacing.bankTabsPaddingTop,
        AppSpacing.md,
        AppSpacing.bankTabsPaddingBottom,
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          _buildTab('练习', _BankTab.practice),
          const SizedBox(width: AppSpacing.bankTabGap),
          _buildTab('考试', _BankTab.exam),
        ],
      ),
    );
  }

  /// 单个 tab = 20px 标签 + 下方渐隐虚线指示线（不是搜索元素）。
  Widget _buildTab(String label, _BankTab tab) {
    final active = _tab == tab;
    // 选中态用深浅色自适应的标题色，未选中用弱提示色；指示线跟随标签色。
    final color = active
        ? AppColors.cardTitle(context)
        : AppColors.cardCaption(context);
    final style = TextStyle(
      fontSize: AppFontSizes.bankTabLabel,
      fontWeight: active ? FontWeight.w800 : FontWeight.w500,
      color: color,
      height: AppSizes.bankTabLabelHeight,
    );
    final labelWidth = _measureLabelWidth(label, style);
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () {
        if (_tab != tab) setState(() => _tab = tab);
      },
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(label, style: style),
          const SizedBox(height: AppSizes.bankTabLineGap),
          SizedBox(
            width: labelWidth + AppSizes.bankTabLineOverhang * 2,
            height: AppSizes.bankTabLineHeight,
            child: CustomPaint(
              painter: _TabLinePainter(
                color: color,
                opacity: active ? 1 : AppSizes.bankTabLineInactiveOpacity,
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// 量出标签文字宽度，指示线按「标签宽 + 两侧各 10」铺开。
  double _measureLabelWidth(String label, TextStyle style) {
    final painter = TextPainter(
      text: TextSpan(text: label, style: style),
      textDirection: TextDirection.ltr,
    )..layout();
    return painter.width;
  }

  Widget _buildSets() {
    return _tab == _BankTab.exam ? _buildExamSets() : _buildPracticeSets();
  }

  Widget _buildPracticeSets() {
    final modules = _modules.isEmpty
        ? kModuleOrder
        : _modules.map((m) => m.module).toList();
    final tags = SetRowTags(labels: modules.map(moduleLabel).toList());

    return ListView(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.md,
        AppSpacing.sm,
        AppSpacing.md,
        AppSizes.homeBottomPad,
      ),
      children: [
        SetRowCard(
          title: '100 题套卷',
          subtitle: '100 题 · 5 个模块 · 含解析',
          trailing: tags,
          onTap: () => _openSetDetail(100),
        ),
        const SizedBox(height: AppSpacing.cardGap),
        SetRowCard(
          title: '200 题套卷',
          subtitle: '200 题 · 5 个模块 · 含解析',
          trailing: tags,
          onTap: () => _openSetDetail(200),
        ),
        const SizedBox(height: AppSpacing.cardGap),
        SetRowCard(
          title: '50 题套卷',
          subtitle: '50 题 · 5 个模块 · 含解析',
          trailing: tags,
          onTap: () => _openSetDetail(50),
        ),
        const SizedBox(height: AppSpacing.cardGap),
        SetRowCard(
          title: '10 题速练',
          subtitle: '10 题 · 5 个模块 · 含解析',
          trailing: tags,
          onTap: () => _openSetDetail(10),
        ),
      ],
    );
  }

  /// 考试 tab：模拟卷卡。卷名与标签是占位排版内容（真实卷子等后端题库
  /// 数据），不接数据源、不做异步加载。
  Widget _buildExamSets() {
    const titles = <String>[
      'H3CNE 模拟卷 01',
      'H3CNE 模拟卷 02',
      'H3CNE 模拟卷 03',
      'H3CNE 模拟卷 04',
      'H3CNE 模拟卷 05',
      'H3CNE 模拟卷 06',
    ];
    const tags = SetRowTags(labels: ['综合', 'H3CNE', '模拟', '60分钟', '100题']);

    return ListView(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.md,
        AppSpacing.sm,
        AppSpacing.md,
        AppSizes.homeBottomPad,
      ),
      children: [
        for (var i = 0; i < titles.length; i++) ...[
          if (i > 0) const SizedBox(height: AppSpacing.cardGap),
          SetRowCard(
            title: titles[i],
            subtitle: '100 题 · 60 分钟 · 含解析',
            trailing: tags,
            onTap: () => _openSetDetail(100),
          ),
        ],
      ],
    );
  }

  Widget _buildResults(ThemeData theme) {
    final results = _filtered;
    if (results.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.search_off_outlined,
              size: AppSizes.emptyStateIcon,
              color: theme.colorScheme.onSurfaceVariant,
            ),
            const SizedBox(height: AppSpacing.sm),
            Text('没有找到相关题目', style: theme.textTheme.bodyMedium),
          ],
        ),
      );
    }
    return ListView.builder(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.md,
        AppSpacing.sm,
        AppSpacing.md,
        AppSizes.homeBottomPad,
      ),
      itemCount: results.length,
      itemBuilder: (context, index) {
        final q = results[index];
        return Card(
          margin: const EdgeInsets.only(bottom: AppSpacing.xs),
          elevation: 0,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(AppRadii.card),
            side: BorderSide(color: theme.colorScheme.outlineVariant),
          ),
          child: ListTile(
            title: Text(q.stem, maxLines: 2, overflow: TextOverflow.ellipsis),
            subtitle: Text('${moduleLabel(q.module)} · ${_typeLabel(q.type)}'),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => Navigator.of(context).pushNamed(
              AppRoutes.bankQuiz,
              arguments: <String, Object?>{
                'mode': 'single',
                'questionId': q.id,
              },
            ),
          ),
        );
      },
    );
  }
}

/// tab 下方的渐隐虚线指示线（虚线段 + 两端平滑渐隐）。
class _TabLinePainter extends CustomPainter {
  const _TabLinePainter({required this.color, required this.opacity});

  final Color color;
  final double opacity;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..strokeWidth = size.height
      ..strokeCap = StrokeCap.butt;
    final period = AppSizes.bankTabDash + AppSizes.bankTabDashGap;
    for (var x = 0.0; x < size.width; x += period) {
      final end = (x + AppSizes.bankTabDash).clamp(0.0, size.width);
      final fade = _fadeAt((x + end) / 2 / size.width);
      if (fade <= 0) continue;
      paint.color = color.withValues(alpha: opacity * fade);
      canvas.drawLine(
        Offset(x, size.height / 2),
        Offset(end, size.height / 2),
        paint,
      );
    }
  }

  /// 两端渐隐包络：0% 透明 → 14% 25% → 30%–70% 全显 → 86% 25% → 100% 透明。
  double _fadeAt(double t) {
    const stops = <double>[0, 0.14, 0.30, 0.70, 0.86, 1];
    const alphas = <double>[0, 0.25, 1, 1, 0.25, 0];
    for (var i = 1; i < stops.length; i++) {
      if (t <= stops[i]) {
        final span = stops[i] - stops[i - 1];
        final ratio = span == 0 ? 1.0 : (t - stops[i - 1]) / span;
        return alphas[i - 1] + (alphas[i] - alphas[i - 1]) * ratio;
      }
    }
    return 0;
  }

  @override
  bool shouldRepaint(_TabLinePainter oldDelegate) =>
      oldDelegate.color != color || oldDelegate.opacity != opacity;
}
