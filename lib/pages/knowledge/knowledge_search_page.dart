import 'dart:async';

import 'package:flutter/material.dart';

import '../../core/service_locator.dart';
import '../../models/search.dart';
import '../../router/app_router.dart';
import '../../widgets/animated_app_bar.dart';

/// 知识库搜索页（第 4 章 §4.5.2，路由 `/knowledge/search`）。
///
/// 输入后防抖 300ms 调 `SearchService.search`；结果分两个区（知识点区 / 题目区）。
/// 入口参数（RouteSettings.arguments，`Map<String, Object?>`）：query（String?，初始关键词）。
class KnowledgeSearchPage extends StatefulWidget {
  const KnowledgeSearchPage({super.key, required this.args});

  final Map<String, Object?> args;

  @override
  State<KnowledgeSearchPage> createState() => _KnowledgeSearchPageState();
}

class _KnowledgeSearchPageState extends State<KnowledgeSearchPage> {
  final TextEditingController _controller = TextEditingController();
  Timer? _debounce;
  SearchResult? _result;

  @override
  void initState() {
    super.initState();
    final initial = widget.args['query'] as String? ?? '';
    if (initial.isNotEmpty) {
      _controller.text = initial;
      _doSearch(initial);
    }
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _controller.dispose();
    super.dispose();
  }

  void _onChanged(String value) {
    _debounce?.cancel();
    if (value.trim().isEmpty) {
      setState(() {
        _result = null;
      });
      return;
    }
    _debounce = Timer(const Duration(milliseconds: 300), () {
      _doSearch(value);
    });
  }

  Future<void> _doSearch(String keyword) async {
    final key = keyword.trim();
    if (key.isEmpty) {
      if (!mounted) return;
      setState(() {
        _result = null;
      });
      return;
    }
    SearchResult result;
    try {
      result = await ServiceLocator.searchService.search(key);
    } catch (_) {
      result = SearchResult(knowledgePoints: [], questions: []);
    }
    if (!mounted) return;
    setState(() {
      _result = result;
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AnimatedAppBar(title: '搜索'),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
            child: SizedBox(
              height: 48,
              child: TextField(
                controller: _controller,
                autofocus: true,
                onChanged: _onChanged,
                decoration: InputDecoration(
                  hintText: '搜索知识点与题目',
                  prefixIcon: const Icon(Icons.search),
                  suffixIcon: _controller.text.isEmpty
                      ? null
                      : IconButton(
                          icon: const Icon(Icons.clear),
                          onPressed: () {
                            _controller.clear();
                            _onChanged('');
                          },
                        ),
                  filled: true,
                  fillColor: theme.colorScheme.surfaceContainerHighest,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: BorderSide.none,
                  ),
                  contentPadding: const EdgeInsets.symmetric(horizontal: 16),
                ),
              ),
            ),
          ),
          Expanded(child: _buildBody()),
        ],
      ),
    );
  }

  Widget _buildBody() {
    final theme = Theme.of(context);
    final query = _controller.text.trim();
    if (query.isEmpty) {
      return const Center(child: Text('输入关键词搜索知识点与题目'));
    }
    if (_result == null) {
      return const Center(child: CircularProgressIndicator());
    }
    final result = _result!;
    if (result.knowledgePoints.isEmpty && result.questions.isEmpty) {
      return const Center(child: Text('没有找到相关内容'));
    }
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
      children: [
        if (result.knowledgePoints.isNotEmpty) ...[
          Text('知识点', style: theme.textTheme.titleMedium),
          const SizedBox(height: 8),
          ...result.knowledgePoints.map(
            (p) => InkWell(
              onTap: () => Navigator.of(context).pushNamed(
                AppRoutes.knowledgePoint,
                arguments: <String, Object?>{
                  'kpId': p.id,
                  'returnTo': 'knowledge',
                },
              ),
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 8),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(p.title, style: theme.textTheme.titleSmall),
                    const SizedBox(height: 2),
                    Text(
                      p.summary,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
            ),
          ),
          const Divider(height: 24),
        ],
        if (result.questions.isNotEmpty) ...[
          Text('题目', style: theme.textTheme.titleMedium),
          const SizedBox(height: 8),
          ...result.questions.map(
            (q) => InkWell(
              onTap: () => Navigator.of(context).pushNamed(
                AppRoutes.bankQuiz,
                arguments: <String, Object?>{
                  'mode': 'single',
                  'questionId': q.id,
                  'returnTo': 'knowledge',
                },
              ),
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 8),
                child: Text(
                  q.stem,
                  style: theme.textTheme.bodyMedium,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ),
          ),
        ],
      ],
    );
  }
}
