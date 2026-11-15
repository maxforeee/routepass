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

import '../../core/app_animations.dart';
import '../../core/app_snackbar.dart';
import '../../core/service_locator.dart';
import '../../core/theme.dart';
import '../../models/answer_record.dart';
import '../../models/answer_session_state.dart';
import '../../models/practice.dart';
import '../../models/question.dart';
import '../../services/bank/answer_record_service.dart';
import '../../services/bank/answer_session_service.dart';
import '../../services/bank/exam_service.dart';
import '../../services/bank/practice_service.dart';
import '../../widgets/answer_records_card.dart';
import 'answer_widgets.dart';

class QuizPage extends StatefulWidget {
  const QuizPage({
    super.key,
    required this.args,
    this.practiceService,
    this.examService,
    this.recordService,
    this.sessionService,
  });

  final Map<String, Object?> args;

  /// 测试可注入；生产环境不传，走 ServiceLocator。
  final PracticeService? practiceService;
  final ExamService? examService;
  final AnswerRecordService? recordService;
  final AnswerSessionService? sessionService;

  @override
  State<QuizPage> createState() => _QuizPageState();
}

class _QuizPageState extends State<QuizPage> {
  late final PracticeService _practice;
  late final ExamService _exam;
  late final AnswerRecordService _recordService;
  late final AnswerSessionService _sessionService;

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
  List<AnswerRecord> _records = <AnswerRecord>[];

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

  String? _completionRecordId;
  int _completionCreatedAt = 0;

  @override
  void initState() {
    super.initState();
    _isExam = widget.args['mode'] == 'exam';
    if (_isExam) {
      _exam = widget.examService ?? ServiceLocator.examService;
    } else {
      _practice = widget.practiceService ?? ServiceLocator.practiceService;
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
    _timer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!mounted) return;
      setState(() => _elapsed = DateTime.now().difference(_startedAt));
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
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
    } else if (saved != null) {
      // 达标后退出：保留 completion，不恢复进行态（下次从新会话开始）。
      _sessionService.clear(setId: _setId, mode: 'practice');
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

  Future<void> _initExam() async {
    final saved = _sessionService.load(setId: _setId, mode: 'exam');
    if (saved != null && saved.examId != null) {
      _examId = saved.examId;
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

    final session = await _exam.startExam(drawCount: _total, setId: _setId);
    _examId = session.id;
    _questions = session.snapshot.asMap().entries.map((entry) {
      final snapshot = entry.value;
      return Question(
        id: 'EXAM-${entry.key}',
        module: '',
        type: 'single',
        stem: snapshot.stem,
        options: snapshot.options,
        answer: snapshot.answer,
        explanation: snapshot.analysis,
        knowledge_point_id: '',
        difficulty: 1,
        set_no: 0,
        row_version: 0,
      );
    }).toList();
    if (_questions.isEmpty) {
      throw StateError('empty exam');
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

  List<String> get _chosen {
    final q = _current;
    if (q == null) return const <String>[];
    return _answers[q.id] ?? const <String>[];
  }

  void _selectOption(String key) {
    final q = _current;
    if (q == null) return;
    if (_graded.containsKey(q.id) || (_isExam && _reviewMode)) return;
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
        durationMs: DateTime.now().difference(_startedAt).inMilliseconds,
        createdAt: _completionCreatedAt,
        updatedAt: now,
      ),
    );
  }

  void _finalizeCompletion() {
    if (_answeredCount > 0) _writeCompletion();
    _sessionService.clear(setId: _setId, mode: 'practice');
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
        durationMs: DateTime.now().difference(_startedAt).inMilliseconds,
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
      ),
    );
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
      ),
    );
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
        durationMs: DateTime.now().difference(_startedAt).inMilliseconds,
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
    });
    _writeExamCompletion(score);
    _sessionService.clear(setId: _setId, mode: 'exam');
    _refreshRecords();

    await showAppSheet<void>(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (sheetContext) {
        return ResultSheetContent(
          total: _total,
          answered: _answeredCount,
          elapsed: DateTime.now().difference(_startedAt),
          score: score,
          detail: detail,
          isExam: true,
          questions: _questions,
          answers: _answers,
          onReview: (index) {
            Navigator.of(sheetContext).pop();
            if (!mounted) return;
            setState(() {
              _reviewMode = true;
              _currentIndex = index.clamp(0, _questions.length - 1);
            });
            unawaited(_loadExamGrading());
          },
          onRetryWrong: () {
            Navigator.of(sheetContext).pop();
          },
          onClose: () {
            Navigator.of(sheetContext).pop();
            Navigator.of(context).pop();
          },
        );
      },
    );
  }

  /// B14：进入回顾后拉取服务端判分，不阻塞回顾界面。失败或空结果保持
  /// 空 map——没有判分依据就只标已选，绝不本地猜对错。
  Future<void> _loadExamGrading() async {
    final examId = _examId;
    if (examId == null || examId.isEmpty) return;
    try {
      final grading = await _exam.loadExamGrading(examId);
      if (!mounted || grading.isEmpty) return;
      setState(() {
        _examGrading
          ..clear()
          ..addAll(grading);
      });
    } catch (_) {
      // 保持空 map，回顾走原有兜底。
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
        durationMs: DateTime.now().difference(_startedAt).inMilliseconds,
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
        durationMs: DateTime.now().difference(_startedAt).inMilliseconds,
        createdAt: now,
        updatedAt: now,
      ),
    );
  }

  Future<void> _handleBack() async {
    if (_loading) return;
    if (_isExam && _reviewMode) {
      Navigator.of(context).pop();
      return;
    }
    if (_isExam) {
      if (_answeredCount == 0) {
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
    if (q != null && _graded.containsKey(q.id)) return '下一题';
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
    } else {
      final q = _current;
      if (q == null) return;
      if (_graded.containsKey(q.id)) {
        await _nextPractice();
      } else {
        await _submitPractice();
      }
    }
  }

  String get _currentSummary {
    if (_isExam) {
      return _score == null
          ? '本次 · 已答 $_answeredCount/$_total 题'
          : '本次 · 得分 $_score';
    }
    return '本次 · 已答 $_answeredCount/$_target 题 · 答对 $_correctCount 题';
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
                AnalysisCard(question: q, result: result, chosen: chosen),
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
          if (!_exhausted && !_isExam)
            TextButton(
              onPressed: _continueAfterTarget,
              child: const Text('继续答题'),
            ),
          if (!_isExam)
            TextButton(
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
}
