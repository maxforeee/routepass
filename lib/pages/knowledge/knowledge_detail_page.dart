import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/app_snackbar.dart';
import '../../core/service_locator.dart';
import '../../core/theme.dart';
import '../../models/knowledge_point.dart';
import '../../models/question.dart';
import '../../router/app_router.dart';

/// 知识详情页（第 3 章 §22.8）。
///
/// 入口参数（RouteSettings.arguments，`Map<String, Object?>`）：
/// kpId（String，必填）、sectionId（String?，同节关联/上一下一用）、
/// chapterTitle（String?，面包屑）、sectionTitle（String?，面包屑）、
/// returnTo（String?：'knowledge' | 'home' | 'quiz'，决定返回文案）。
/// D-08 图示：样例内容无图，本页不渲染。
class KnowledgeDetailPage extends StatefulWidget {
  const KnowledgeDetailPage({super.key, required this.args});

  final Map<String, Object?> args;

  @override
  State<KnowledgeDetailPage> createState() => _KnowledgeDetailPageState();
}

class _KnowledgeDetailPageState extends State<KnowledgeDetailPage> {
  /// 掌握态的本地 kv 键（派生键，与列表页同一键，见 T5a 任务书）。
  static const String _keyMasteredIds = 'kb.masteredIds';

  KnowledgePoint? _point;
  List<KnowledgePoint> _siblings = <KnowledgePoint>[];
  List<Question> _relatedQuestions = <Question>[];
  String _knowledgeVersion = '';
  bool _loading = true;
  bool _notFound = false;
  bool _mastered = false;

  String get _kpId => widget.args['kpId'] as String? ?? '';
  String? get _sectionId => widget.args['sectionId'] as String?;
  String? get _chapterTitle => widget.args['chapterTitle'] as String?;
  String? get _sectionTitle => widget.args['sectionTitle'] as String?;
  String get _returnTo => widget.args['returnTo'] as String? ?? 'knowledge';

