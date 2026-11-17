/// 套卷详情页（R5：09_set_detail mockup）。
///
/// 从题库页的套卷卡进入，展示套卷规模、模块进度与答题说明；
/// “开始答题”再进答题页。四套卷（100/200/50/10）共用本模板，
/// 标题 / 单选多选 / 时长由路由参数 drawCount 推导；知识点考察的
/// 题量与进度来自真实数据（F16/F26）：优先预留的套卷统计接口，其次
/// 模块接口（GET /bank/modules）的真实模块与题量，再次题库清单
/// practiceByModule 的重叠模块，取不到就显示“待接口”。
/// 答题说明卡只在考试（mode=exam）前置页显示（F16）。
library;

import 'package:flutter/material.dart';

import '../../core/service_locator.dart';
import '../../core/modules.dart';
import '../../core/theme.dart';
import '../../models/answer_record.dart';
import '../../models/bank_manifest.dart';
import '../../models/stats.dart';
import '../../router/app_router.dart';
import '../../services/bank/answer_entry_preload.dart';
import '../../services/bank/answer_record_service.dart';
import '../../services/bank/answer_session_service.dart';
import '../../services/bank/bank_manifest_service.dart';
import '../../services/bank/practice_service.dart';
import '../../services/bank/question_repo.dart';
import '../../services/bank/set_detail_preload.dart';
import '../../widgets/answer_records_card.dart';
import '../../widgets/loading_skeleton.dart';
import '../../widgets/reserved_slot.dart';

class SetDetailPage extends StatefulWidget {
  const SetDetailPage({
    super.key,
    required this.args,
    this.manifestService,
    this.questionRepository,
    this.recordService,
    this.sessionService,
    this.practiceService,
  });

  final Map<String, Object?> args;

  /// 测试可注入 Mock；生产环境不传，走 ServiceLocator 里的 HTTP 实现。
  final BankManifestService? manifestService;

  /// 测试可注入 Mock；生产环境不传，走 ServiceLocator 里的实现。
  final QuestionRepository? questionRepository;

  /// 测试可注入；生产环境不传，走 ServiceLocator。
  final AnswerRecordService? recordService;
  final AnswerSessionService? sessionService;

  /// F27 答题入口预热用；测试可注入，生产懒解析 ServiceLocator。
  final PracticeService? practiceService;

  @override
  State<SetDetailPage> createState() => _SetDetailPageState();
}

class _SetDetailPageState extends State<SetDetailPage> {
  List<ModuleStat> _modules = const <ModuleStat>[];
  List<ModuleStat> _setStats = const <ModuleStat>[];
  BankManifest? _manifest;
  BankSetOverview? _overview;
  List<AnswerRecord> _records = const <AnswerRecord>[];
  AnswerRecord? _breakpoint;
  int _practiceTarget = 20;

  /// F27：首屏网络数据未就绪时，动态区块显示同尺寸骨架，就绪后淡入。
  /// 预加载命中时 initState 即置 false，打开即真实内容，无骨架闪烁。
  bool _loading = true;

  late final BankManifestService _manifestService;
  late final QuestionRepository _questionRepository;
  late final AnswerRecordService _recordService;
  late final AnswerSessionService _sessionService;

  /// 套卷规模：路由参数 drawCount（100/200/50/10）。
  int get _drawCount =>
      widget.args['drawCount'] is int ? widget.args['drawCount'] as int : 100;

  /// 时长估算：每题 0.6 分钟，四舍五入。
  int get _minutes => (_drawCount * 0.6).round();

  /// F16：答题说明卡只出现在考试前置页（mode=exam），练习页不显示。
  bool get _isExam => widget.args['mode'] == 'exam';

  /// 套卷标识（F16）：考试卷 id 或练习模块代码，供预留统计接口使用。
  String? get _setId => widget.args['setId'] as String?;

