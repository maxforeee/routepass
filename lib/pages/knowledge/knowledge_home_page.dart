import 'dart:convert';

import 'package:flutter/material.dart';

import '../../core/kv_store.dart';
import '../../core/service_locator.dart';
import '../../core/theme.dart';
import '../../models/knowledge_point.dart';
import '../../router/app_router.dart';
import '../../widgets/page_header.dart';

/// 知识库页（R7：按 06_knowledge mockup 重排：页头 + 搜索 + 章卡片 + 节 + 知识点行）。
///
/// K-01 页头；K-02 搜索（输入即过滤，提交进搜索页）；K-03 掌握进度（每知识点行右侧
/// “已掌握 x/y”）；K-04 章卡片（右缘三角 220ms 旋转，点按折叠整章）；K-05 节 header；
/// K-06 知识点行；K-07 倒三角（220ms 旋转）；K-08 展开面板；K-09 查看详情；
/// K-10 练一练；K-11 掌握 icon；K-13 空态。K-12 版本条由 AppShell 全局显示，不在本页重复。
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
        chapterSections = await ServiceLocator.knowledgeRepository.getSections(
          chapter.id,
        );
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

  /// 搜索时命中至少一个知识点的章（未搜索时返回全部章）。
  List<Chapter> _visibleChapters() {
    if (!_searching) return _chapters;
    return _chapters.where((chapter) {
      final sections = _sections[chapter.id] ?? <Section>[];
      return sections.any((s) => _visiblePoints(s.id).isNotEmpty);
    }).toList();
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
      backgroundColor: AppColors.pageBackground(context),
      body: SafeArea(
        child: _loading
            ? const Center(child: CircularProgressIndicator())
            : _chapters.isEmpty
            ? const Center(child: Text('暂无知识点，请更新'))
            : ListView(
                padding: const EdgeInsets.fromLTRB(
                  AppSpacing.md,
                  AppSpacing.sm,
                  AppSpacing.md,
                  AppSpacing.md,
                ),
                children: [
                  const PageHeader(
                    title: '知识库',
                    subtitle: 'H3CNE 考点 · 章 / 节 / 知识点',
                  ),
                  const SizedBox(height: AppSpacing.md),
                  _buildSearch(),
                  const SizedBox(height: AppSpacing.md),
                  if (_searching && _visibleTotal == 0)
                    const Padding(
                      padding: EdgeInsets.only(top: AppSizes.emptyStateTop),
                      child: Center(child: Text('没有找到相关知识点')),
                    )
                  else
                    ..._buildChapterList(),
                ],
              ),
      ),
    );
  }

  List<Widget> _buildChapterList() {
    final chapters = _visibleChapters();
    final widgets = <Widget>[];
    for (var i = 0; i < chapters.length; i++) {
      widgets.add(_buildChapter(chapters[i]));
      if (i < chapters.length - 1) {
        widgets.add(const SizedBox(height: AppSpacing.chapterGap));
      }
    }
    return widgets;
  }

  /// K-02 搜索框：高 44，圆角 22；输入即过滤，提交进搜索页。
  Widget _buildSearch() {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return SizedBox(
      height: AppSizes.searchBarHeight,
      child: TextField(
        controller: _searchController,
        onChanged: _onSearchChanged,
        onSubmitted: (_) => _openSearchPage(),
        decoration: InputDecoration(
          hintText: '搜索知识点、命令…',
          hintStyle: theme.textTheme.labelLarge?.copyWith(
            color: scheme.onSurfaceVariant,
          ),
          prefixIcon: Icon(
            Icons.search,
            size: AppSizes.icon,
            color: scheme.onSurfaceVariant,
          ),
          prefixIconConstraints: const BoxConstraints(
            minWidth: AppSizes.searchBarHeight,
            minHeight: AppSizes.searchBarHeight,
          ),
          suffixIcon: _query.isEmpty
              ? null
              : IconButton(
                  icon: const Icon(Icons.clear, size: AppSizes.icon),
                  onPressed: () {
                    _searchController.clear();
                    _onSearchChanged('');
                  },
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(
                    minWidth: AppSizes.searchBarHeight,
                    minHeight: AppSizes.searchBarHeight,
                  ),
                ),
          isDense: true,
          filled: true,
          fillColor: scheme.surfaceContainerHighest,
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(AppRadii.search),
            borderSide: BorderSide.none,
          ),
          contentPadding: const EdgeInsets.symmetric(horizontal: AppSpacing.md),
        ),
      ),
    );
  }

  /// K-04 章卡片：白底圆角 14 浅灰描边；标题 15 粗体 + 右缘三角（220ms 旋转）。
  Widget _buildChapter(Chapter chapter) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final sections = _sections[chapter.id] ?? <Section>[];
    final collapsed = _collapsedChapters.contains(chapter.id);
    return Container(
      decoration: BoxDecoration(
        color: scheme.surface,
        borderRadius: BorderRadius.circular(AppRadii.chapterCard),
        border: Border.all(color: scheme.outlineVariant),
      ),
      child: Column(
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
            borderRadius: BorderRadius.circular(AppRadii.chapterCard),
            child: SizedBox(
              height: AppSizes.chapterCardHeight,
              child: Row(
                children: [
                  const SizedBox(width: AppSpacing.md),
                  Expanded(
                    child: Text(
                      chapter.title,
                      style: theme.textTheme.bodyMedium?.copyWith(
                        fontSize: AppFontSizes.entryTitle,
                        fontWeight: FontWeight.bold,
                        color: scheme.onSurface,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  Semantics(
                    label: collapsed ? '展开章节' : '收起章节',
                    child: AnimatedRotation(
                      turns: collapsed ? 0 : 0.25,
                      duration: const Duration(milliseconds: 220),
                      child: Icon(
                        Icons.chevron_right,
                        color: scheme.onSurfaceVariant,
                      ),
                    ),
                  ),
                  const SizedBox(width: AppSpacing.md),
                ],
              ),
            ),
          ),
          if (!collapsed) ...[
            ...sections.map((s) => _buildSection(chapter, s)),
            const SizedBox(height: AppSpacing.sm),
          ],
        ],
      ),
    );
  }

  /// K-05 节 header：标题 14 粗体，缩进；点按折叠节。搜索时命中节自动展开。
  Widget _buildSection(Chapter chapter, Section section) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final points = _visiblePoints(section.id);
    final collapsed = _collapsedSections.contains(section.id) && !_searching;
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
          child: Padding(
            padding: const EdgeInsets.fromLTRB(
              AppSpacing.md,
              AppSpacing.xs,
              AppSpacing.md,
              AppSpacing.xs,
            ),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    section.title,
                    style: theme.textTheme.labelLarge?.copyWith(
                      fontWeight: FontWeight.bold,
                      color: scheme.onSurface,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                Icon(
                  collapsed ? Icons.expand_more : Icons.expand_less,
                  size: AppSizes.icon,
                  color: scheme.onSurfaceVariant,
                ),
              ],
            ),
          ),
        ),
        if (!collapsed) ..._buildPointList(chapter, section),
      ],
    );
  }

  List<Widget> _buildPointList(Chapter chapter, Section section) {
    final points = _visiblePoints(section.id);
    final widgets = <Widget>[];
    for (var i = 0; i < points.length; i++) {
      widgets.add(_buildPointRow(chapter, section, points[i]));
      if (i < points.length - 1) {
        widgets.add(const SizedBox(height: AppSpacing.chapterGap));
      }
    }
    return widgets;
  }

  /// K-06 知识点行：高 44，圆角 12，浅灰描边；标题 13 + 右侧“已掌握 x/y”（K-03）
  /// + 掌握 icon（K-11）。K-07 倒三角：24dp，220ms 旋转 180°。
  Widget _buildPointRow(
    Chapter chapter,
    Section section,
    KnowledgePoint point,
  ) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final expanded = _expandedPoints.contains(point.id);
    final mastered = _mastered.contains(point.id);
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md),
      child: Column(
        key: point.id == _firstMatchId ? _firstMatchKey : null,
        children: [
          Container(
            decoration: BoxDecoration(
              color: AppColors.pageBackground(context),
              borderRadius: BorderRadius.circular(AppRadii.pointRow),
              border: Border.all(color: scheme.outlineVariant),
            ),
            child: InkWell(
              onTap: () => _togglePoint(point, section.id),
              borderRadius: BorderRadius.circular(AppRadii.pointRow),
              child: SizedBox(
                height: AppSizes.pointRowHeight,
                child: Row(
                  children: [
                    Semantics(
                      label: mastered ? '已掌握' : '标记已掌握',
                      button: true,
                      child: SizedBox(
                        width: AppSizes.pointRowHeight,
                        height: AppSizes.pointRowHeight,
                        child: InkWell(
                          onTap: () => _toggleMastered(point.id),
                          borderRadius: BorderRadius.circular(
                            AppRadii.pointRow,
                          ),
                          child: Icon(
                            mastered
                                ? Icons.check_circle
                                : Icons.radio_button_unchecked,
                            size: AppSizes.icon,
                            color: mastered
                                ? scheme.primary
                                : scheme.onSurfaceVariant,
                          ),
                        ),
                      ),
                    ),
                    Expanded(
                      child: Text(
                        point.title,
                        style: theme.textTheme.bodyMedium?.copyWith(
                          fontSize: AppFontSizes.pageSubtitle,
                          color: scheme.onSurface,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    Text(
                      '已掌握 ${mastered ? 1 : 0}/1',
                      style: theme.textTheme.labelMedium?.copyWith(
                        color: scheme.onSurfaceVariant,
                      ),
                    ),
                    Semantics(
                      label: expanded ? '收起知识点' : '展开知识点',
                      child: AnimatedRotation(
                        turns: expanded ? 0.5 : 0,
                        duration: const Duration(milliseconds: 220),
                        child: Icon(
                          Icons.expand_more,
                          size: AppSizes.iconLarge,
                        ),
                      ),
                    ),
                    const SizedBox(width: AppSpacing.xs),
                  ],
                ),
              ),
            ),
          ),
          if (expanded) _buildPanel(chapter, section, point),
        ],
      ),
    );
  }

  /// K-08 展开面板：背景 `surfaceVariant@50%`；内边距 16；摘要 2 行 + 要点 ≤3；
  /// K-10 练一练（左下）→ V2 按 `kp_id` 抽题；K-09 查看详情（右下）→ 详情页。
  Widget _buildPanel(Chapter chapter, Section section, KnowledgePoint point) {
    final theme = Theme.of(context);
    final keyPoints = (point.key_points ?? <String>[]).take(3).toList();
    return Container(
      width: double.infinity,
      color: theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.5),
      padding: const EdgeInsets.all(AppSpacing.md),
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
            const SizedBox(height: AppSpacing.xs),
            ...keyPoints.map(
              (k) => Padding(
                padding: const EdgeInsets.only(bottom: AppSpacing.xxs),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('•  '),
                    Expanded(child: Text(k, style: theme.textTheme.bodyMedium)),
                  ],
                ),
              ),
            ),
          ],
          const SizedBox(height: AppSpacing.xs),
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