  /// D-01 返回文案随来源。
  String get _backLabel {
    return switch (_returnTo) {
      'home' => '返回首页',
      'quiz' => '返回作答',
      'bank' => '返回作答',
      _ => '返回知识库',
    };
  }

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    KnowledgePoint? point;
    try {
      point = await ServiceLocator.knowledgeRepository.getPointDetail(_kpId);
    } catch (_) {
      point = null;
    }
    var siblings = <KnowledgePoint>[];
    if (point != null && _sectionId != null) {
      try {
        siblings = await ServiceLocator.knowledgeRepository
            .getPointsBySection(_sectionId!);
      } catch (_) {}
    }
    var related = <Question>[];
    if (point != null) {
      try {
        related =
            await ServiceLocator.questionRepository.drawQuestions(
          mode: 'practice',
          drawCount: 3,
          knowledgePointId: point.id,
        );
      } catch (_) {}
    }
    var version = '';
    try {
      final v = await ServiceLocator.contentService.getContentVersion();
      version = v.knowledge_version;
    } catch (_) {}
    var mastered = false;
    try {
      final raw = ServiceLocator.kvStore.getString(_keyMasteredIds);
      if (raw != null && raw.isNotEmpty) {
        final ids = (jsonDecode(raw) as List<dynamic>).cast<String>();
        mastered = ids.contains(_kpId);
      }
    } catch (_) {}
    if (!mounted) return;
    setState(() {
      _point = point;
      _siblings = siblings;
      _relatedQuestions = related;
      _knowledgeVersion = version;
      _mastered = mastered;
      _loading = false;
      _notFound = point == null;
    });
  }

  void _toggleMastered(bool value) {
    List<String> ids = <String>[];
    try {
      final raw = ServiceLocator.kvStore.getString(_keyMasteredIds);
      if (raw != null && raw.isNotEmpty) {
        ids = (jsonDecode(raw) as List<dynamic>).cast<String>();
      }
    } catch (_) {}
    if (value) {
      if (!ids.contains(_kpId)) ids.add(_kpId);
    } else {
      ids.remove(_kpId);
    }
    try {
      ServiceLocator.kvStore.setString(_keyMasteredIds, jsonEncode(ids));
    } catch (_) {}
    setState(() {
      _mastered = value;
    });
  }

  void _copyCommand(String cmd) {
    Clipboard.setData(ClipboardData(text: cmd));
    showAppSnackBar(context, '已复制');
  }

  /// D-12 上一/下一：栈里只留一个详情页（pushReplacementNamed）。
  void _openSibling(KnowledgePoint point) {
    Navigator.of(context).pushReplacementNamed(
      AppRoutes.knowledgePoint,
      arguments: <String, Object?>{
        'kpId': point.id,
        'sectionId': _sectionId,
        'chapterTitle': _chapterTitle,
        'sectionTitle': _sectionTitle,
        'returnTo': _returnTo,
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      );
    }
    if (_notFound || _point == null) {
      return Scaffold(
        body: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text('知识点不存在或已下线'),
              const SizedBox(height: 16),
              TextButton(
                onPressed: () => Navigator.of(context).pop(),
                child: const Text('返回'),
              ),
            ],
          ),
        ),
      );
    }
    final point = _point!;
    return Scaffold(
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _buildBackRow(),
              const SizedBox(height: 8),
              _buildBreadcrumb(point),
              const SizedBox(height: 12),
              _buildTitleMeta(point),
              const Divider(height: 24),
              _MarkdownBody(markdown: point.content_md),
              const SizedBox(height: 16),
              _buildCommands(point),
              _buildPitfalls(point),
              _buildRelatedPoints(point),
              _buildRelatedQuestions(),
              _buildPrevNext(point),
              const SizedBox(height: 12),
              SizedBox(
                width: double.infinity,
                height: 48,
                child: FilledButton(
                  onPressed: () => Navigator.of(context).pushNamed(
                    AppRoutes.bankQuiz,
                    arguments: <String, Object?>{
                      'mode': 'practice',
                      'knowledgePointId': point.id,
                      'drawCount': 10,
                      'returnTo': 'knowledge',
                    },
                  ),
                  child: const Text('练这个知识点'),
                ),
              ),
              const SizedBox(height: 16),
              Center(
                child: Text(
                  _knowledgeVersion.isEmpty
                      ? '本地样例内容'
                      : '内容版本 $_knowledgeVersion',
                  style: Theme.of(context).textTheme.labelSmall?.copyWith(
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                      ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// D-01 返回：icon 24 + 文案随来源。
  Widget _buildBackRow() {
    return Align(
      alignment: Alignment.centerLeft,
      child: TextButton.icon(
        onPressed: () => Navigator.of(context).pop(),
        icon: const Icon(Icons.arrow_back, size: 24),
        label: Text(_backLabel),
      ),
    );
  }

  /// D-02 面包屑：章 > 节 > 知识点；点章/节回知识库。
  Widget _buildBreadcrumb(KnowledgePoint point) {
    final theme = Theme.of(context);
    final style = theme.textTheme.labelMedium?.copyWith(
      color: theme.colorScheme.onSurfaceVariant,
    );
    return Row(
      children: [
        InkWell(
          onTap: () => Navigator.of(context).pop(),
          child: Text(_chapterTitle ?? '知识库', style: style),
        ),
        Text(' > ', style: style),
        InkWell(
          onTap: () => Navigator.of(context).pop(),
          child: Text(_sectionTitle ?? point.code, style: style),
        ),
        Text(' > ', style: style),
        Expanded(
          child: Text(
            point.title,
            style: style,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ),
      ],
    );
  }

  /// D-03 标题（title 22）+ D-04 元信息 + D-05 掌握切换。
  Widget _buildTitleMeta(KnowledgePoint point) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(point.title, style: theme.textTheme.titleLarge),
        const SizedBox(height: 8),
        Row(
          children: [
            Expanded(
              child: Text(
                _knowledgeVersion.isEmpty
                    ? '行版本 ${point.row_version}'
                    : '内容版本 $_knowledgeVersion · 行版本 ${point.row_version}',
                style: theme.textTheme.labelMedium?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ),
            const Text('已掌握'),
            Switch(
              value: _mastered,
              onChanged: _toggleMastered,
            ),
          ],
        ),
      ],
    );
  }

  /// D-07 命令表：等宽 13；长命令横向局部滚动；长按复制 + 复制按钮。
  Widget _buildCommands(KnowledgePoint point) {
    final theme = Theme.of(context);
    final commands = point.commands ?? <KnowledgeCommand>[];
    if (commands.isEmpty) return const SizedBox.shrink();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('常用命令', style: theme.textTheme.titleMedium),
        const SizedBox(height: 8),
        ...commands.map(
          (c) => Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Container(
              width: double.infinity,
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: theme.colorScheme.surfaceContainerHighest,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: GestureDetector(
                          onLongPress: () => _copyCommand(c.cmd),
                          child: SingleChildScrollView(
                            scrollDirection: Axis.horizontal,
                            child: Text(
                              c.cmd,
                              style: monoTextStyle(context, fontSize: 13),
                            ),
                          ),
                        ),
                      ),
                      IconButton(
                        icon: const Icon(Icons.copy, size: 20),
                        tooltip: '复制',
                        onPressed: () => _copyCommand(c.cmd),
                      ),
                    ],
                  ),
                  if (c.desc.isNotEmpty)
                    Text(
                      c.desc,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                ],
              ),
            ),
          ),
        ),
        const SizedBox(height: 8),
      ],
    );
  }

  /// D-09 易错点：`warningContainer` 卡。
  Widget _buildPitfalls(KnowledgePoint point) {
    final theme = Theme.of(context);
    final pitfalls = point.pitfalls ?? <String>[];
    if (pitfalls.isEmpty) return const SizedBox.shrink();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('易错点', style: theme.textTheme.titleMedium),
        const SizedBox(height: 8),
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: AppColors.warningContainer(context),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Column(
            children: pitfalls
                .map(
                  (p) => Padding(
                    padding: const EdgeInsets.only(bottom: 4),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Icon(Icons.warning_amber, size: 20),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            p,
                            style: theme.textTheme.bodyMedium,
                          ),
                        ),
                      ],
                    ),
                  ),
                )
                .toList(),
          ),
        ),
        const SizedBox(height: 16),
      ],
    );
  }

  /// D-10 关联知识点 chips：同节其他点；没有 sectionId 或无同节他点时隐藏。
  Widget _buildRelatedPoints(KnowledgePoint point) {
    final theme = Theme.of(context);
    final related =
        _siblings.where((p) => p.id != point.id).toList();
    if (_sectionId == null || related.isEmpty) {
      return const SizedBox.shrink();
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('关联知识点', style: theme.textTheme.titleMedium),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: related
              .map(
                (p) => ActionChip(
                  label: Text(p.title),
                  onPressed: () => Navigator.of(context).pushNamed(
                    AppRoutes.knowledgePoint,
                    arguments: <String, Object?>{
                      'kpId': p.id,
                      'sectionId': _sectionId,
                      'chapterTitle': _chapterTitle,
                      'sectionTitle': _sectionTitle,
                      'returnTo': _returnTo,
                    },
                  ),
                ),
              )
              .toList(),
        ),
        const SizedBox(height: 16),
      ],
    );
  }

  /// D-11 关联题目：≤3 项，每项高 56；点按单题作答；无关联时诚实空态。
  Widget _buildRelatedQuestions() {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('关联题目', style: theme.textTheme.titleMedium),
        const SizedBox(height: 8),
        if (_relatedQuestions.isEmpty)
          Text(
            '暂无关联题目',
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          )
        else
          ..._relatedQuestions.map(
            (q) => InkWell(
              onTap: () => Navigator.of(context).pushNamed(
                AppRoutes.bankQuiz,
                arguments: <String, Object?>{
                  'mode': 'single',
                  'questionId': q.id,
                  'returnTo': 'knowledge',
                },
              ),
              child: SizedBox(
                height: 56,
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        q.stem,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.bodyMedium,
                      ),
                    ),
                    const Icon(Icons.chevron_right),
                  ],
                ),
              ),
            ),
          ),
        const SizedBox(height: 16),
      ],
    );
  }

  /// D-12 上一/下一：同节切换；两端禁用；无 sectionId 时隐藏。
  Widget _buildPrevNext(KnowledgePoint point) {
    if (_sectionId == null) {
      return const SizedBox.shrink();
    }
    final index = _siblings.indexWhere((p) => p.id == point.id);
    final prev = index > 0 ? _siblings[index - 1] : null;
    final next =
        index >= 0 && index < _siblings.length - 1
            ? _siblings[index + 1]
            : null;
    return Row(
      children: [
        Expanded(
          child: SizedBox(
            height: 48,
            child: OutlinedButton(
              onPressed: prev == null ? null : () => _openSibling(prev),
              child: const Text('上一知识点'),
            ),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: SizedBox(
            height: 48,
            child: OutlinedButton(
              onPressed: next == null ? null : () => _openSibling(next),
              child: const Text('下一知识点'),
            ),
          ),
        ),
      ],
    );
  }
}