  /// 套卷标题：练习 = 模块中文名；考试优先用上游传入的卷标题。
  String get _setTitle {
    final fromArgs = widget.args['setTitle'] as String?;
    if (fromArgs != null && fromArgs.isNotEmpty) return fromArgs;
    return moduleLabel(_setId ?? '');
  }

  int get _modeTarget => _isExam ? _drawCount : _practiceTarget;

  int get _defaultPracticeTarget => _drawCount < 20 ? _drawCount : 20;

  @override
  void initState() {
    super.initState();
    _manifestService =
        widget.manifestService ?? ServiceLocator.bankManifestService;
    _questionRepository =
        widget.questionRepository ?? ServiceLocator.questionRepository;
    _recordService = widget.recordService ?? ServiceLocator.answerRecordService;
    _sessionService =
        widget.sessionService ?? ServiceLocator.answerSessionService;
    _practiceTarget = _defaultPracticeTarget;
    _bootstrap();
  }

  /// F27：优先消费题库页点按时的预加载——已就绪直接带着数据首帧渲染；
  /// 在途则 await 同一份 Future（不重复发请求）；都没有才走自身 _load。
  /// 记录同步 / 本地记录与预加载无关，始终照常执行。
  void _bootstrap() {
    final setId = _setId;
    if (setId != null) {
      final ready = SetDetailPreload.take(setId);
      if (ready != null) {
        _applyPreload(ready);
        _loading = false;
        _syncRecords(setId);
        _preloadAnswerEntry();
        return;
      }
      final pending = SetDetailPreload.pending(setId);
      if (pending != null) {
        pending
            .then((data) {
              if (!mounted) return;
              setState(() {
                _applyPreload(data);
                _loading = false;
              });
            })
            .catchError((Object _) {
              if (mounted) _load();
            });
        _syncRecords(setId);
        _preloadAnswerEntry();
        return;
      }
    }
    _load();
    _preloadAnswerEntry();
  }

  void _applyPreload(SetDetailPreloadData data) {
    _modules = data.modules;
    _manifest = data.manifest;
    _setStats = data.setStats;
    _overview = data.overview;
  }

  /// F27 预测性预加载：前置页最可能的下一步是「开始练习」，后台预热
  /// 答题页（QuizPage）首题要用的本地题库——冷缓存抽题原本要等整套题库
  /// 拉取，预热后首题命中本地即开。考试不预热：startExamPaper 会在服务端
  /// 创建考卷，不能预创建。依赖懒解析 + 容错，失败静默，不阻塞页面。
  void _preloadAnswerEntry() {
    if (_isExam) return;
    final setId = _setId;
    if (setId == null || setId.isEmpty) return;
    try {
      final practice = widget.practiceService ?? ServiceLocator.practiceService;
      AnswerEntryPreload.start(setId: setId, service: practice);
    } catch (_) {}
  }

  Future<void> _load() async {
    try {
      final modules = await _questionRepository.getModules();
      if (!mounted) return;
      setState(() => _modules = modules);
    } catch (_) {}
    try {
      final manifest = await _manifestService.fetchManifest();
      if (!mounted) return;
      setState(() => _manifest = manifest);
    } catch (_) {}
    final setId = _setId;
    if (setId == null) {
      if (mounted) setState(() => _loading = false);
      return;
    }
    try {
      final stats = await _questionRepository.getSetModuleStats(setId: setId);
      if (!mounted) return;
      setState(() => _setStats = stats);
    } catch (_) {}
    try {
      final overview = await _questionRepository.getSetOverview(setId: setId);
      if (!mounted) return;
      setState(() => _overview = overview);
    } catch (_) {}
    if (mounted) setState(() => _loading = false);
    await _syncRecords(setId);
  }

  Future<void> _syncRecords(String setId) async {
    // S11 `GET /practice/records`：在线时以服务端记录为准（完成会话 + 断点），
    // 失败静默；本地 kv 记录照常展示。
    try {
      await _recordService.syncFromServer();
    } catch (_) {}
    _loadRecords(setId);
  }

