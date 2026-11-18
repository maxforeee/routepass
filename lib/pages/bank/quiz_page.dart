/// 前置页进入的逐题答题页（F19）。
///
/// practice / exam 共用同一骨架，只在判分时机上分叉：
/// - practice：逐题抽题，单选/判断点选项即判分（F22：错项红、正确项绿、
///   下方出解析），多选选完点「确认作答」判分；判分先用题目自带答案键，
///   `POST /practice/submit` 在后台补记录并以其结果为准，提交失败只提示、
///   不清空已显示的结果；达标写 completion，未达标退出写 breakpoint。
/// - exam：`POST /exam/start` 拿整卷（不含答案），作答只暂存选项、交卷统一
///   判分；交卷成功写 completion，未交卷退出写 breakpoint 并可恢复。
///
/// 旧 `AnswerPage` 仍服务错题 / 收藏 / 单题 / 每日一练，本页只接前置页。
library;

import 'dart:async';
import 'dart:math';

import 'package:flutter/material.dart';

import '../../core/app_snackbar.dart';
import '../../core/service_locator.dart';
import '../../core/theme.dart';
import '../../models/answer_record.dart';
import '../../models/answer_session_state.dart';
import '../../models/bank_manifest.dart';
import '../../models/knowledge_point.dart';
import '../../models/practice.dart';
import '../../models/question.dart';
import '../../router/app_router.dart';
import '../../services/bank/answer_record_service.dart';
import '../../services/bank/answer_session_service.dart';
import '../../services/bank/bank_manifest_service.dart';
import '../../services/bank/exam_service.dart';
import '../../services/bank/favorite_service.dart';
import '../../services/bank/practice_service.dart';
import '../../services/bank/question_bank_source.dart';
import '../../services/bank/rotation_service.dart';
import '../../services/bank/wrong_service.dart';
import '../../services/knowledge/knowledge_repo.dart';
import '../../widgets/answer_records_card.dart';
import 'answer_widgets.dart';
import 'exam_score_page.dart';

class QuizPage extends StatefulWidget {
  const QuizPage({
    super.key,
    required this.args,
    this.practiceService,
    this.examService,
    this.recordService,
    this.sessionService,
    this.favoriteService,
    this.wrongService,
    this.knowledgeRepository,
    this.rotationService,
    this.manifestService,
  });

  final Map<String, Object?> args;

  /// 测试可注入；生产环境不传，走 ServiceLocator。
  final PracticeService? practiceService;
  final ExamService? examService;
  final AnswerRecordService? recordService;
  final AnswerSessionService? sessionService;
  final FavoriteService? favoriteService;
  final WrongService? wrongService;

  /// F28：7 天轮回服务与题库清单（bankId 来源）；测试可注入。
  final RotationService? rotationService;
  final BankManifestService? manifestService;

  /// F26 chunk 8：判分后知识点 chips 的反查仓储；测试可注入。
  final KnowledgeRepository? knowledgeRepository;

  @override
  State<QuizPage> createState() => _QuizPageState();
}

