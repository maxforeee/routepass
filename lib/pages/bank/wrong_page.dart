/// 错题本页（规格文档第 3 章 §22.5 Q-05；第 4 章 §4.4.2 WrongService）。
///
/// Mock 下错题列表为空，显示空态，不编造题目。
library;

import 'package:flutter/material.dart';

import '../../core/service_locator.dart';
import '../../models/question.dart';
import '../../models/wrong_favorite.dart';
import '../../router/app_router.dart';

class WrongPage extends StatefulWidget {
  const WrongPage({super.key});

  @override
  State<WrongPage> createState() => _WrongPageState();
}

class _WrongPageState extends State<WrongPage> {
  bool _loading = true;
  List<(WrongItem, Question)> _items = const <(WrongItem, Question)>[];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final wrong = await ServiceLocator.wrongService.getWrongBook();
      final list = <(WrongItem, Question)>[];
      for (final w in wrong) {
        final q =
            await ServiceLocator.questionRepository.getQuestionById(w.question_id);
        if (q != null) list.add((w, q));
      }
      if (!mounted) return;
      setState(() {
        _items = list;
        _loading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _loading = false);
    }
  }

  Future<void> _markMastered(String questionId) async {
    try {
      await ServiceLocator.wrongService.markMastered(questionId);
    } catch (_) {}
    await _load();
  }

  Future<void> _remove(String questionId) async {
    try {
      await ServiceLocator.wrongService.removeWrong(questionId);
    } catch (_) {}
    await _load();
  }

  void _openWrongPractice() {
    Navigator.of(context).pushNamed(
      AppRoutes.bankQuiz,
      arguments: <String, Object?>{'mode': 'wrong'},
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(title: const Text('错题本')),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _items.isEmpty
              ? Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(Icons.check_circle_outline, size: 48),
                      const SizedBox(height: 12),
                      Text(
                        '暂无错题',
                        style: theme.textTheme.titleMedium,
                      ),
                      const SizedBox(height: 4),
                      Text(
                        '做错的题目会出现在这里',
                        style: theme.textTheme.bodyMedium?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                )
              : Column(
                  children: [
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
                      child: FilledButton(
                        onPressed: _openWrongPractice,
                        style: FilledButton.styleFrom(
                          minimumSize: const Size.fromHeight(48),
                        ),
                        child: const Text('开始错题练习'),
                      ),
                    ),
                    Expanded(
                      child: ListView.builder(
                        padding: const EdgeInsets.fromLTRB(16, 4, 16, 16),
                        itemCount: _items.length,
                        itemBuilder: (context, index) {
                          final (item, q) = _items[index];
                          return Card(
                            margin: const EdgeInsets.only(bottom: 8),
                            child: ListTile(
                              title: Text(
                                q.stem,
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                              ),
                              subtitle: Text(
                                '错 ${item.wrong_count} 次${item.mastered ? ' · 已掌握' : ''}',
                              ),
                              trailing: PopupMenuButton<String>(
                                onSelected: (v) {
                                  if (v == 'mastered') {
                                    _markMastered(q.id);
                                  } else if (v == 'remove') {
                                    _remove(q.id);
                                  }
                                },
                                itemBuilder: (context) => const [
                                  PopupMenuItem(
                                    value: 'mastered',
                                    child: Text('标记已掌握'),
                                  ),
                                  PopupMenuItem(
                                    value: 'remove',
                                    child: Text('移除'),
                                  ),
                                ],
                              ),
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
                      ),
                    ),
                  ],
                ),
    );
  }
}
