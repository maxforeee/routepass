/// 收藏页（规格文档第 3 章 §22.5 Q-06；第 4 章 FavoriteService）。
///
/// 列表来自 FavoriteService（带收藏时间，条目显示加入日期）；Mock 预置了两条
/// 今天的演示收藏（首页预览卡同源），真实收藏接口接上后自动换成接口数据。
library;

import 'package:flutter/material.dart';

import '../../core/service_locator.dart';
import '../../core/util/md_date.dart';
import '../../models/question.dart';
import '../../models/wrong_favorite.dart';
import '../../router/app_router.dart';

class FavoritesPage extends StatefulWidget {
  const FavoritesPage({super.key});

  @override
  State<FavoritesPage> createState() => _FavoritesPageState();
}

class _FavoritesPageState extends State<FavoritesPage> {
  bool _loading = true;
  List<(Favorite, Question)> _items = const <(Favorite, Question)>[];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final favorites = await ServiceLocator.favoriteService.getFavorites();
      final list = <(Favorite, Question)>[];
      for (final favorite in favorites) {
        final q = await ServiceLocator.questionRepository.getQuestionById(
          favorite.question_id,
        );
        if (q != null) list.add((favorite, q));
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
          : _items.isEmpty
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
                    itemCount: _items.length,
                    itemBuilder: (context, index) {
                      final (favorite, q) = _items[index];
                      return Card(
                        margin: const EdgeInsets.only(bottom: 8),
                        child: ListTile(
                          title: Text(
                            q.stem,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                          ),
                          subtitle: Text(
                            '${q.module} · 加入 '
                            '${formatMonthDay(favorite.created_at)}',
                          ),
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
