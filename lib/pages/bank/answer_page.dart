/// 答题页（规格文档第 3 章 §22.6：A-01–A-17）。
///
/// 入口参数（RouteSettings.arguments，`Map<String, Object?>`）：
/// mode（'quick' | 'practice' | 'exam' | 'daily' | 'wrong' | 'favorite' | 'single'）、
/// drawCount（int，抽题数）、questionId（String，单题/续作）、
/// questionIds（`List<String>`，指定题单）、knowledgePointId（String，按知识点抽题）、
/// returnTo（String，返回来源：'home' | 'bank' | 'knowledge' | 'answer'）。
/// 练习模式逐题 submitAnswer（Mock 不判对错，解析卡只显示占位文案）；
/// 考试模式只在交卷时 submitExam（Mock score 恒为 null，不计分）。
library;

import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';

import '../../core/kv_store.dart';
import '../../core/service_locator.dart';
import '../../models/practice.dart';
import '../../models/question.dart';
import '../../router/app_router.dart';
import 'answer_widgets.dart';

class AnswerPage extends StatefulWidget {
  const AnswerPage({super.key, required this.args});

  final Map<String, Object?> args;

  @override
  State<AnswerPage> createState() => _AnswerPageState();
}

class _AnswerPageState extends State<AnswerPage> {
  bool _loading = true;
  String? _error;
  List<Question> _questions = const <Question>[];
  String _sessionId = '';
  String? _examId;
  bool _isExam = false;
  String _mode = 'practice';
  int _currentIndex = 0;
  final Map<String, List<String>> _answers = <String, List<String>>{};
  final Map<String, AnswerResult> _submitted = <String, AnswerResult>{};
  final Set<String> _marked = <String>{};
  Set<String> _favorites = <String>{};
  final Map<String, TextEditingController> _fillControllers =
      <String, TextEditingController>{};
  late DateTime _startTime;
  Duration _elapsed = Duration.zero;
  Timer? _timer;
  DateTime _questionStartTime = DateTime.now();

  String get _modeLabel {
    return switch (_mode) {
      'quick' => '快速 10 题',
      'exam' => '套卷考试',
      'daily' => '每日一练',
      'wrong' => '错题练习',
      'favorite' => '收藏练习',
      'single' => '单题作答',
      _ => '练习',
    };
  }

  @override
  void initState() {
    super.initState();
    _startTime = DateTime.now();
    _questionStartTime = _startTime;
    _init();
  }

