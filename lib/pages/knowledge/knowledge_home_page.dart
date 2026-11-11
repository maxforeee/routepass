import 'dart:convert';

import 'package:flutter/material.dart';

import '../../core/kv_store.dart';
import '../../core/service_locator.dart';
import '../../models/knowledge_point.dart';
import '../../router/app_router.dart';

/// 知识库页（第 3 章 §22.7：章→节→知识点三层，倒三角展开，同节单开手风琴）。
///
/// K-01 顶栏；K-02 搜索（输入即过滤，提交进搜索页）；K-03 掌握进度；K-04 章 header；
/// K-05 节 header；K-06 知识点行；K-07 倒三角（220ms 旋转）；K-08 展开面板；
/// K-09 查看详情；K-10 练一练；K-11 掌握 icon；K-13 空态。K-12 版本条由 AppShell 全局显示，不在本页重复。
/// 展开态存 kv `kb.expandedIds`（§4.9.1）；掌握态存派生 kv 键 `kb.masteredIds`。
class KnowledgeHomePage extends StatefulWidget {
  const KnowledgeHomePage({super.key});

  @override
  State<KnowledgeHomePage> createState() => _KnowledgeHomePageState();
}

class _KnowledgeHomePageState extends State<KnowledgeHomePage> {
  /// 掌握态的本地 kv 键（派生键，不在 §4.9.1 表内：§4.9.1 没有给知识点掌握态留键；
  /// 与 `kb.expandedIds` 同为设备本地 UI 状态，只存本地，不走账号同步）。
  static const String _keyMasteredIds = 'kb.masteredIds';

