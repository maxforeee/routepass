/// 收藏页（规格文档第 3 章 §22.5 Q-06；第 4 章 FavoriteService）。
///
/// Mock 下收藏列表为空，显示空态，不编造题目。
library;

import 'package:flutter/material.dart';

import '../../core/service_locator.dart';
import '../../models/question.dart';
import '../../router/app_router.dart';

class FavoritesPage extends StatefulWidget {
  const FavoritesPage({super.key});

  @override
  State<FavoritesPage> createState() => _FavoritesPageState();
}

class _FavoritesPageState extends State<FavoritesPage> {
  bool _loading = true;
  List<Question> _questions = const <Question>[];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final ids = await ServiceLocator.favoriteService.getFavoriteIds();
      final list = <Question>[];
      for (final id in ids) {
        final q = await ServiceLocator.questionRepository.getQuestionById(id);
        if (q != null) list.add(q);
      }
      if (!mounted) return;
      setState(() {
        _questions = list;
        _loading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _loading = false);
    }
  }

  void _openFavoritePractice() {
    Navigator.of(context).pushNamed(
      AppRoutes.bankQuiz,
      arguments: <String, Object?>{'mode': 'favorite'},
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(title: const Text('收藏')),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _questions.isEmpty
          ? Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.bookmark_border, size: 48),
                  const SizedBox(height: 12),
                  Text('暂无收藏', style: theme.textTheme.titleMedium),
                  const SizedBox(height: 4),
                  Text(
                    '答题页点收藏图标可收藏题目',
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
                    onPressed: _openFavoritePractice,
                    style: FilledButton.styleFrom(
                      minimumSize: const Size.fromHeight(48),
                    ),
                    child: const Text('开始收藏练习'),
                  ),
                ),
                Expanded(
                  child: ListView.builder(
                    padding: const EdgeInsets.fromLTRB(16, 4, 16, 16),
                    itemCount: _questions.length,
                    itemBuilder: (context, index) {
                      final q = _questions[index];
                      return Card(
                        margin: const EdgeInsets.only(bottom: 8),
                        child: ListTile(
                          title: Text(
                            q.stem,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                          ),
                          subtitle: Text(q.module),
                          trailing: IconButton(
                            icon: const Icon(Icons.bookmark),
                            tooltip: '取消收藏',
                            onPressed: () async {
                              try {
                                await ServiceLocator.favoriteService
                                    .toggleFavorite(q.id, false);
                              } catch (_) {}
                              await _load();
                            },
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