  void _loadRecords(String setId) {
    try {
      final mode = _isExam ? 'exam' : 'practice';
      final records = _recordService.recordsFor(setId: setId, mode: mode);
      final breakpoint = _recordService.breakpointOf(setId: setId, mode: mode);
      final session = _sessionService.load(setId: setId, mode: mode);
      if (!mounted) return;
      setState(() {
        _records = records;
        _breakpoint = breakpoint;
        if (!_isExam &&
            session != null &&
            session.targetCount > 0 &&
            session.answeredCount < session.targetCount) {
          _practiceTarget = _clampTarget(session.targetCount);
        }
      });
    } catch (_) {}
  }

  int _clampTarget(int value) {
    const step = 5;
    final max = _drawCount;
    final min = _drawCount < step ? _drawCount : step;
    var clamped = value.clamp(min, max).toInt();
    if (max >= step) {
      clamped = (clamped ~/ step) * step;
      if (clamped < step) clamped = step;
      if (clamped > max) clamped = max;
    }
    return clamped;
  }

  void _changeTarget(int delta) {
    final next = _clampTarget(_practiceTarget + delta);
    if (next == _practiceTarget) return;
    setState(() => _practiceTarget = next);
    try {
      ServiceLocator.kvStore.setString(
        'answer.target',
        _practiceTarget.toString(),
      );
    } catch (_) {}
  }

  void _start() {
    Navigator.of(context).pushNamed(
      AppRoutes.bankAnswer,
      arguments: <String, Object?>{
        'mode': _isExam ? 'exam' : 'practice',
        'setId': _setId,
        'setTitle': _setTitle,
        'drawCount': _drawCount,
        'target': _modeTarget,
      },
    );
  }

  /// F25：记录行进详情页（摘要 + 删除）；返回后重读记录，
  /// 详情页删掉的记录（含断点）立即从列表与「继续练习」里消失。
  Future<void> _openRecord(AnswerRecord record) async {
    await Navigator.of(context).pushNamed(
      AppRoutes.bankRecordDetail,
      arguments: <String, Object?>{'record': record},
    );
    final setId = _setId;
    if (!mounted || setId == null) return;
    _loadRecords(setId);
  }

  String get _startLabel {
    final bp = _breakpoint;
    if (bp != null && bp.isBreakpoint) {
      final target = _isExam ? _drawCount : _practiceTarget;
      return '${_isExam ? '继续答题' : '继续练习'} (${bp.answeredCount}/$target)';
    }
    return _isExam ? '开始答题' : '开始练习';
  }

  /// 展示模块顺序（优先题库模块接口：真实后端返回真实模块名，含
  /// H3CNE / 基础知识 / 子网 等本地五模块之外的名字，原样展示；
  /// Mock 兜底返回 5 个同序模块）。
  List<String> get _displayModules {
    if (_modules.isNotEmpty) {
      return _modules.map((m) => m.module).toList();
    }
    return kModuleOrder;
  }

  ModuleStat? _statOf(List<ModuleStat> stats, String module) {
    for (final s in stats) {
      if (s.module == module) return s;
    }
    return null;
  }

  /// 每模块题量（F16/F26）：优先预留套卷统计接口，其次模块接口
  /// （GET /bank/modules）的真实题量，再次清单 practiceByModule 里与展示
  /// 模块重叠的真实题量；都取不到返回 null（UI 显示“题量待接口”），
  /// 不再按 drawCount 均分虚构。
  int? _moduleCount(String module) {
    final setStat = _statOf(_setStats, module);
    if (setStat != null && setStat.total > 0) return setStat.total;
    final moduleStat = _statOf(_modules, module);
    if (moduleStat != null && moduleStat.total > 0) return moduleStat.total;
    final manifest = _manifest;
    if (manifest != null) {
      for (final set in manifest.practiceSets) {
        if (set.module == module) return set.questionCount;
      }
    }
    return null;
  }