  @override
  void dispose() {
    _timer?.cancel();
    for (final c in _fillControllers.values) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _init() async {
    final args = widget.args;
    final mode = args['mode'] as String? ?? 'practice';
    final drawCount = args['drawCount'] as int? ?? 10;
    final questionId = args['questionId'] as String?;
    final questionIds = (args['questionIds'] as List<dynamic>?)
        ?.map((e) => e.toString())
        .toList();
    final knowledgePointId = args['knowledgePointId'] as String?;
    try {
      List<Question> questions;
      String sessionId = '';
      String? examId;
      bool isExam = false;
      int startIndex = 0;
      if (mode == 'exam') {
        final session =
            await ServiceLocator.examService.startExam(drawCount: drawCount);
        // 考试快照没有 id/module/type，就地转成 Question（合成 id，type 默认为 single）。
        questions = session.snapshot.asMap().entries.map((e) {
          final s = e.value;
          return Question(
            id: 'EXAM-${e.key}',
            module: '',
            type: 'single',
            stem: s.stem,
            options: s.options,
            answer: s.answer,
            explanation: s.analysis,
            knowledge_point_id: '',
            difficulty: 1,
            set_no: 0,
            row_version: 0,
          );
        }).toList();
        examId = session.id;
        isExam = true;
      } else if (mode == 'single' && questionId != null) {
        final q =
            await ServiceLocator.questionRepository.getQuestionById(questionId);
        questions = q == null ? const <Question>[] : <Question>[q];
        final s = await ServiceLocator.practiceService.startSession(
          questions: questions,
          mode: mode,
        );
        sessionId = s.id;
      } else if (mode == 'wrong' || mode == 'favorite') {
        final ids = mode == 'wrong'
            ? (await ServiceLocator.wrongService.getWrongBook())
                .map((w) => w.question_id)
                .toList()
            : await ServiceLocator.favoriteService.getFavoriteIds();
        final list = <Question>[];
        for (final id in ids) {
          final q =
              await ServiceLocator.questionRepository.getQuestionById(id);
          if (q != null) list.add(q);
        }
        questions = list;
        final s = await ServiceLocator.practiceService.startSession(
          questions: questions,
          mode: 'practice',
        );
        sessionId = s.id;
      } else if (questionIds != null && questionIds.isNotEmpty) {
        final list = <Question>[];
        for (final id in questionIds) {
          final q =
              await ServiceLocator.questionRepository.getQuestionById(id);
          if (q != null) list.add(q);
        }
        questions = list;
        final s = await ServiceLocator.practiceService.startSession(
          questions: questions,
          mode: mode,
        );
        sessionId = s.id;
      } else {
        questions = await ServiceLocator.questionRepository.drawQuestions(
          mode: mode,
          drawCount: drawCount,
          knowledgePointId: knowledgePointId,
        );
        final s = await ServiceLocator.practiceService.startSession(
          questions: questions,
          mode: mode,
        );
        sessionId = s.id;
        if (questionId != null) {
          final idx = questions.indexWhere((q) => q.id == questionId);
          if (idx >= 0) startIndex = idx;
        }
      }
      final favorites =
          await ServiceLocator.favoriteService.getFavoriteIds();
      if (!mounted) return;
      setState(() {
        _mode = mode;
        _questions = questions;
        _sessionId = sessionId;
        _examId = examId;
        _isExam = isExam;
        _currentIndex = startIndex;
        _favorites = favorites.toSet();
        _loading = false;
        _error = questions.isEmpty ? '暂无题目' : null;
      });
      _timer = Timer.periodic(const Duration(seconds: 1), (_) {
        if (!mounted) return;
        setState(() {
          _elapsed = DateTime.now().difference(_startTime);
        });
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = '加载失败，请重试';
      });
    }
  }

  Question get _current => _questions[_currentIndex];

  String get _elapsedText {
    final m = _elapsed.inMinutes.remainder(60).toString().padLeft(2, '0');
    final s = _elapsed.inSeconds.remainder(60).toString().padLeft(2, '0');
    return '$m:$s';
  }

  int get _answeredCount =>
      _answers.values.where((a) => a.isNotEmpty).length;

  void _selectOption(String key) {
    final q = _current;
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
    });
  }

  List<String> _fillAnswers(Question q) {
    final blankCount = q.answer.isEmpty ? 1 : q.answer.length;
    final values = <String>[];
    for (var i = 0; i < blankCount; i++) {
      final c = _fillControllers['${q.id}_$i'];
      values.add(c?.text.trim() ?? '');
    }
    return values;
  }

  Future<void> _goTo(int index) async {
    if (index < 0 || index >= _questions.length) return;
    setState(() {
      _currentIndex = index;
      _questionStartTime = DateTime.now();
    });
  }

  Future<void> _next() async {
    final q = _current;
    final chosen = q.type == 'fill'
        ? _fillAnswers(q)
        : List<String>.from(_answers[q.id] ?? const <String>[]);
    if (!_isExam && chosen.any((c) => c.isNotEmpty)) {
      // 练习模式：点“下一题”时提交本题（Mock 不判对错，解析卡只显示占位文案）。
      final durationMs =
          DateTime.now().difference(_questionStartTime).inMilliseconds;
      try {
        final result = await ServiceLocator.practiceService.submitAnswer(
          sessionId: _sessionId,
          questionId: q.id,
          chosen: chosen,
          durationMs: durationMs,
        );
        if (!mounted) return;
        setState(() {
          _answers[q.id] = chosen;
          _submitted[q.id] = result;
        });
      } catch (_) {
        if (!mounted) return;
        setState(() => _answers[q.id] = chosen);
      }
    } else if (q.type == 'fill') {
      setState(() => _answers[q.id] = chosen);
    }
    if (_currentIndex == _questions.length - 1) {
      await _submit();
    } else {
      await _goTo(_currentIndex + 1);
    }
  }

  Future<void> _submit() async {
    final unanswered = _questions.length - _answeredCount;
    final confirmed =
        await showSubmitDialog(context, unanswered: unanswered);
    if (!confirmed || !mounted) return;
    int? score;
    String detail = '';
    if (_isExam) {
      try {
        final result = await ServiceLocator.examService.submitExam(
          examId: _examId ?? '',
          answers: Map<String, List<String>>.from(_answers),
          durationMs: _elapsed.inMilliseconds,
        );
        score = result?.score;
        detail = result?.detail ?? '';
      } catch (_) {
        score = null;
        detail = '样例考试，不计分';
      }
    }
    if (!mounted) return;
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (sheetContext) {
        return ResultSheetContent(
          total: _questions.length,
          answered: _answeredCount,
          elapsed: _elapsed,
          score: score,
          detail: detail,
          isExam: _isExam,
          questions: _questions,
          answers: _answers,
          onReview: (index) {
            Navigator.of(sheetContext).pop();
            _goTo(index);
          },
          onRetryWrong: () {
            Navigator.of(sheetContext).pop();
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('暂无错题')),
            );
          },
          onClose: () {
            Navigator.of(sheetContext).pop();
            _finish();
          },
        );
      },
    );
  }

  void _finish() {
    // 会话完成，清除首页“继续学习”进度指针。
    try {
      ServiceLocator.kvStore.remove(KvStore.keyHomeContinue);
    } catch (_) {}
    Navigator.of(context).pop();
  }

  Future<void> _onBack() async {
    final exit = await showExitConfirmDialog(context);
    if (!exit || !mounted) return;
    // 退出保留进度：把进度指针写进 kv（home.continue），首页 H-B1 恢复用。
    try {
      final session = ContinueSession(
        mode: _mode,
        questionId: _questions.isEmpty ? null : _current.id,
        answeredCount: _answeredCount,
        totalCount: _questions.length,
      );
      ServiceLocator.kvStore.setString(
        KvStore.keyHomeContinue,
        jsonEncode(session.toJson()),
      );
    } catch (_) {}
    Navigator.of(context).pop();
  }

  Future<void> _toggleFavorite() async {
    final q = _current;
    final on = !_favorites.contains(q.id);
    setState(() {
      if (on) {
        _favorites.add(q.id);
      } else {
        _favorites.remove(q.id);
      }
    });
    try {
      await ServiceLocator.favoriteService.toggleFavorite(q.id, on);
    } catch (_) {}
  }

  void _openAnswerSheet() {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (sheetContext) {
        return AnswerSheetContent(
          questions: _questions,
          answers: _answers,
          marked: _marked,
          currentIndex: _currentIndex,
          onJump: (index) {
            Navigator.of(sheetContext).pop();
            _goTo(index);
          },
        );
      },
    );
  }

  Widget _buildOptions(Question q) {
    if (q.type == 'fill') {
      final blankCount = q.answer.isEmpty ? 1 : q.answer.length;
      return Column(
        children: List<Widget>.generate(blankCount, (i) {
          final controller = _fillControllers.putIfAbsent(
            '${q.id}_$i',
            () => TextEditingController(
              text: (_answers[q.id] ?? const <String>[]).length > i
                  ? _answers[q.id]![i]
                  : '',
            ),
          );
          return Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: TextField(
              controller: controller,
              decoration: InputDecoration(
                labelText: '填空 ${i + 1}',
                border: const OutlineInputBorder(),
              ),
              onChanged: (_) {
                setState(() => _answers[q.id] = _fillAnswers(q));
              },
            ),
          );
        }),
      );
    }
    final multiple = q.type == 'multiple';
    final chosen = _answers[q.id] ?? const <String>[];
    return Column(
      children: q.options.map((o) {
        return OptionTile(
          option: o,
          selected: chosen.contains(o.key),
          multiple: multiple,
          onTap: () => _selectOption(o.key),
        );
      }).toList(),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    if (_loading) {
      return const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      );
    }
    if (_error != null || _questions.isEmpty) {
      return Scaffold(
        appBar: AppBar(title: Text(_modeLabel)),
        body: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(_error ?? '暂无题目'),
              const SizedBox(height: 16),
              FilledButton(
                onPressed: () => Navigator.of(context).pop(),
                child: const Text('返回'),
              ),
            ],
          ),
        ),
      );
    }
    final q = _current;
    final chosen = _answers[q.id] ?? const <String>[];
    final submitted = _submitted[q.id];
    final isFavorite = _favorites.contains(q.id);
    final isMarked = _marked.contains(q.id);
    final isLast = _currentIndex == _questions.length - 1;
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) async {
        if (didPop) return;
        await _onBack();
      },
      child: Scaffold(
        appBar: AppBar(
          leading: IconButton(
            icon: const Icon(Icons.arrow_back),
            tooltip: '返回',
            onPressed: _onBack,
          ),
          title: Text(
            '第 ${_currentIndex + 1}/${_questions.length} 题',
            style: theme.textTheme.titleMedium,
          ),
          actions: [
            Text(
              _elapsedText,
              style: theme.textTheme.bodyMedium?.copyWith(
                fontFamily: 'monospace',
              ),
            ),
            IconButton(
              icon: Icon(
                isMarked ? Icons.flag : Icons.flag_outlined,
                color: isMarked ? theme.colorScheme.error : null,
              ),
              tooltip: isMarked ? '取消标记' : '标记',
              onPressed: () {
                setState(() {
                  if (isMarked) {
                    _marked.remove(q.id);
                  } else {
                    _marked.add(q.id);
                  }
                });
              },
            ),
            IconButton(
              icon: Icon(
                isFavorite ? Icons.bookmark : Icons.bookmark_border,
              ),
              tooltip: isFavorite ? '取消收藏' : '收藏',
              onPressed: _toggleFavorite,
            ),
            IconButton(
              icon: const Icon(Icons.grid_view),
              tooltip: '答题卡',
              onPressed: _openAnswerSheet,
            ),
          ],
        ),
        body: Column(
          children: [
            LinearProgressIndicator(
              value: _questions.isEmpty
                  ? 0
                  : _answeredCount / _questions.length,
              minHeight: 4,
            ),
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Chip(
                      label: Text(questionTypeLabel(q.type)),
                      visualDensity: VisualDensity.compact,
                    ),
                    const SizedBox(height: 8),
                    SelectableText(
                      q.stem,
                      style: theme.textTheme.bodyLarge?.copyWith(
                        height: 1.6,
                      ),
                    ),
                    const SizedBox(height: 16),
                    _buildOptions(q),
                    if (submitted != null)
                      AnalysisCard(
                        question: q,
                        result: submitted,
                        chosen: chosen,
                      ),
                    if (q.knowledge_point_id.isNotEmpty) ...[
                      const SizedBox(height: 16),
                      Wrap(
                        spacing: 8,
                        children: [
                          ActionChip(
                            label: Text('知识点：${q.knowledge_point_id}'),
                            onPressed: () {
                              Navigator.of(context).pushNamed(
                                AppRoutes.knowledgePoint,
                                arguments: <String, Object?>{
                                  'kpId': q.knowledge_point_id,
                                  'returnTo': 'answer',
                                },
                              );
                            },
                          ),
                        ],
                      ),
                    ],
                  ],
                ),
              ),
            ),
            SafeArea(
              top: false,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
                child: Row(
                  children: [
                    Expanded(
                      child: OutlinedButton(
                        onPressed: _currentIndex == 0
                            ? null
                            : () => _goTo(_currentIndex - 1),
                        style: OutlinedButton.styleFrom(
                          minimumSize: const Size.fromHeight(48),
                        ),
                        child: const Text('上一题'),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: FilledButton(
                        onPressed: _next,
                        style: FilledButton.styleFrom(
                          minimumSize: const Size.fromHeight(48),
                        ),
                        child: Text(isLast ? '提交' : '下一题'),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