class _QuizPageState extends State<QuizPage>
    with WidgetsBindingObserver, RouteAware {
  late final PracticeService _practice;
  late final ExamService _exam;
  late final AnswerRecordService _recordService;
  late final AnswerSessionService _sessionService;
  late final FavoriteService _favorite;

  /// F28：rotation 模式（7 天轮回）——整批服务端抽题、逐题服务端判分、
  /// 整批结算；不走 /practice/next 与 /practice/submit，不写本地断点。
  late final RotationService _rotation;
  late final BankManifestService _manifestService;
  late final bool _isRotation;

  /// 空抽 / 清单不可用：诚实待接口态（服务端文案 + 解锁时间）。
  bool _rotationWaiting = false;
  String _rotationMessage = '';
  DateTime? _rotationUnlockAt;

  /// 已结算：退出直接走，不再弹确认（会话已在服务端结算 / 删除）。
  bool _rotationFinished = false;

  /// 判分在途的题目 id：连点选项只提交一次。
  final Set<String> _rotationGrading = <String>{};

  late final bool _isExam;
  late final String _setId;
  late final String _setTitle;
  late final int _total;

  List<Question> _questions = <Question>[];
  final Map<String, List<String>> _answers = <String, List<String>>{};
  final Map<String, AnswerResult> _graded = <String, AnswerResult>{};

  /// B14：交卷后服务端逐题判分（question id → 明细），进入回顾时拉取。
  /// 为空 / 拉取失败保持空 map，回顾沿用「只标已选 + 解析待接口」兜底。
  final Map<String, ExamQuestionGrade> _examGrading =
      <String, ExamQuestionGrade>{};
  final Set<String> _answeredIds = <String>{};

  /// F25：练习收藏态（按题目 id），进页拉一次，切换时本地即时更新。
  final Set<String> _favoriteIds = <String>{};
  List<AnswerRecord> _records = <AnswerRecord>[];

  /// F26 chunk 8：判分后反查到的知识点（按题目 id）。只有正式内容的 KP
  /// 才会在列表里（仓储保证）；空 / 缺失都不显示 chip。
  final Map<String, List<KnowledgePoint>> _questionPoints =
      <String, List<KnowledgePoint>>{};
  final Set<String> _kpRequested = <String>{};

  int _currentIndex = 0;
  int _target = 20;
  int _answeredCount = 0;
  int _correctCount = 0;

  /// 练习历史里第一道题的累计序号。练习一次只抽一道题，但抽到的题按顺序
  /// 留在 [_questions] 里供「上一题」回看，题号不能跟着已答总数走。
  int _practiceBaseOrdinal = 1;

  String _sessionId = '';
  String? _examId;
  int? _score;

  /// F25：交卷成功即置 true。此后退出答题页直接走，不再弹确认、不写
  /// breakpoint——会话已结算，评分页的「退出」就是离开整个答题流程。
  bool _examFinished = false;
  bool _reviewMode = false;
  bool _loading = true;
  bool _submitting = false;
  bool _drawing = false;
  bool _targetReached = false;
  bool _exhausted = false;
  String? _error;

  late DateTime _startedAt;
  late DateTime _questionStartedAt;
  Timer? _timer;
  Duration _elapsed = Duration.zero;

  /// F25：用时 = 本次进入页面前的累计值 + 本次在前台的时长。离开页面（返回 /
  /// 退到后台）就把累计值冻结并写回进行态，再进入同一会话从冻结值续计，
  /// 页面外的时间一律不计。
  Duration _elapsedBeforeVisit = Duration.zero;
  DateTime _visitStartedAt = DateTime.now();
  DateTime? _pausedAt;
  bool _timerRunning = false;

  /// F33：本页所在 Navigator 的路由观察者（didChangeDependencies 里解析；
  /// dispose 必须从同一个实例退订）。
  RouteObserver<PageRoute<dynamic>>? _routeObserver;

  /// F33：是否已订阅路由观察者（didChangeDependencies 可能多次调用，
  /// 只订阅一次；dispose 里退订）。
  bool _routeSubscribed = false;

  /// F34：本页当前是否被其它路由盖住。被盖住期间退后台再回前台时
  /// 不能续计——等 didPopNext 重新露出才恢复，否则被盖住的时间会计入用时。
  bool _covered = false;

  /// 本地进行态当前是否有一条活会话：完成 / 交卷会 clear，此时不能再落盘，
  /// 否则 dispose 里的暂停会把已结算的会话复活。
  bool _sessionPersisted = false;

  String? _completionRecordId;
  int _completionCreatedAt = 0;

  @override
  void initState() {
    super.initState();
    _isExam = widget.args['mode'] == 'exam';
    _isRotation = widget.args['mode'] == 'rotation';
    if (_isExam) {
      _exam = widget.examService ?? ServiceLocator.examService;
    } else if (_isRotation) {
      _rotation = widget.rotationService ?? ServiceLocator.rotationService;
      _manifestService =
          widget.manifestService ?? ServiceLocator.bankManifestService;
    } else {
      _practice = widget.practiceService ?? ServiceLocator.practiceService;
      _favorite = widget.favoriteService ?? ServiceLocator.favoriteService;
    }
    _recordService = widget.recordService ?? ServiceLocator.answerRecordService;
    _sessionService =
        widget.sessionService ?? ServiceLocator.answerSessionService;

    _setId = widget.args['setId'] as String? ?? '';
    _setTitle =
        widget.args['setTitle'] as String? ??
        (widget.args['setId'] as String? ?? '');
    _total = widget.args['drawCount'] is int
        ? widget.args['drawCount'] as int
        : 20;
    _target = _isExam
        ? _total
        : (widget.args['target'] is int ? widget.args['target'] as int : 20);
    if (_target > _total) _target = _total;
    if (_target <= 0) _target = 1;

    _startedAt = DateTime.now();
    _questionStartedAt = _startedAt;
    _refreshRecords();
    _init();
    WidgetsBinding.instance.addObserver(this);
    _startTimer();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // F33：订阅本页所在 Navigator 自己的路由观察者（每个 tab 内层栈各持
    // 一个实例，不用全局单例），被其它路由盖住 / 重新露出时暂停 / 续计。
    // 未注册观察者的宿主（测试里的普通 MaterialApp）静默跳过订阅——
    // didPushNext / didPopNext 不会触发，即 F33 之前的行为。
    if (!_routeSubscribed) {
      final route = ModalRoute.of(context);
      if (route is PageRoute<dynamic>) {
        final observer = Navigator.of(context).widget.observers
            .whereType<RouteObserver<PageRoute<dynamic>>>()
            .firstOrNull;
        if (observer != null) {
          observer.subscribe(this, route);
          _routeObserver = observer;
          _routeSubscribed = true;
        }
      }
    }
  }

  @override
  void dispose() {
    if (_routeSubscribed) {
      _routeObserver?.unsubscribe(this);
      _routeObserver = null;
      _routeSubscribed = false;
    }
    WidgetsBinding.instance.removeObserver(this);
    // 页面被销毁（返回 / 被替换）即视为离开：冻结用时并落盘，下次续计。
    _pauseTimer();
    super.dispose();
  }

  /// 退到后台 / 被系统挂起时冻结用时，回到前台从冻结值续计（F25）。
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      // F34：仍被其它路由盖住时不续计，等 didPopNext 露出后再恢复。
      if (!_covered) _startTimer();
    } else {
      _pauseTimer();
    }
  }

  /// F33：其它路由盖住本页（页面仍活在栈里，不会 dispose）——走与退后台
  /// 完全相同的暂停路径：冻结累计用时并落盘，绝不从 0 重来。
  /// `_pauseTimer` 自带 `_timerRunning` 守卫，未开始 / 已暂停时是空操作。
  @override
  void didPushNext() {
    _covered = true;
    _pauseTimer();
  }

  /// F33：盖住本页的路由弹出、重新露出——走与回前台完全相同的续计路径：
  /// 从冻结值继续累计，并把单题起点后移被盖住的时长（durationSec 不含
  /// 页面外的时间）。`_startTimer` 自带守卫，已在走时是空操作。
  @override
  void didPopNext() {
    _covered = false;
    _startTimer();
  }

  /// 当前累计用时：只在计时器运行时叠加本次在前台的时长。
  Duration get _currentElapsed => _timerRunning
      ? _elapsedBeforeVisit + DateTime.now().difference(_visitStartedAt)
      : _elapsedBeforeVisit;

  void _startTimer() {
    if (_timerRunning) return;
    final pausedAt = _pausedAt;
    if (pausedAt != null) {
      // 单题用时（practice submit 的 durationSec）同样扣掉页面外的时间：
      // 把起点整体后移这段暂停时长。
      _questionStartedAt = _questionStartedAt.add(
        DateTime.now().difference(pausedAt),
      );
      _pausedAt = null;
    }
    _timerRunning = true;
    _visitStartedAt = DateTime.now();
    _elapsed = _elapsedBeforeVisit;
    _timer?.cancel();
    _timer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!mounted) return;
      setState(() => _elapsed = _currentElapsed);
    });
  }

  void _pauseTimer() {
    if (!_timerRunning) return;
    _elapsedBeforeVisit = _currentElapsed;
    _elapsed = _elapsedBeforeVisit;
    _pausedAt = DateTime.now();
    _timerRunning = false;
    _timer?.cancel();
    _timer = null;
    // 没有活会话、或本次还没拿到题（抽题 / 开考失败）就不落盘：否则会把
    // 上次的好快照覆盖成空卷面。
    if (!_sessionPersisted || _questions.isEmpty) return;
    if (_isExam) {
      _saveExamSession();
    } else {
      _savePracticeSession();
    }
  }

  Question? get _current =>
      _questions.isEmpty ? null : _questions[_currentIndex];

  bool get _isLastQuestion => _currentIndex >= _questions.length - 1;

  /// 当前这道题的累计序号：按它在抽题历史里的位置算，回看旧题时题号跟着
  /// 退回，而不是停在已答总数上。
  int get _practiceOrdinal {
    if (_questions.isEmpty) return _answeredCount + 1;
    return _practiceBaseOrdinal + _currentIndex;
  }

  /// 达标后继续答题时序号会超过目标，分母跟着长大，题号才不会被卡在 20/20。
  int get _denominator => _isExam ? _total : max(_target, _practiceOrdinal);

  int get _displayIndex {
    if (_isExam) return _currentIndex + 1;
    return _practiceOrdinal;
  }

  String get _elapsedText {
    final m = _elapsed.inMinutes.remainder(60).toString().padLeft(2, '0');
    final s = _elapsed.inSeconds.remainder(60).toString().padLeft(2, '0');
    return '$m:$s';
  }

  Future<void> _init() async {
    try {
      if (_isExam) {
        await _initExam();
      } else if (_isRotation) {
        await _initRotation();
      } else {
        await _initPractice();
      }
      if (!mounted) return;
      setState(() => _loading = false);
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = _isExam ? '加载失败，请重试' : '抽题失败，请重试';
      });
      showAppSnackBar(context, _isExam ? '加载失败，请重试' : '抽题失败，请重试');
    }
  }

  Future<void> _initPractice() async {
    await _refreshFavoriteIds();
    final saved = _sessionService.load(setId: _setId, mode: 'practice');
    if (saved != null && saved.answeredCount < saved.targetCount) {
      _target = saved.targetCount;
      _answeredCount = saved.answeredCount;
      _correctCount = saved.correctCount;
      _answeredIds
        ..clear()
        ..addAll(saved.answeredIds);
      _sessionId = saved.sessionId ?? '';
      _startedAt = DateTime.fromMillisecondsSinceEpoch(saved.startedAt);
      _questionStartedAt = DateTime.now();
      // F25：从上次离开时冻结的用时续计，不是从 0、也不是从 startedAt 的墙钟。
      _elapsedBeforeVisit = Duration(milliseconds: saved.elapsedMs);
      _elapsed = _elapsedBeforeVisit;
    } else if (saved != null) {
      // 达标后退出：保留 completion，不恢复进行态（下次从新会话开始）。
      _sessionService.clear(setId: _setId, mode: 'practice');
      _sessionPersisted = false;
    }

    await _openServerSession();
    _practiceBaseOrdinal = _answeredCount + 1;
    final next = await _drawPractice();
    if (next == null) {
      _exhausted = true;
      await _finishServerSession();
      _finalizeCompletion();
      return;
    }
    _sessionId = next.sessionId;
    _questions = <Question>[next.question];
    _currentIndex = 0;
    _savePracticeSession();
  }

  /// S11 `POST /practice/sessions`：开始或续接服务端会话。
  ///
  /// - 服务端已有 in_progress 会话（answered_count < 20）时返回它，并按
  ///   `GET /practice/sessions/{id}` 的 answeredQuestionIds 补全已答集合；
  /// - 已满 20 题时服务端先把旧会话结算为 completed，再新建；
  /// - 接口未就绪 / 401（线上尚未部署 S11）返回 null，保持本地会话，不报错。
  Future<void> _openServerSession() async {
    final info = await _practice.startPracticeSession(
      module: _setId.isEmpty ? null : _setId,
    );
    if (info == null || info.id.isEmpty) return;
    final previous = _sessionId;
    _sessionId = info.id;
    if (info.isCompleted) return;
    final detail = await _practice.fetchPracticeSession(info.id);
    final answered = detail?.answeredQuestionIds ?? info.answeredQuestionIds;
    if (info.id != previous) {
      // 服务端开了新会话（旧会话满 20 题已结算）：本地旧计数不再适用。
      _answeredIds.clear();
      _answeredCount = 0;
      _correctCount = 0;
    }
    if (answered.isNotEmpty) {
      _answeredIds
        ..clear()
        ..addAll(answered);
    }
    _answeredCount = max(_answeredCount, info.answeredCount);
    _correctCount = max(_correctCount, info.correctCount);
  }

  /// S11 `POST /practice/sessions/{id}/end`：满 20 题服务端结算为 completed，
  /// 未满保留 in_progress 断点。失败静默（本地断点记录照旧）。
  Future<void> _finishServerSession() async {
    if (_sessionId.isEmpty) return;
    await _practice.endPracticeSession(_sessionId);
  }

  Future<PracticeNext?> _drawPractice() async {
    var next = await _practice.drawNextQuestion(
      setId: _setId,
      excludedIds: _answeredIds,
      sessionId: _sessionId.isEmpty ? null : _sessionId,
    );
    if (next != null && _answeredIds.contains(next.question.id)) {
      // 客户端兜底：服务端返回重复题丢弃并重抽一次，仍重复则视为抽尽。
      final retry = await _practice.drawNextQuestion(
        setId: _setId,
        excludedIds: <String>{..._answeredIds, next.question.id},
        sessionId: _sessionId.isEmpty ? null : _sessionId,
      );
      next = retry != null && !_answeredIds.contains(retry.question.id)
          ? retry
          : null;
    }
    return next;
  }

  /// F28：轮回初始化——bankId 取自题库清单（绝不硬编码），整批抽题。
  /// 空抽 / 清单不可用：诚实待接口态（服务端文案 + 解锁时间），绝不编题、
  /// 绝不编解锁时间、不留白屏。短抽：用抽到的题继续，服务端文案提示。
  Future<void> _initRotation() async {
    BankManifest? manifest;
    try {
      manifest = await _manifestService.fetchManifest();
    } catch (_) {}
    if (!mounted) return;
    final bankId = manifest?.bankId ?? '';
    if (bankId.isEmpty) {
      setState(() {
        _rotationWaiting = true;
        _rotationMessage = '轮回待接口';
      });
      return;
    }
    final draw = await _rotation.draw(bankId: bankId, count: _total);
    if (!mounted) return;
    if (draw.isEmpty) {
      setState(() {
        _rotationWaiting = true;
        _rotationMessage = draw.message ?? '当前无可抽题目';
        _rotationUnlockAt = draw.nextUnlockAt;
      });
      return;
    }
    setState(() {
      _sessionId = draw.sessionId!;
      _questions = draw.questions;
      _target = draw.questions.length;
      _currentIndex = 0;
      _questionStartedAt = DateTime.now();
    });
    if (draw.drawnShort && (draw.message ?? '').isNotEmpty) {
      showAppSnackBar(context, draw.message!);
    }
  }

  /// F28：轮回单题判分——没有本地答案键，对错 / 正确答案 / 解析全部
  /// 来自 `POST /sessions/{id}/answers`。失败只提示重试，不涂红绿、
  /// 不编判分；在途防连点。
  Future<void> _submitRotation() async {
    final q = _current;
    if (q == null ||
        _graded.containsKey(q.id) ||
        _rotationGrading.contains(q.id)) {
      return;
    }
    final chosen = List<String>.from(_chosen);
    if (chosen.isEmpty) return;
    setState(() => _rotationGrading.add(q.id));
    try {
      final result = await _rotation.answer(
        sessionId: _sessionId,
        questionId: q.id,
        chosen: bankAnswerIndices(chosen),
        opId: newRotationOpId(),
      );
      if (!mounted) return;
      setState(() {
        _rotationGrading.remove(q.id);
        _answers[q.id] = chosen;
        _graded[q.id] = AnswerResult(
          correct: result.isCorrect,
          explanation: result.explanation.isEmpty
              ? '解析待接口'
              : result.explanation,
          correctKeys: result.answer.isEmpty ? null : result.answer,
        );
        if (_answeredIds.add(q.id)) {
          _answeredCount++;
          if (result.isCorrect) _correctCount++;
        }
        if (_answeredCount >= _target) _targetReached = true;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _rotationGrading.remove(q.id));
      showAppSnackBar(context, '提交失败，请重试');
    }
  }

  /// F28：轮回结算——`POST /sessions/{id}/submit`，服务端得分 + 逐题
  /// 明细复用全屏评分页（ExamScorePage）。0 题已答被服务端删除
  /// （deleted: true）时没有成绩可展示，直接退出。
  Future<void> _settleRotation() async {
    if (_submitting || _sessionId.isEmpty) return;
    setState(() => _submitting = true);
    final RotationResult result;
    try {
      result = await _rotation.submit(
        sessionId: _sessionId,
        opId: newRotationOpId(),
      );
    } catch (_) {
      if (!mounted) return;
      setState(() => _submitting = false);
      showAppSnackBar(context, '结算失败，请重试');
      return;
    }
    if (!mounted) return;
    setState(() {
      _submitting = false;
      _rotationFinished = true;
    });
    if (result.deleted) {
      Navigator.of(context).pop();
      return;
    }
    final grading = <String, ExamQuestionGrade>{
      for (final item in result.detail)
        item.questionId: ExamQuestionGrade(
          questionId: item.questionId,
          chosen: item.chosen,
          answer: item.answer,
          explanation: item.explanation,
          correct: item.isCorrect,
        ),
    };
    final exited = await Navigator.of(context).push<bool>(
      MaterialPageRoute<bool>(
        // 命名路由：外壳按名字隐藏底栏（匿名 push 会让底栏重新出现）。
        settings: const RouteSettings(name: AppRoutes.bankExamResult),
        builder: (_) => ExamScorePage(
          title: '7天轮回结果',
          total: _questions.length,
          answered: _answeredCount,
          elapsed: _currentElapsed,
          score: result.score,
          detail: '答对 ${result.correctCount} 题 · 答错 ${result.wrongCount} 题',
          questions: _questions,
          answers: _answers,
          grading: grading,
          wrongService: widget.wrongService,
          onReview: (index) {
            if (!mounted) return;
            setState(() {
              _reviewMode = true;
              _currentIndex = index.clamp(0, _questions.length - 1);
            });
          },
        ),
      ),
    );
    if (!mounted) return;
    if (exited == true) Navigator.of(context).pop();
  }

  /// 解锁时间展示：服务端 ISO 时间转本地时区，分钟精度。
  static String _unlockText(DateTime time) {
    final local = time.toLocal();
    String two(int n) => n.toString().padLeft(2, '0');
    return '${local.year}-${two(local.month)}-${two(local.day)} '
        '${two(local.hour)}:${two(local.minute)}';
  }

  /// F28：空抽 / 待接口态——服务端文案 + 真实解锁时间（没有就不显示），
  /// 绝不编题、绝不编时间、不留白屏。
  Widget _buildRotationWaiting() {
    final theme = Theme.of(context);
    final unlock = _rotationUnlockAt;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.md),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              '7天轮回',
              style: theme.textTheme.titleMedium?.copyWith(
                fontSize: AppFontSizes.detailSectionTitle,
                fontWeight: FontWeight.w700,
                color: AppColors.title(context),
              ),
            ),
            const SizedBox(height: AppSpacing.sm),
            Text(
              _rotationMessage,
              textAlign: TextAlign.center,
              style: theme.textTheme.bodyMedium?.copyWith(
                fontSize: AppFontSizes.detailBody,
                color: AppColors.title(context),
              ),
            ),
            if (unlock != null) ...[
              const SizedBox(height: AppSpacing.xs),
              Text(
                '下次解锁：${_unlockText(unlock)}',
                style: theme.textTheme.bodyMedium?.copyWith(
                  fontSize: AppFontSizes.detailStat,
                  color: AppColors.cardCaption(context),
                ),
              ),
            ],
            const SizedBox(height: AppSpacing.md),
            OutlinedButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('返回'),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _initExam() async {
    final saved = _sessionService.load(setId: _setId, mode: 'exam');
    if (saved != null && saved.examId != null) {
      _examId = saved.examId;
      // F25：续考从冻结的用时续计，本地卷面 / 服务端恢复两条路都用它。
      _elapsedBeforeVisit = Duration(milliseconds: saved.elapsedMs);
      _elapsed = _elapsedBeforeVisit;
      _sessionPersisted = true;
      final hasLocalSnapshot =
          saved.snapshot != null && saved.snapshot!.isNotEmpty;
      if (!hasLocalSnapshot) {
        // 本地卷面缺失时向服务端恢复（S11 `GET /exam/{session_id}`，
        // 已保存选项在 `answers` 列表里）。接口未就绪返回 null。
        final recovery = await _exam.loadExamForResume(saved.examId!);
        if (recovery != null) {
          _questions = recovery.questions;
          _answers.addAll(recovery.answers);
          _answeredCount = recovery.answers.values
              .where((a) => a.isNotEmpty)
              .length;
          _startedAt = recovery.startedAt > 0
              ? DateTime.fromMillisecondsSinceEpoch(recovery.startedAt)
              : DateTime.now();
          _questionStartedAt = DateTime.now();
          return;
        }
      } else {
        _questions = saved.snapshot!;
        _answers.addAll(saved.answers);
        _answeredCount = saved.answeredCount;
        _correctCount = saved.correctCount;
        _startedAt = DateTime.fromMillisecondsSinceEpoch(saved.startedAt);
        _questionStartedAt = DateTime.now();
        final index = _questions.indexWhere(
          (q) => q.id == saved.lastQuestionId,
        );
        _currentIndex = index < 0 ? 0 : index;
        return;
      }
    }

    // F25 Chunk 4：走 startExamPaper 拿真实卷面——题目 id 必须是服务端题目
    // id：暂存 / 交卷 / 判分明细 / 加入错题本都按它定位，自编 EXAM-N 序号
    // 会被服务端判「题目不属于该考试」，错题本 POST 也会 404。Mock 兜底
    // 仍按快照序号编 id（examStartFromSession），本地样例卷不受影响。
    final paper = await _exam.startExamPaper(drawCount: _total, setId: _setId);
    _examId = paper.id;
    // 新开考：旧断点的累计用时不属于这张新卷，从 0 起。
    _elapsedBeforeVisit = Duration.zero;
    _elapsed = Duration.zero;
    _questions = paper.questions;
    if (paper.startedAt > 0) {
      _startedAt = DateTime.fromMillisecondsSinceEpoch(paper.startedAt);
      _questionStartedAt = DateTime.now();
    }
    if (_questions.isEmpty) {
      throw StateError('empty exam');
    }
  }

  /// F25：进页拉收藏题号（GET /favorites）。失败静默——收藏按钮按未收藏
  /// 显示，点收藏仍会尝试提交，不因列表拉取失败锁死按钮。
  Future<void> _refreshFavoriteIds() async {
    try {
      final ids = await _favorite.getFavoriteIds();
      if (!mounted) return;
      setState(() {
        _favoriteIds
          ..clear()
          ..addAll(ids);
      });
    } catch (_) {}
  }

  /// F25：练习收藏切换（POST /favorites / DELETE /favorites/{qid}）。
  /// 本地即时更新图标，失败回滚并提示；考试页没有这个按钮。
  Future<void> _toggleFavorite() async {
    final q = _current;
    if (q == null) return;
    final on = !_favoriteIds.contains(q.id);
    setState(() {
      if (on) {
        _favoriteIds.add(q.id);
      } else {
        _favoriteIds.remove(q.id);
      }
    });
    try {
      await _favorite.toggleFavorite(q.id, on);
      if (!mounted) return;
      showAppSnackBar(context, on ? '已收藏' : '已取消收藏');
    } catch (_) {
      if (!mounted) return;
      setState(() {
        if (on) {
          _favoriteIds.remove(q.id);
        } else {
          _favoriteIds.add(q.id);
        }
      });
      showAppSnackBar(context, on ? '收藏失败，请重试' : '取消收藏失败，请重试');
    }
  }

  void _refreshRecords() {
    if (_setId.isEmpty) {
      _records = <AnswerRecord>[];
      return;
    }
    try {
      _records = _recordService.recordsFor(
        setId: _setId,
        mode: _isExam ? 'exam' : 'practice',
      );
    } catch (_) {
      _records = <AnswerRecord>[];
    }
  }

  /// F26 chunk 8：判分后反查本题知识点（每题只查一次）。仓储失败 / 未登录
  /// 回落 Mock（返回空），chip 不显示；ServiceLocator 懒解析——考试链测试
  /// 只注入服务、不注册 Locator，解析失败静默跳过。
  void _ensureQuestionPoints(Question q) {
    if (_kpRequested.contains(q.id)) return;
    _kpRequested.add(q.id);
    KnowledgeRepository? repo;
    try {
      repo = widget.knowledgeRepository ?? ServiceLocator.knowledgeRepository;
    } catch (_) {
      repo = null;
    }
    if (repo == null) return;
    // 闭包捕获会使外部 null 提升失效，拷贝为非空 final 再进闭包。
    final knowledgeRepo = repo;
    unawaited(() async {
      try {
        final points = await knowledgeRepo.getPointsByQuestion(q.id);
        if (!mounted || points.isEmpty) return;
        setState(() => _questionPoints[q.id] = points);
      } catch (_) {}
    }());
  }

  /// F26 chunk 8：判分后的知识点 chip——仅当题目关联到有正式内容的 KP
  /// 时出现；点按进知识详情页（与知识库页同一命名路由，returnTo=quiz）。
  Widget _buildKnowledgeChip(KnowledgePoint point) {
    return Padding(
      padding: const EdgeInsets.only(top: AppSpacing.sm),
      child: Align(
        alignment: Alignment.centerLeft,
        child: ActionChip(
          avatar: const Icon(Icons.menu_book, size: 18),
          label: Text('知识点：${point.title}'),
          onPressed: () => _openKnowledgePoint(point),
        ),
      ),
    );
  }

  void _openKnowledgePoint(KnowledgePoint point) {
    final parts = point.code.split('.');
    final chapter = parts.isNotEmpty ? (int.tryParse(parts[0]) ?? 1) : 1;
    final section = parts.length > 1 ? (int.tryParse(parts[1]) ?? 1) : 1;
    final chapterId = '${point.module}-${chapter.toString().padLeft(2, '0')}';
    Navigator.of(context).pushNamed(
      AppRoutes.knowledgePoint,
      arguments: <String, Object?>{
        'kpId': point.id,
        'sectionId': '$chapterId-${section.toString().padLeft(2, '0')}',
        'chapterTitle': point.module,
        'sectionTitle': point.topic,
        'returnTo': 'quiz',
      },
    );
  }

  List<String> get _chosen {
    final q = _current;
    if (q == null) return const <String>[];
    return _answers[q.id] ?? const <String>[];
  }

  void _selectOption(String key) {
    final q = _current;
    if (q == null) return;
    if (_graded.containsKey(q.id) ||
        ((_isExam || _isRotation) && _reviewMode)) {
      return;
    }
    final current = List<String>.from(_answers[q.id] ?? const <String>[]);
    setState(() {
      if (q.type == 'multiple') {
        if (current.contains(key)) {
          current.remove(key);
        } else {
          current.add(key);
        }
        _answers[q.id] = current;
      } else {
        _answers[q.id] = <String>[key];
      }
      if (_isExam) {
        _answeredCount = _answers.values.where((a) => a.isNotEmpty).length;
      }
    });
    if (_isExam) {
      _saveExamSession();
      unawaited(
        _exam
            .saveAnswer(
              examId: _examId ?? '',
              questionId: q.id,
              chosen: _answers[q.id] ?? const <String>[],
              opId: '${_examId ?? ''}-${q.id}',
            )
            .catchError((_) {}),
      );
      return;
    }
    // F28：轮回没有本地答案键，判分只来自服务端；单选 / 判断点完即提交，
    // 多选仍由「确认作答」触发。
    if (_isRotation) {
      if (q.type != 'multiple') unawaited(_submitRotation());
      return;
    }
    // F22：单选 / 判断点完选项立刻判分（红绿 + 解析），不再等「确认作答」。
    // 多选要选完才知道对错，仍由「确认作答」触发。
    if (q.type != 'multiple') unawaited(_submitPractice());
  }

  /// 练习判分（F22）：先用题目自带的答案键**即时**判分并显示解析，再把作答
  /// 提交到服务端；服务端返回的判分与解析随后覆盖本地结果。
  ///
  /// 提交失败只提示重试，已经显示的红绿与解析原样保留——点选项即出结果，
  /// 不能让用户等网络。多选题仍走「确认作答」，选完才判。
  Future<void> _submitPractice() async {
    final q = _current;
    if (q == null || _graded.containsKey(q.id)) return;
    final chosen = List<String>.from(_chosen);
    if (chosen.isEmpty) return;
    final durationMs = DateTime.now()
        .difference(_questionStartedAt)
        .inMilliseconds;
    final local = _practiceGrade(q, chosen);
    setState(() {
      _graded[q.id] = local;
      _answers[q.id] = chosen;
      if (_answeredIds.add(q.id)) {
        _answeredCount++;
        if (local.correct == true) _correctCount++;
      }
      if (_completionRecordId != null || _answeredCount >= _target) {
        _writeCompletion();
      }
      if (_answeredCount == _target) _targetReached = true;
      _refreshRecords();
    });
    _savePracticeSession();
    try {
      final result = await _practice.submitAnswer(
        sessionId: _sessionId,
        questionId: q.id,
        chosen: chosen,
        durationMs: durationMs,
        setId: _setId,
        opId: '$_sessionId-${q.id}',
        mode: 'practice',
      );
      if (!mounted) return;
      setState(() {
        final merged = _practiceGrade(q, chosen, result);
        // 服务端判分与本地答案键不一致时以服务端为准，答对数跟着校正。
        if (merged.correct != local.correct) {
          _correctCount += merged.correct == true ? 1 : -1;
          if (_completionRecordId != null) _writeCompletion();
        }
        _graded[q.id] = merged;
        _refreshRecords();
      });
      _savePracticeSession();
    } catch (_) {
      if (!mounted) return;
      showAppSnackBar(context, '提交失败，请重试');
    }
  }

  /// 练习判分结果的取值口径：服务端结果优先，缺什么用题目自带数据补什么。
  ///
  /// - 答案键：服务端 `correctKeys` → 题目 `answer`；两者都空就不判对错
  ///   （`correct: null`），选项只标已选，绝不涂红（与考试 P1-4 守卫一致）。
  /// - 解析：服务端 `explanation` → 题目 `explanation`；都空显示「解析待接口」，
  ///   不许编造解析文本。
  AnswerResult _practiceGrade(
    Question q,
    List<String> chosen, [
    AnswerResult? remote,
  ]) {
    final remoteKeys = remote?.correctKeys ?? const <String>[];
    final keys = remoteKeys.isNotEmpty ? remoteKeys : q.answer;
    final remoteExplanation = remote?.explanation ?? '';
    final explanation = remoteExplanation.isNotEmpty
        ? remoteExplanation
        : (q.explanation.isEmpty ? '解析待接口' : q.explanation);
    return AnswerResult(
      correct:
          remote?.correct ?? (keys.isEmpty ? null : _sameKeys(chosen, keys)),
      explanation: explanation,
      correctKeys: keys.isEmpty ? null : keys,
      opId: remote?.opId,
    );
  }

  /// 练习「下一题」：先沿抽题历史前进，走到最新一题才抽新题。
  ///
  /// 抽题失败（线上 `/practice/next` 未鉴权、本地题库读写出错）只提示，
  /// 不改状态：当前题与已判分结果原样留在屏上，绝不把页面留白。
  Future<void> _nextPractice() async {
    if (!_isLastQuestion) {
      setState(() {
        _currentIndex++;
        _targetReached = false;
      });
      _savePracticeSession();
      return;
    }
    // 抽题期间连点「下一题」只抽一次：否则会跳过一道题，历史里留下一道
    // 没判分的题，题号与已答数就对不上了。
    if (_drawing) return;
    _drawing = true;
    PracticeNext? next;
    try {
      next = await _drawPractice();
    } catch (_) {
      if (!mounted) return;
      showAppSnackBar(context, '抽题失败，请重试');
      return;
    } finally {
      _drawing = false;
    }
    if (!mounted) return;
    if (next == null) {
      setState(() {
        _exhausted = true;
        _targetReached = true;
      });
      _finalizeCompletion();
      showAppSnackBar(context, '本题库已全部完成');
      return;
    }
    final question = next.question;
    setState(() {
      _questions.add(question);
      _currentIndex = _questions.length - 1;
      _exhausted = false;
      _targetReached = false;
      _questionStartedAt = DateTime.now();
    });
    _savePracticeSession();
  }

  /// 练习「上一题」：回看已抽到的题，判分与解析由 [_graded] / [_answers]
  /// 按题目 id 还原，不重新抽题、不重复计数。
  void _previousPractice() {
    if (_currentIndex == 0) return;
    setState(() => _currentIndex--);
    _savePracticeSession();
  }

  void _continueAfterTarget() {
    setState(() {
      _targetReached = false;
      // 「继续答题」语义是抽新题：先回到历史最新一题，别停在回看的旧题上。
      _currentIndex = _questions.isEmpty ? 0 : _questions.length - 1;
    });
    _nextPractice();
  }

  void _writeCompletion() {
    if (_setId.isEmpty) return;
    final now = DateTime.now().millisecondsSinceEpoch;
    _completionRecordId ??= 'rec-$now-${(Random().nextInt(9000) + 1000)}';
    _completionCreatedAt = _completionCreatedAt == 0
        ? now
        : _completionCreatedAt;
    _recordService.upsert(
      AnswerRecord(
        id: _completionRecordId!,
        setId: _setId,
        setTitle: _setTitle,
        mode: 'practice',
        kind: 'completion',
        targetCount: _target,
        answeredCount: _answeredCount,
        totalCount: _total,
        correctCount: _correctCount,
        lastQuestionId: _current?.id,
        durationMs: _currentElapsed.inMilliseconds,
        createdAt: _completionCreatedAt,
        updatedAt: now,
      ),
    );
  }

  void _finalizeCompletion() {
    if (_answeredCount > 0) _writeCompletion();
    _sessionService.clear(setId: _setId, mode: 'practice');
    _sessionPersisted = false;
    // S11：退出时结束会话，满 20 题由服务端结算为 completed。
    unawaited(_finishServerSession());
    _refreshRecords();
  }

  void _writePracticeBreakpoint() {
    if (_setId.isEmpty) return;
    final now = DateTime.now().millisecondsSinceEpoch;
    _recordService.upsert(
      AnswerRecord(
        id: 'rec-$now-${(Random().nextInt(9000) + 1000)}',
        setId: _setId,
        setTitle: _setTitle,
        mode: 'practice',
        kind: 'breakpoint',
        targetCount: _target,
        answeredCount: _answeredCount,
        totalCount: _total,
        correctCount: _correctCount,
        lastQuestionId: _current?.id,
        durationMs: _currentElapsed.inMilliseconds,
        createdAt: now,
        updatedAt: now,
      ),
    );
  }

  void _savePracticeSession() {
    if (_setId.isEmpty || _isExam) return;
    _sessionService.save(
      AnswerSessionState(
        setId: _setId,
        setTitle: _setTitle,
        mode: 'practice',
        sessionId: _sessionId,
        targetCount: _target,
        answeredCount: _answeredCount,
        correctCount: _correctCount,
        answeredIds: _answeredIds.toList(),
        answers: _answers,
        lastQuestionId: _current?.id,
        startedAt: _startedAt.millisecondsSinceEpoch,
        updatedAt: DateTime.now().millisecondsSinceEpoch,
        elapsedMs: _currentElapsed.inMilliseconds,
      ),
    );
    _sessionPersisted = true;
  }

  void _saveExamSession() {
    if (_setId.isEmpty || !_isExam) return;
    _sessionService.save(
      AnswerSessionState(
        setId: _setId,
        setTitle: _setTitle,
        mode: 'exam',
        examId: _examId,
        targetCount: _total,
        answeredCount: _answeredCount,
        correctCount: _correctCount,
        answeredIds: const <String>[],
        answers: _answers,
        snapshot: _questions,
        lastQuestionId: _current?.id,
        startedAt: _startedAt.millisecondsSinceEpoch,
        updatedAt: DateTime.now().millisecondsSinceEpoch,
        elapsedMs: _currentElapsed.inMilliseconds,
      ),
    );
    _sessionPersisted = true;
  }

  Future<void> _nextExam() async {
    if (_isLastQuestion) {
      await _submitExam();
      return;
    }
    setState(() {
      _currentIndex++;
      _questionStartedAt = DateTime.now();
    });
    _saveExamSession();
  }

  void _previousExam() {
    if (_currentIndex == 0) return;
    setState(() => _currentIndex--);
    _saveExamSession();
  }

  Future<void> _submitExam() async {
    final unanswered = _total - _answeredCount;
    final confirmed = await showSubmitDialog(context, unanswered: unanswered);
    if (!confirmed || !mounted) return;
    if (_submitting) return;
    setState(() => _submitting = true);

    int? score;
    String detail = '';
    try {
      final result = await _exam.submitExam(
        examId: _examId ?? '',
        answers: Map<String, List<String>>.from(_answers),
        durationMs: _currentElapsed.inMilliseconds,
      );
      score = result?.score;
      detail = result?.detail ?? '';
    } catch (_) {
      if (!mounted) return;
      setState(() => _submitting = false);
      showAppSnackBar(context, '交卷失败，请重试');
      return;
    }
    if (!mounted) return;

    setState(() {
      _submitting = false;
      _score = score;
      _examFinished = true;
    });
    _writeExamCompletion(score);
    _sessionService.clear(setId: _setId, mode: 'exam');
    _sessionPersisted = false;
    _refreshRecords();

    // F25 Chunk 4：全屏评分页取代半屏结果 sheet。判分明细由评分页后台
    // 拉取（不阻塞渲染），返回后错题列表自动刷新；回顾沿用同一份明细。
    final exited = await Navigator.of(context).push<bool>(
      MaterialPageRoute<bool>(
        // 命名路由：外壳按名字隐藏底栏（_shouldHideNav），匿名 push 会让
        // 底栏重新出现在「全屏」评分页上。
        settings: const RouteSettings(name: AppRoutes.bankExamResult),
        builder: (_) => ExamScorePage(
          total: _total,
          answered: _answeredCount,
          elapsed: _currentElapsed,
          score: score,
          detail: detail,
          questions: _questions,
          answers: _answers,
          grading: _examGrading,
          loadGrading: _loadExamGrading,
          wrongService: widget.wrongService,
          onReview: (index) {
            if (!mounted) return;
            setState(() {
              _reviewMode = true;
              _currentIndex = index.clamp(0, _questions.length - 1);
            });
          },
        ),
      ),
    );
    if (!mounted) return;
    // 评分页「退出」：离开答题页。已交卷，_handleBack 直接 pop，
    // 不弹确认、不写 breakpoint。
    if (exited == true) await _handleBack();
  }

  /// B14 / F25：交卷后拉取服务端判分（评分页 initState 调用），不阻塞
  /// 界面。失败或空结果保持空 map——没有判分依据就只标已选，绝不本地猜对错。
  Future<Map<String, ExamQuestionGrade>> _loadExamGrading() async {
    final examId = _examId;
    if (examId == null || examId.isEmpty) {
      return const <String, ExamQuestionGrade>{};
    }
    try {
      final grading = await _exam.loadExamGrading(examId);
      if (!mounted || grading.isEmpty) return grading;
      setState(() {
        _examGrading
          ..clear()
          ..addAll(grading);
      });
      return grading;
    } catch (_) {
      // 保持空 map，评分页 / 回顾走原有兜底。
      return const <String, ExamQuestionGrade>{};
    }
  }

  void _writeExamCompletion(int? score) {
    if (_setId.isEmpty) return;
    final now = DateTime.now().millisecondsSinceEpoch;
    _recordService.upsert(
      AnswerRecord(
        id: 'rec-$now-${(Random().nextInt(9000) + 1000)}',
        setId: _setId,
        setTitle: _setTitle,
        mode: 'exam',
        kind: 'completion',
        targetCount: _total,
        answeredCount: _answeredCount,
        totalCount: _total,
        score: score,
        durationMs: _currentElapsed.inMilliseconds,
        createdAt: now,
        updatedAt: now,
      ),
    );
  }

  void _writeExamBreakpoint() {
    if (_setId.isEmpty) return;
    final now = DateTime.now().millisecondsSinceEpoch;
    _recordService.upsert(
      AnswerRecord(
        id: 'rec-$now-${(Random().nextInt(9000) + 1000)}',
        setId: _setId,
        setTitle: _setTitle,
        mode: 'exam',
        kind: 'breakpoint',
        targetCount: _total,
        answeredCount: _answeredCount,
        totalCount: _total,
        lastQuestionId: _current?.id,
        durationMs: _currentElapsed.inMilliseconds,
        createdAt: now,
        updatedAt: now,
      ),
    );
  }

  Future<void> _handleBack() async {
    if (_loading) return;
    if (_isRotation) {
      if (_rotationWaiting || _rotationFinished || _answeredCount == 0) {
        // 0 题已答：让服务端删除空会话（静默，不阻塞退出）。
        if (!_rotationFinished &&
            _answeredCount == 0 &&
            _sessionId.isNotEmpty) {
          unawaited(() async {
            try {
              await _rotation.submit(
                sessionId: _sessionId,
                opId: newRotationOpId(),
              );
            } catch (_) {}
          }());
        }
        Navigator.of(context).pop();
        return;
      }
      // >=1 题已答：退出即结算，展示服务端得分（轮回不写本地断点）。
      await _settleRotation();
      return;
    }
    if (_isExam && _reviewMode) {
      Navigator.of(context).pop();
      return;
    }
    if (_isExam) {
      // F25：已交卷（_examFinished）或一题未答，直接退出，不写 breakpoint。
      if (_examFinished || _answeredCount == 0) {
        Navigator.of(context).pop();
        return;
      }
      final exit = await showExitConfirmDialog(context);
      if (!mounted || !exit) return;
      _writeExamBreakpoint();
      _saveExamSession();
      Navigator.of(context).pop();
      return;
    }

    if (_answeredCount == 0) {
      Navigator.of(context).pop();
      return;
    }
    if (_answeredCount >= _target || _exhausted) {
      _finalizeCompletion();
      Navigator.of(context).pop();
      return;
    }
    final exit = await showExitConfirmDialog(context);
    if (!mounted || !exit) return;
    _writePracticeBreakpoint();
    _savePracticeSession();
    // S11：未满 20 题退出，服务端保留 in_progress 断点会话。
    await _finishServerSession();
    if (!mounted) return;
    Navigator.of(context).pop();
  }

  OptionTileState _optionState(Question q, String key) {
    final chosen = _answers[q.id] ?? const <String>[];
    if (_isExam) {
      if (!_reviewMode) {
        return chosen.contains(key)
            ? OptionTileState.selected
            : OptionTileState.idle;
      }
      final grade = _examGrading[q.id];
      if (grade != null) {
        // B14：服务端判分优先。correct 未下发不涂红绿；答案键标绿，
        // 用户错选标红。
        if (grade.correct == null) {
          return chosen.contains(key)
              ? OptionTileState.selected
              : OptionTileState.idle;
        }
        if (grade.answer.contains(key)) return OptionTileState.correct;
        if (chosen.contains(key)) return OptionTileState.wrong;
        return OptionTileState.idle;
      }
      if (q.answer.isEmpty) {
        // 卷面不含答案（考试作答接口不返回答案）：没有判分依据，就只标已选，
        // 不把用户选项涂成“错”——与 _resultFor 的 correct: null 保持一致。
        return chosen.contains(key)
            ? OptionTileState.selected
            : OptionTileState.idle;
      }
      final correct = q.answer.contains(key);
      if (correct) return OptionTileState.correct;
      if (chosen.contains(key)) return OptionTileState.wrong;
      return OptionTileState.idle;
    }
    final result = _graded[q.id];
    if (result == null || result.correct == null) {
      return chosen.contains(key)
          ? OptionTileState.selected
          : OptionTileState.idle;
    }
    final correctKeys = result.correctKeys ?? q.answer;
    if (correctKeys.contains(key)) return OptionTileState.correct;
    if (chosen.contains(key)) return OptionTileState.wrong;
    return OptionTileState.idle;
  }

  AnswerResult? _resultFor(Question q) {
    if (_isExam) {
      if (!_reviewMode) return null;
      final grade = _examGrading[q.id];
      if (grade != null) {
        // B14：对错以服务端为准；解析 / 答案键缺什么用题目自带数据补什么。
        final keys = grade.answer.isNotEmpty ? grade.answer : q.answer;
        final explanation = grade.explanation.isNotEmpty
            ? grade.explanation
            : (q.explanation.isEmpty ? '解析待接口' : q.explanation);
        return AnswerResult(
          correct: grade.correct,
          explanation: explanation,
          correctKeys: keys,
        );
      }
      return AnswerResult(
        correct: q.answer.isEmpty
            ? null
            : _sameKeys(_answers[q.id] ?? const <String>[], q.answer),
        explanation: q.explanation.isEmpty ? '解析待接口' : q.explanation,
        correctKeys: q.answer,
      );
    }
    return _graded[q.id];
  }

  bool _sameKeys(List<String> a, List<String> b) {
    if (a.length != b.length) return false;
    final sortedA = List<String>.of(a)..sort();
    final sortedB = List<String>.of(b)..sort();
    for (var i = 0; i < sortedA.length; i++) {
      if (sortedA[i] != sortedB[i]) return false;
    }
    return true;
  }

  String? _correctAnswerText(Question q, AnswerResult result) {
    final keys = result.correctKeys ?? q.answer;
    if (keys.isEmpty) return null;
    return '正确答案：${keys.join('、')}';
  }

  bool get _showAnalysis {
    final q = _current;
    if (q == null) return false;
    return _isExam ? _reviewMode : _graded.containsKey(q.id);
  }

  String get _primaryLabel {
    if (_isExam) return _isLastQuestion ? '交卷' : '下一题';
    final q = _current;
    if (q != null && _graded.containsKey(q.id)) {
      return _isRotation && _isLastQuestion ? '完成本轮' : '下一题';
    }
    return '确认作答';
  }

  bool get _primaryEnabled {
    if (_isExam) return !_submitting;
    final q = _current;
    if (q == null) return false;
    // 已判分：「下一题」随时可点，不等后台提交返回。
    if (_graded.containsKey(q.id)) return true;
    return _chosen.isNotEmpty;
  }

  Future<void> _onPrimary() async {
    if (_isExam) {
      await _nextExam();
      return;
    }
    final q = _current;
    if (q == null) return;
    if (_isRotation) {
      if (_graded.containsKey(q.id)) {
        if (_isLastQuestion) {
          await _settleRotation();
        } else {
          setState(() {
            _currentIndex++;
            _questionStartedAt = DateTime.now();
          });
        }
      } else {
        await _submitRotation();
      }
      return;
    }
    if (_graded.containsKey(q.id)) {
      await _nextPractice();
    } else {
      await _submitPractice();
    }
  }

  String get _currentSummary {
    if (_isExam) {
      return _score == null
          ? '本次 · 已答 $_answeredCount/$_total 题'
          : '本次 · 得分 $_score';
    }
    // F32：达标后「继续答题」会让已答数超过目标（数据如实：answeredCount
    // 可以 > targetCount），分母跟着已答数长大，不再显示 21/20 这种假比例。
    final denominator = max(_target, _answeredCount);
    return '本次 · 已答 $_answeredCount/$denominator 题 · 答对 $_correctCount 题';
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) async {
        if (didPop) return;
        await _handleBack();
      },
      child: Scaffold(
        backgroundColor: AppColors.pageBackground(context),
        body: SafeArea(
          child: _loading
              ? const Center(child: CircularProgressIndicator())
              : _error != null
              ? _buildError()
              : _rotationWaiting
              ? _buildRotationWaiting()
              : _buildContent(),
        ),
      ),
    );
  }

  Widget _buildError() {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(_error!, style: Theme.of(context).textTheme.bodyMedium),
          const SizedBox(height: AppSpacing.md),
          OutlinedButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('返回'),
          ),
        ],
      ),
    );
  }

  Widget _buildContent() {
    final q = _current;
    if (q == null) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text('本题库已全部完成', style: Theme.of(context).textTheme.bodyMedium),
            const SizedBox(height: AppSpacing.md),
            FilledButton(
              onPressed: () {
                _finalizeCompletion();
                Navigator.of(context).pop();
              },
              child: const Text('结束本轮'),
            ),
          ],
        ),
      );
    }

    final result = _resultFor(q);
    final correctAnswer = result == null ? null : _correctAnswerText(q, result);
    final chosen = _answers[q.id] ?? const <String>[];
    final progress = _denominator == 0
        ? 0.0
        : (_answeredCount / _denominator).clamp(0.0, 1.0);
    // F26 chunk 8：判分可见即反查知识点（异步、每题一次），不阻塞渲染。
    if (_showAnalysis) _ensureQuestionPoints(q);

    return Column(
      children: [
        SizedBox(
          height: 56,
          child: Row(
            children: [
              IconButton(
                icon: const Icon(Icons.chevron_left),
                tooltip: '返回',
                onPressed: _handleBack,
              ),
              Expanded(
                child: Center(
                  child: Text(
                    '第 $_displayIndex/$_denominator 题',
                    style: TextStyle(
                      fontSize: AppFontSizes.detailBody,
                      fontWeight: FontWeight.w600,
                      color: AppColors.title(context),
                    ),
                  ),
                ),
              ),
              // F25：收藏按钮只在练习页出现，考试页没有（F28：轮回也没有）。
              if (!_isExam && !_isRotation)
                IconButton(
                  icon: Icon(
                    _favoriteIds.contains(q.id)
                        ? Icons.bookmark
                        : Icons.bookmark_border,
                    color: _favoriteIds.contains(q.id)
                        ? AppColors.accent(context)
                        : null,
                  ),
                  tooltip: _favoriteIds.contains(q.id) ? '取消收藏' : '收藏',
                  onPressed: _toggleFavorite,
                ),
              Padding(
                padding: const EdgeInsets.only(right: AppSpacing.md),
                child: Text(
                  '答对 $_correctCount · $_elapsedText',
                  style: TextStyle(
                    fontFamily: AppTheme.monoFontFamily,
                    fontSize: AppFontSizes.detailStat,
                    color: AppColors.cardCaption(context),
                  ),
                ),
              ),
            ],
          ),
        ),
        LinearProgressIndicator(
          value: progress,
          minHeight: 4,
          backgroundColor: AppColors.cardBorder(context),
          color: AppColors.accent(context),
        ),
        Container(
          height: AppSizes.divider,
          color: AppColors.cardBorder(context),
        ),
        Expanded(
          child: ListView(
            padding: const EdgeInsets.fromLTRB(
              AppSpacing.md,
              AppSpacing.md,
              AppSpacing.md,
              AppSpacing.md,
            ),
            children: [
              Align(
                alignment: Alignment.centerLeft,
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 3,
                  ),
                  decoration: BoxDecoration(
                    color: AppColors.cardSurface(context),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: AppColors.cardBorder(context)),
                  ),
                  child: Text(
                    questionTypeLabel(q.type),
                    style: TextStyle(
                      fontSize: AppFontSizes.detailStat,
                      color: AppColors.cardCaption(context),
                    ),
                  ),
                ),
              ),
              const SizedBox(height: AppSpacing.md),
              SelectableText(
                q.stem,
                style: TextStyle(
                  fontSize: AppFontSizes.detailBody + 1,
                  height: 1.6,
                  color: AppColors.title(context),
                ),
              ),
              const SizedBox(height: AppSpacing.md),
              for (final option in q.options)
                OptionTile(
                  option: option,
                  selected: chosen.contains(option.key),
                  multiple: q.type == 'multiple',
                  state: _optionState(q, option.key),
                  onTap: () => _selectOption(option.key),
                ),
              if (correctAnswer != null) ...[
                const SizedBox(height: AppSpacing.xs),
                Text(
                  correctAnswer,
                  style: TextStyle(
                    fontSize: AppFontSizes.detailBody,
                    fontWeight: FontWeight.w600,
                    color: AppColors.success(context),
                  ),
                ),
              ],
              if (_showAnalysis && result != null) ...[
                const SizedBox(height: AppSpacing.md),
                AnswerRecordsCard(
                  records: _records.take(2).toList(),
                  currentSummary: _currentSummary,
                  maxHeightFactor: AppSizes.recordsCardMaxHeightFactorQuiz,
                ),
                AnalysisCard(
                  question: q,
                  result: result,
                  chosen: chosen,
                  // F32：考试回顾卷面不含答案，「正确答案」行用服务端判分
                  // 明细（_resultFor 已把 grade.answer 并进 correctKeys）。
                  correctAnswerOverride: _isExam ? result.correctKeys : null,
                ),
                if ((_questionPoints[q.id] ?? const <KnowledgePoint>[])
                    .isNotEmpty)
                  _buildKnowledgeChip(_questionPoints[q.id]!.first),
              ],
            ],
          ),
        ),
        Container(
          height: AppSizes.divider,
          color: AppColors.cardBorder(context),
        ),
        if (_targetReached || _exhausted) _buildTargetBanner(),
        Padding(
          padding: const EdgeInsets.fromLTRB(
            AppSpacing.md,
            AppSpacing.sm,
            AppSpacing.md,
            AppSpacing.md,
          ),
          child: Row(
            children: [
              TextButton(
                onPressed: _currentIndex > 0
                    ? (_isExam ? _previousExam : _previousPractice)
                    : null,
                child: const Text('上一题'),
              ),
              const SizedBox(width: AppSpacing.sm),
              Expanded(
                child: SizedBox(
                  height: AppSizes.buttonHeight,
                  child: FilledButton(
                    onPressed: _primaryEnabled ? _onPrimary : null,
                    style: FilledButton.styleFrom(
                      backgroundColor: AppColors.accent(context),
                      foregroundColor: AppColors.brandSurface,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(
                          AppRadii.setDetailStartButton,
                        ),
                      ),
                    ),
                    child: Text(_primaryLabel),
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildTargetBanner() {
    final text = _exhausted ? '本题库已全部完成' : '已完成 $_target 题 · 答对 $_correctCount';
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.fromLTRB(
        AppSpacing.md,
        AppSpacing.xs,
        AppSpacing.md,
        0,
      ),
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.sm),
      decoration: BoxDecoration(
        color: AppColors.cardSurface(context),
        borderRadius: BorderRadius.circular(AppRadii.input),
        border: Border.all(color: AppColors.cardBorder(context)),
      ),
      child: Row(
        children: [
          Expanded(
            child: Text(
              text,
              style: TextStyle(
                fontSize: AppFontSizes.detailStat,
                color: AppColors.title(context),
              ),
            ),
          ),
          // F28：轮回是固定批次，没有「继续答题」（那会走 /practice/next）。
          if (!_exhausted && !_isExam && !_isRotation)
            TextButton(
              onPressed: _continueAfterTarget,
              child: const Text('继续答题'),
            ),
          if (!_isExam)
            TextButton(
              onPressed: _isRotation
                  ? _settleRotation
                  : () {
                      _finalizeCompletion();
                      Navigator.of(context).pop();
                    },
              child: const Text('结束本轮'),
            ),
        ],
      ),
    );
  }
}