  /// 模块进度（0–1，F16/F26）：只有 total>0 才计算 answered/total；
  /// 模块接口只给题量（answered 恒 0 = 未知），不能把 0% 当真实进度，
  /// 无真实已答数返回 null（UI 显示“进度待接口”），不虚构 0%。
  double? _moduleProgress(String module) {
    final setStat = _statOf(_setStats, module);
    if (setStat != null && setStat.total > 0) {
      return (setStat.answered / setStat.total).clamp(0.0, 1.0);
    }
    final stat = _statOf(_modules, module);
    if (stat == null || stat.total <= 0 || stat.answered <= 0) return null;
    return (stat.answered / stat.total).clamp(0.0, 1.0);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final modules = _displayModules;
    return Scaffold(
      backgroundColor: AppColors.pageBackground(context),
      body: SafeArea(
        bottom: true,
        child: Stack(
          children: [
            Column(
              children: [
                Align(
                  alignment: Alignment.centerLeft,
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: AppSpacing.xs,
                    ),
                    child: IconButton(
                      icon: const Icon(
                        Icons.chevron_left,
                        size: AppSizes.iconLarge,
                      ),
                      tooltip: '返回',
                      onPressed: () => Navigator.of(context).pop(),
                    ),
                  ),
                ),
                Expanded(
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.fromLTRB(
                      AppSpacing.md,
                      AppSpacing.xs,
                      AppSpacing.md,
                      // 底部只为本页钉住按钮留位（导航已按 Q1 隐藏）。
                      AppSizes.buttonHeight + AppSpacing.md * 2,
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          '$_drawCount 题套卷',
                          style: theme.textTheme.headlineLarge?.copyWith(
                            fontSize: AppFontSizes.detailTitle,
                            fontWeight: FontWeight.w800,
                            color: AppColors.title(context),
                          ),
                        ),
                        const SizedBox(height: AppSpacing.xs),
                        // 大标题保持 md 页边距；标题以下内容每侧再内缩
                        // contentInset，离屏幕边 md + contentInset。
                        Padding(
                          padding: const EdgeInsets.symmetric(
                            horizontal: AppSpacing.contentInset,
                          ),
                          child: _MetaRow(drawCount: _drawCount),
                        ),
                        const SizedBox(height: AppSpacing.xs),
                        Padding(
                          padding: const EdgeInsets.symmetric(
                            horizontal: AppSpacing.contentInset,
                          ),
                          // F27 fix round 5：骨架与真实行同一 Wrap（同 spacing /
                          // runSpacing），占位是两枚隐形真实 [_TypePill]（两位数
                          // 题量），换行行为与就绪态一致；shimmer 只作 pill 形
                          // 覆盖层，数据到达不产生纵向位移。
                          child: SkeletonToContent(
                            loaded: !_loading,
                            skeleton: Wrap(
                              spacing: AppSpacing.xs,
                              runSpacing: AppSpacing.xxs,
                              children: [
                                for (final label in const [
                                  '单选 00 题',
                                  '多选 00 题',
                                ])
                                  Stack(
                                    children: [
                                      ExcludeSemantics(
                                        child: Opacity(
                                          opacity: 0,
                                          child: _TypePill(
                                            label: label,
                                            accent: false,
                                          ),
                                        ),
                                      ),
                                      const Positioned.fill(
                                        child: LoadingSkeleton(
                                          height: AppSizes.typeTagHeight,
                                          borderRadius: 999,
                                        ),
                                      ),
                                    ],
                                  ),
                              ],
                            ),
                            child: _TypeTagsRow(overview: _overview),
                          ),
                        ),
                        const SizedBox(height: AppSpacing.xs),
                        Padding(
                          padding: const EdgeInsets.symmetric(
                            horizontal: AppSpacing.contentInset,
                          ),
                          // F27：骨架按就绪态的两行文案占位（同行盒同间距），
                          // 内容到达不产生纵向位移。
                          child: SkeletonToContent(
                            loaded: !_loading,
                            skeleton: _DoneRow.skeleton(context),
                            child: _DoneRow(
                              isExam: _isExam,
                              overview: _overview,
                            ),
                          ),
                        ),
                        const SizedBox(height: AppSpacing.md),
                        Padding(
                          padding: const EdgeInsets.symmetric(
                            horizontal: AppSpacing.contentInset,
                          ),
                          child: Container(
                            height: AppSizes.divider,
                            color: AppColors.cardBorder(context),
                          ),
                        ),
                        const SizedBox(height: AppSpacing.md),
                        Padding(
                          padding: const EdgeInsets.symmetric(
                            horizontal: AppSpacing.contentInset,
                          ),
                          child: const ReservedSlot(),
                        ),
                        const SizedBox(height: AppSpacing.lg),
                        Padding(
                          padding: const EdgeInsets.symmetric(
                            horizontal: AppSpacing.contentInset,
                          ),
                          child: Text(
                            '知识点考察',
                            style: theme.textTheme.titleMedium?.copyWith(
                              fontSize: AppFontSizes.detailSectionTitle,
                              fontWeight: FontWeight.bold,
                              color: AppColors.title(context),
                            ),
                          ),
                        ),
                        const SizedBox(height: AppSpacing.md),
                        for (final module in modules) ...[
                          Padding(
                            padding: const EdgeInsets.symmetric(
                              horizontal: AppSpacing.contentInset,
                            ),
                            // F27：骨架与模块行同构（标题行 + 间距 + 进度条），
                            // 高度逐段一致，数据到达不产生纵向位移。sizer 用
                            // 真实模块名，保证行盒字体度量与就绪态一致。
                            child: SkeletonToContent(
                              loaded: !_loading,
                              skeleton: _ModuleRow.skeleton(
                                context,
                                name: moduleLabel(module),
                              ),
                              child: _ModuleRow(
                                name: moduleLabel(module),
                                count: _moduleCount(module),
                                progress: _moduleProgress(module),
                              ),
                            ),
                          ),
                          if (module != modules.last)
                            const SizedBox(
                              height: AppSpacing.setDetailModuleGap,
                            ),
                        ],
                        // F19：练习目标是本次会话参数，仅 practice 前置页显示。
                        if (!_isExam) ...[
                          const SizedBox(height: AppSpacing.lg),
                          Padding(
                            padding: const EdgeInsets.symmetric(
                              horizontal: AppSpacing.contentInset,
                            ),
                            child: _PracticeTargetRow(
                              target: _practiceTarget,
                              onMinus: () => _changeTarget(-5),
                              onPlus: () => _changeTarget(5),
                            ),
                          ),
                        ],
                        // F16：答题说明卡只在考试前置页显示。
                        if (_isExam) ...[
                          const SizedBox(height: AppSpacing.lg),
                          Padding(
                            padding: const EdgeInsets.symmetric(
                              horizontal: AppSpacing.contentInset,
                            ),
                            child: _InstructionsCard(minutes: _minutes),
                          ),
                        ],
                        // F19：答题记录卡是最后一个内容块（无套卷入口时隐藏）。
                        if (_setId != null) ...[
                          const SizedBox(height: AppSpacing.lg),
                          Padding(
                            padding: const EdgeInsets.symmetric(
                              horizontal: AppSpacing.contentInset,
                            ),
                            child: AnswerRecordsCard(
                              records: _records.take(10).toList(),
                              onContinue: _records.any((r) => r.isBreakpoint)
                                  ? _start
                                  : null,
                              onRecordTap: _openRecord,
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                ),
              ],
            ),
            Positioned(
              left: AppSpacing.md + AppSpacing.contentInset,
              right: AppSpacing.md + AppSpacing.contentInset,
              // 导航已隐藏：按钮贴 SafeArea 底边，只留常规间距。
              bottom: AppSpacing.md,
              child: SizedBox(
                width: double.infinity,
                height: AppSizes.buttonHeight,
                child: FilledButton(
                  onPressed: _start,
                  style: FilledButton.styleFrom(
                    backgroundColor: AppColors.accent(context),
                    foregroundColor: AppColors.brandSurface,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(
                        AppRadii.setDetailStartButton,
                      ),
                    ),
                    textStyle: theme.textTheme.bodyLarge?.copyWith(
                      fontSize: AppFontSizes.detailButton,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  child: Text(_startLabel),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// 元信息行：左副标题，右“共 N 题”（13px），基线对齐。
/// F19：删除按 3:1 编造的单选/多选数字，题型分布改由 [_TypeTagsRow]
/// 从 overview.byType 展示。
class _MetaRow extends StatelessWidget {
  const _MetaRow({required this.drawCount});

  final int drawCount;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Row(
      crossAxisAlignment: CrossAxisAlignment.baseline,
      textBaseline: TextBaseline.alphabetic,
      children: [
        Expanded(
          child: Text(
            'H3CNE-RS+ 模拟套卷 · 含解析',
            style: theme.textTheme.bodyMedium?.copyWith(
              fontSize: AppFontSizes.detailBody,
              color: AppColors.cardCaption(context),
            ),
          ),
        ),
        Text(
          '共 $drawCount 题',
          style: theme.textTheme.bodyMedium?.copyWith(
            fontSize: AppFontSizes.detailStat,
            color: AppColors.cardCaption(context),
          ),
        ),
      ],
    );
  }
}

/// 题型标签行（F19）：真实分布来自 overview.byType；取不到时整行降级为
/// 一个中性 pill“题型待接口”，绝不按 3:1 推算。
class _TypeTagsRow extends StatelessWidget {
  const _TypeTagsRow({required this.overview});

  final BankSetOverview? overview;

  @override
  Widget build(BuildContext context) {
    final byType = overview?.byType;
    final tags = byType == null
        ? const <String>['题型待接口']
        : <String>['单选 ${byType.single} 题', '多选 ${byType.multiple} 题'];
    return Wrap(
      spacing: AppSpacing.xs,
      runSpacing: AppSpacing.xxs,
      children: [
        for (var i = 0; i < tags.length; i++)
          _TypePill(label: tags[i], accent: byType != null && i == 0),
      ],
    );
  }
}

class _TypePill extends StatelessWidget {
  const _TypePill({required this.label, required this.accent});

  final String label;
  final bool accent;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: AppSizes.typeTagHeight,
      padding: const EdgeInsets.symmetric(horizontal: 10),
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: AppColors.cardSurface(context),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(
          color: accent
              ? AppColors.accent(context)
              : AppColors.cardBorder(context),
        ),
      ),
      child: Text(
        label,
        style: TextStyle(
          fontSize: AppFontSizes.detailStat,
          color: AppColors.cardCaption(context),
        ),
      ),
    );
  }
}

/// F27 fix round 2：骨架文本行——与真实文本占同一个行盒。
///
/// 真实文本行高 = fontSize × 主题行高系数（bodyMedium / bodySmall 的
/// height），并非 fontSize 本身；旧骨架拿 fontSize 当块高，比真实行盒矮，
/// 数据到达就把下方内容整体下推（布局位移）。这里用与真实文本**完全相同
/// 样式**的隐形 Text 撑出真实行盒，shimmer 块居中放在行盒内：占位高度在
/// 任何字体 / 行高设置下都与真实文本逐像素一致，块厚度仍按字号的视觉规格。
/// [sizer] 必须使用真实内容同款 TextStyle（见 _DoneRow / _ModuleRow）。
Widget _skeletonLine({
  required Widget sizer,
  required double blockHeight,
  required double blockWidth,
}) {
  return Stack(
    alignment: Alignment.centerLeft,
    children: [
      ExcludeSemantics(child: Opacity(opacity: 0, child: sizer)),
      LoadingSkeleton(height: blockHeight, width: blockWidth),
    ],
  );
}

/// 已完成 / 剩余题数（F19）。
/// 练习前置页按用户 2026-11-14 要求显示“已答题数：X”，考试前置页显示
/// “已完成 X 题 · 剩余 Y 题”；取不到 overview 时显示“完成情况待接口”，
/// 不写 0、不算假数。
/// F26：overview 就绪时另起一行显示真实正确率；accuracy 为 null（尚无
/// 作答记录 / 数据源无该字段）显示“正确率待接口”，绝不编 0%。
class _DoneRow extends StatelessWidget {
  const _DoneRow({required this.isExam, required this.overview});

  final bool isExam;
  final BankSetOverview? overview;

  /// F27：骨架与真实文本共用同一样式 → 同一行盒高度。
  static TextStyle _textStyle(BuildContext context) => TextStyle(
    fontSize: AppFontSizes.detailStat,
    color: AppColors.cardCaption(context),
  );

  /// F27 fix round 2：两行骨架，行盒与真实文本一致（[_skeletonLine]）。
  static Widget skeleton(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      _skeletonLine(
        sizer: Text(' ', style: _textStyle(context)),
        blockHeight: AppFontSizes.detailStat,
        blockWidth: 180,
      ),
      const SizedBox(height: AppSpacing.xxs),
      _skeletonLine(
        sizer: Text(' ', style: _textStyle(context)),
        blockHeight: AppFontSizes.detailStat,
        blockWidth: 120,
      ),
    ],
  );

  @override
  Widget build(BuildContext context) {
    final overview = this.overview;
    final text = overview == null
        ? '完成情况待接口'
        : isExam
        ? '已完成 ${overview.done} 题 · 剩余 ${overview.remaining} 题'
        : '已答题数：${overview.done}';
    final style = _textStyle(context);
    if (overview == null) return Text(text, style: style);
    final accuracy = overview.accuracy;
    final accuracyText = accuracy == null
        ? '正确率待接口'
        : '正确率 ${(accuracy * 100).toStringAsFixed(1)}%';
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(text, style: style),
        const SizedBox(height: AppSpacing.xxs),
        Text(accuracyText, style: style),
      ],
    );
  }
}

/// 本次练习目标（F19，仅 practice）：步长 5，范围 5…drawCount，默认 20。
class _PracticeTargetRow extends StatelessWidget {
  const _PracticeTargetRow({
    required this.target,
    required this.onMinus,
    required this.onPlus,
  });

  final int target;
  final VoidCallback onMinus;
  final VoidCallback onPlus;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: Text(
            '练习目标',
            style: TextStyle(
              fontSize: AppFontSizes.detailBody,
              color: AppColors.title(context),
            ),
          ),
        ),
        IconButton(
          onPressed: onMinus,
          icon: const Icon(Icons.remove),
          iconSize: AppSizes.icon,
          visualDensity: VisualDensity.compact,
          tooltip: '减少目标',
        ),
        Text(
          '$target 题',
          style: TextStyle(
            fontSize: AppFontSizes.detailBody,
            fontWeight: FontWeight.bold,
            color: AppColors.title(context),
          ),
        ),
        IconButton(
          onPressed: onPlus,
          icon: const Icon(Icons.add),
          iconSize: AppSizes.icon,
          visualDensity: VisualDensity.compact,
          tooltip: '增加目标',
        ),
      ],
    );
  }
}