  bool _loading = true;
  List<Chapter> _chapters = <Chapter>[];
  final Map<String, List<Section>> _sections = <String, List<Section>>{};
  final Map<String, List<KnowledgePoint>> _points =
      <String, List<KnowledgePoint>>{};
  final Set<String> _expandedPoints = <String>{};
  final Set<String> _collapsedSections = <String>{};
  final Set<String> _collapsedChapters = <String>{};
  final Set<String> _mastered = <String>{};
  String _query = '';
  final TextEditingController _searchController = TextEditingController();
  final GlobalKey _firstMatchKey = GlobalKey();

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final expanded = _readIdList(KvStore.keyKbExpandedIds);
    final mastered = _readIdList(_keyMasteredIds);
    var chapters = <Chapter>[];
    try {
      chapters = await ServiceLocator.knowledgeRepository.getChapters();
    } catch (_) {
      chapters = <Chapter>[];
    }
    final sections = <String, List<Section>>{};
    final points = <String, List<KnowledgePoint>>{};
    for (final chapter in chapters) {
      var chapterSections = <Section>[];
      try {
        chapterSections = await ServiceLocator.knowledgeRepository
            .getSections(chapter.id);
      } catch (_) {}
      sections[chapter.id] = chapterSections;
      for (final section in chapterSections) {
        var sectionPoints = <KnowledgePoint>[];
        try {
          sectionPoints = await ServiceLocator.knowledgeRepository
              .getPointsBySection(section.id);
        } catch (_) {}
        points[section.id] = sectionPoints;
      }
    }
    if (!mounted) return;
    setState(() {
      _chapters = chapters;
      _sections
        ..clear()
        ..addAll(sections);
      _points
        ..clear()
        ..addAll(points);
      _expandedPoints
        ..clear()
        ..addAll(expanded);
      _mastered
        ..clear()
        ..addAll(mastered);
      _loading = false;
    });
  }

  List<String> _readIdList(String key) {
    final raw = ServiceLocator.kvStore.getString(key);
    if (raw == null || raw.isEmpty) return <String>[];
    try {
      final decoded = jsonDecode(raw) as List<dynamic>;
      return decoded.cast<String>();
    } catch (_) {
      return <String>[];
    }
  }

  void _saveIdList(String key, Set<String> ids) {
    try {
      ServiceLocator.kvStore.setString(key, jsonEncode(ids.toList()));
    } catch (_) {}
  }

  bool get _searching => _query.trim().isNotEmpty;

  bool _matches(KnowledgePoint point) {
    final q = _query.trim();
    if (q.isEmpty) return true;
    return point.title.contains(q) || point.summary.contains(q);
  }

  List<KnowledgePoint> _visiblePoints(String sectionId) {
    final all = _points[sectionId] ?? <KnowledgePoint>[];
    if (!_searching) return all;
    return all.where(_matches).toList();
  }

  int get _totalPoints {
    var n = 0;
    for (final list in _points.values) {
      n += list.length;
    }
    return n;
  }

  int get _masteredCount {
    final allIds = <String>{};
    for (final list in _points.values) {
      for (final p in list) {
        allIds.add(p.id);
      }
    }
    return _mastered.intersection(allIds).length;
  }

  /// 搜索时第一个命中点的 id（用于自动滚动定位）。
  String? get _firstMatchId {
    if (!_searching) return null;
    for (final chapter in _chapters) {
      for (final section in _sections[chapter.id] ?? <Section>[]) {
        final visible = _visiblePoints(section.id);
        if (visible.isNotEmpty) return visible.first.id;
      }
    }
    return null;
  }

  int get _visibleTotal {
    var n = 0;
    for (final chapter in _chapters) {
      for (final section in _sections[chapter.id] ?? <Section>[]) {
        n += _visiblePoints(section.id).length;
      }
    }
    return n;
  }

  /// 点知识点行或倒三角：同节单开（先收起同节其他已开项），展开态写 kv。
  void _togglePoint(KnowledgePoint point, String sectionId) {
    setState(() {
      if (_expandedPoints.contains(point.id)) {
        _expandedPoints.remove(point.id);
      } else {
        final siblings = _points[sectionId] ?? <KnowledgePoint>[];
        for (final s in siblings) {
          _expandedPoints.remove(s.id);
        }
        _expandedPoints.add(point.id);
      }
    });
    _saveIdList(KvStore.keyKbExpandedIds, _expandedPoints);
  }

  void _toggleMastered(String pointId) {
    setState(() {
      if (_mastered.contains(pointId)) {
        _mastered.remove(pointId);
      } else {
        _mastered.add(pointId);
      }
    });
    _saveIdList(_keyMasteredIds, _mastered);
  }

  void _onSearchChanged(String value) {
    setState(() {
      _query = value;
    });
    if (_searching) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        final context = _firstMatchKey.currentContext;
        if (context != null && mounted) {
          Scrollable.ensureVisible(
            context,
            duration: const Duration(milliseconds: 220),
          );
        }
      });
    }
  }

  void _openSearchPage() {
    Navigator.of(context).pushNamed(
      AppRoutes.knowledgeSearch,
      arguments: <String, Object?>{'query': _query.trim()},
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('知识库')),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _chapters.isEmpty
              ? const Center(child: Text('暂无知识点，请更新'))
              : ListView(
                  padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
                  children: [
                    _buildSearch(),
                    const SizedBox(height: 12),
                    _buildProgress(),
                    const SizedBox(height: 8),
                    if (_searching && _visibleTotal == 0)
                      const Padding(
                        padding: EdgeInsets.only(top: 48),
                        child: Center(child: Text('没有找到相关知识点')),
                      )
                    else
                      ..._chapters.map(_buildChapter),
                  ],
                ),
    );
  }

  /// K-02 搜索框：高 48，圆角 12；输入即过滤，提交进搜索页。
  Widget _buildSearch() {
    final theme = Theme.of(context);
    return SizedBox(
      height: 48,
      child: TextField(
        controller: _searchController,
        onChanged: _onSearchChanged,
        onSubmitted: (_) => _openSearchPage(),
        decoration: InputDecoration(
          hintText: '搜索知识点',
          prefixIcon: const Icon(Icons.search),
          suffixIcon: _query.isEmpty
              ? null
              : IconButton(
                  icon: const Icon(Icons.clear),
                  onPressed: () {
                    _searchController.clear();
                    _onSearchChanged('');
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
    );
  }

  /// K-03 掌握进度：label 12“已掌握 x/y”+ 线性条。
  Widget _buildProgress() {
    final theme = Theme.of(context);
    final total = _totalPoints;
    final done = _masteredCount;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          '已掌握 $done/$total',
          style: theme.textTheme.labelMedium,
        ),
        const SizedBox(height: 4),
        LinearProgressIndicator(value: total == 0 ? 0 : done / total),
      ],
    );
  }

  /// K-04 章 header：高 56；左模块名，标题 16，右知识点计数；点按折叠整章。
  Widget _buildChapter(Chapter chapter) {
    final theme = Theme.of(context);
    final sections = _sections[chapter.id] ?? <Section>[];
    final collapsed = _collapsedChapters.contains(chapter.id);
    if (_searching) {
      final hasMatch =
          sections.any((s) => _visiblePoints(s.id).isNotEmpty);
      if (!hasMatch) return const SizedBox.shrink();
    }
    var pointCount = 0;
    for (final s in sections) {
      pointCount += _points[s.id]?.length ?? 0;
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        InkWell(
          onTap: () => setState(() {
            if (collapsed) {
              _collapsedChapters.remove(chapter.id);
            } else {
              _collapsedChapters.add(chapter.id);
            }
          }),
          child: SizedBox(
            height: 56,
            child: Row(
              children: [
                Text(
                  chapter.module,
                  style: theme.textTheme.labelMedium?.copyWith(
                    color: theme.colorScheme.primary,
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    chapter.title,
                    style: theme.textTheme.titleMedium,
                  ),
                ),
                Text(
                  '$pointCount 个知识点',
                  style: theme.textTheme.labelMedium?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
                const SizedBox(width: 4),
                Icon(collapsed ? Icons.expand_more : Icons.expand_less),
              ],
            ),
          ),
        ),
        if (!collapsed) ...sections.map((s) => _buildSection(chapter, s)),
      ],
    );
  }

  /// K-05 节 header：高 48；标题 15 `onSurfaceVariant`；点按折叠节。
  /// 搜索时命中节自动展开（忽略折叠态）。
  Widget _buildSection(Chapter chapter, Section section) {
    final theme = Theme.of(context);
    final points = _visiblePoints(section.id);
    final collapsed =
        _collapsedSections.contains(section.id) && !_searching;
    if (_searching && points.isEmpty) return const SizedBox.shrink();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        InkWell(
          onTap: () => setState(() {
            if (_collapsedSections.contains(section.id)) {
              _collapsedSections.remove(section.id);
            } else {
              _collapsedSections.add(section.id);
            }
          }),
          child: SizedBox(
            height: 48,
            child: Row(
              children: [
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    section.title,
                    style: theme.textTheme.titleMedium?.copyWith(
                      fontSize: 15,
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                ),
                Text(
                  '${points.length} 个',
                  style: theme.textTheme.labelMedium?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
                Icon(
                  collapsed ? Icons.expand_more : Icons.expand_less,
                  size: 20,
                ),
              ],
            ),
          ),
        ),
        if (!collapsed)
          ...points.map((p) => _buildPointRow(chapter, section, p)),
      ],
    );
  }

  /// K-06 知识点行：高 56；1px 分隔；标题 15；左掌握 icon（K-11）。
  /// K-07 倒三角：24dp，220ms 旋转 180°，semantics“展开/收起知识点”。
  Widget _buildPointRow(
    Chapter chapter,
    Section section,
    KnowledgePoint point,
  ) {
    final theme = Theme.of(context);
    final expanded = _expandedPoints.contains(point.id);
    final mastered = _mastered.contains(point.id);
    return Column(
      key: point.id == _firstMatchId ? _firstMatchKey : null,
      children: [
        InkWell(
          onTap: () => _togglePoint(point, section.id),
          child: SizedBox(
            height: 56,
            child: Row(
              children: [
                IconButton(
                  icon: Icon(
                    mastered
                        ? Icons.check_circle
                        : Icons.radio_button_unchecked,
                    color: mastered
                        ? theme.colorScheme.primary
                        : theme.colorScheme.onSurfaceVariant,
                  ),
                  tooltip: mastered ? '已掌握' : '标记已掌握',
                  onPressed: () => _toggleMastered(point.id),
                ),
                Expanded(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        point.title,
                        style: theme.textTheme.titleMedium?.copyWith(
                          fontSize: 15,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      Text(
                        '${point.code} · ${point.topic}',
                        style: theme.textTheme.labelSmall?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ),
                Semantics(
                  label: expanded ? '收起知识点' : '展开知识点',
                  child: AnimatedRotation(
                    turns: expanded ? 0.5 : 0,
                    duration: const Duration(milliseconds: 220),
                    child: const Icon(Icons.expand_more, size: 24),
                  ),
                ),
                const SizedBox(width: 16),
              ],
            ),
          ),
        ),
        const Divider(height: 1),
        if (expanded) _buildPanel(chapter, section, point),
      ],
    );
  }

  /// K-08 展开面板：背景 `surfaceVariant@50%`；内边距 16；摘要 2 行 + 要点 ≤3；
  /// K-10 练一练（左下）→ V2 按 `kp_id` 抽题；K-09 查看详情（右下）→ 详情页。
  Widget _buildPanel(
    Chapter chapter,
    Section section,
    KnowledgePoint point,
  ) {
    final theme = Theme.of(context);
    final keyPoints = (point.key_points ?? <String>[]).take(3).toList();
    return Container(
      width: double.infinity,
      color: theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.5),
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            point.summary,
            style: theme.textTheme.bodyMedium,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
          ),
          if (keyPoints.isNotEmpty) ...[
            const SizedBox(height: 8),
            ...keyPoints.map(
              (k) => Padding(
                padding: const EdgeInsets.only(bottom: 4),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('•  '),
                    Expanded(
                      child: Text(k, style: theme.textTheme.bodyMedium),
                    ),
                  ],
                ),
              ),
            ),
          ],
          const SizedBox(height: 8),
          Row(
            children: [
              TextButton(
                onPressed: () => Navigator.of(context).pushNamed(
                  AppRoutes.bankQuiz,
                  arguments: <String, Object?>{
                    'mode': 'practice',
                    'knowledgePointId': point.id,
                    'drawCount': 10,
                    'returnTo': 'knowledge',
                  },
                ),
                child: const Text('练一练'),
              ),
              const Spacer(),
              TextButton(
                onPressed: () => Navigator.of(context).pushNamed(
                  AppRoutes.knowledgePoint,
                  arguments: <String, Object?>{
                    'kpId': point.id,
                    'sectionId': section.id,
                    'chapterTitle': chapter.title,
                    'sectionTitle': section.title,
                    'returnTo': 'knowledge',
                  },
                ),
                child: const Text('查看详情'),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