/// 正文最小 Markdown 渲染（不引新依赖）：`# ` 标题、`## ` 小标题、``` 代码块横向滚动、
/// `- ` 要点、空行分段、其余正文 15sp/行高 1.6。
class _MarkdownBody extends StatelessWidget {
  const _MarkdownBody({required this.markdown});

  final String markdown;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final bodyStyle = theme.textTheme.bodyMedium?.copyWith(
      fontSize: 15,
      height: 1.6,
    );
    final lines = markdown.split('\n');
    final widgets = <Widget>[];
    var i = 0;
    while (i < lines.length) {
      final line = lines[i];
      if (line.startsWith('# ')) {
        widgets.add(
          Text(line.substring(2).trim(), style: theme.textTheme.titleLarge),
        );
        widgets.add(const SizedBox(height: 8));
      } else if (line.startsWith('## ')) {
        widgets.add(
          Text(line.substring(3).trim(), style: theme.textTheme.titleMedium),
        );
        widgets.add(const SizedBox(height: 8));
      } else if (line.startsWith('```')) {
        final buf = <String>[];
        i++;
        while (i < lines.length && !lines[i].startsWith('```')) {
          buf.add(lines[i]);
          i++;
        }
        widgets.add(
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: theme.colorScheme.surfaceContainerHighest,
              borderRadius: BorderRadius.circular(12),
            ),
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Text(
                buf.join('\n'),
                style: monoTextStyle(context, fontSize: 13),
              ),
            ),
          ),
        );
        widgets.add(const SizedBox(height: 12));
      } else if (line.startsWith('- ') || line.startsWith('* ')) {
        widgets.add(
          Padding(
            padding: const EdgeInsets.only(bottom: 4),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('•  '),
                Expanded(
                  child: Text(line.substring(2), style: bodyStyle),
                ),
              ],
            ),
          ),
        );
      } else if (line.trim().isEmpty) {
        widgets.add(const SizedBox(height: 8));
      } else {
        widgets.add(Text(line, style: bodyStyle));
        widgets.add(const SizedBox(height: 8));
      }
      i++;
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: widgets,
    );
  }
}