/// 单个模块行：名称（14 粗）+ 右侧“N 题 · x%”（13 灰）+ 下方进度条。
/// F16：题量 / 进度取不到真实数据时显示“待接口”，进度条不填充。
class _ModuleRow extends StatelessWidget {
  const _ModuleRow({
    required this.name,
    required this.count,
    required this.progress,
  });

  final String name;
  final int? count;
  final double? progress;

  /// F27：骨架与真实文本共用同一样式 → 同一行盒高度。
  static TextStyle _nameStyle(BuildContext context) =>
      Theme.of(context).textTheme.bodyMedium!.copyWith(
        fontSize: AppFontSizes.detailBody,
        fontWeight: FontWeight.bold,
        color: AppColors.title(context),
      );

  static TextStyle _countStyle(BuildContext context) => Theme.of(context)
      .textTheme
      .bodySmall!
      .copyWith(
        fontSize: AppFontSizes.detailStat,
        color: AppColors.cardCaption(context),
      );

  /// F27 fix round 3：骨架行高不再逐元素手工对齐（标题行盒 / 间距 /
  /// 进度条各自拼），而是直接拿真实 [_ModuleRow] 本身做隐形占位 sizer——
  /// 占位高度与就绪态逐像素一致，shimmer 块只作覆盖层（Positioned 不参与
  /// Stack 尺寸），数据到达不产生纵向位移。
  ///
  /// [name] 必须传就绪态将要显示的真实模块名：行盒高度由文本实际落到的
  /// 字体决定，中文模块名与占位空格会落到不同字体/行盒（差约 6px/行），
  /// 用真实名字 + 中文题量占位才能和就绪态走同一套字形度量。
  static Widget skeleton(BuildContext context, {required String name}) => Stack(
    children: [
      ExcludeSemantics(
        child: Opacity(
          opacity: 0,
          child: _ModuleRow(name: name, count: 0, progress: 0),
        ),
      ),
      const Positioned.fill(
        child: IgnorePointer(
          child: Align(
            alignment: Alignment.topLeft,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                LoadingSkeleton(height: AppFontSizes.detailBody, width: 140),
                SizedBox(height: AppSpacing.xs),
                LoadingSkeleton(
                  height: AppSizes.setDetailProgressBarHeight,
                  width: double.infinity,
                ),
              ],
            ),
          ),
        ),
      ),
    ],
  );

  @override
  Widget build(BuildContext context) {
    final countLabel = count == null ? '题量待接口' : '$count 题';
    final progressLabel = progress == null
        ? '进度待接口'
        : '${(progress! * 100).round()}%';
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(child: Text(name, style: _nameStyle(context))),
            Text('$countLabel · $progressLabel', style: _countStyle(context)),
          ],
        ),
        const SizedBox(height: AppSpacing.xs),
        Container(
          height: AppSizes.setDetailProgressBarHeight,
          alignment: Alignment.centerLeft,
          decoration: BoxDecoration(
            color: AppColors.cardBorder(context),
            borderRadius: BorderRadius.circular(AppRadii.setDetailProgressBar),
          ),
          child: FractionallySizedBox(
            widthFactor: (progress ?? 0).clamp(0.0, 1.0),
            child: Container(
              decoration: BoxDecoration(
                color: AppColors.accent(context),
                borderRadius: BorderRadius.circular(
                  AppRadii.setDetailProgressBar,
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

/// 答题说明卡：标题 + 三条说明。
class _InstructionsCard extends StatelessWidget {
  const _InstructionsCard({required this.minutes});

  final int minutes;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final lines = <String>[
      '限时 $minutes 分钟，超时自动交卷',
      '交卷后可查看解析与得分',
      '做错的题自动收入错题本',
    ];
    return Container(
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: AppColors.cardSurface(context),
        borderRadius: BorderRadius.circular(AppRadii.input),
        border: Border.all(color: AppColors.cardBorder(context)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '答题说明',
            style: theme.textTheme.labelLarge?.copyWith(
              fontWeight: FontWeight.bold,
              color: AppColors.title(context),
            ),
          ),
          const SizedBox(height: AppSpacing.xs),
          for (final line in lines) ...[
            Row(
              children: [
                Icon(
                  Icons.check_circle,
                  size: AppSizes.iconSmall,
                  color: AppColors.success(context),
                ),
                const SizedBox(width: AppSpacing.xs),
                Expanded(
                  child: Text(
                    line,
                    style: theme.textTheme.bodyMedium?.copyWith(
                      fontSize: AppFontSizes.detailStat,
                      color: AppColors.label(context),
                    ),
                  ),
                ),
              ],
            ),
            if (line != lines.last) const SizedBox(height: AppSpacing.xs),
          ],
        ],
      ),
    );
  }
}
