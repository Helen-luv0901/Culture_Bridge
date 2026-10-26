import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../data/api_client.dart';
import '../../data/admin_repository.dart';
import '../../domain/admin_models.dart';
import '../../domain/api_models.dart';
import '../core/design_system.dart';
import '../core/loading.dart';
import 'browse_pages.dart';

part 'admin_queues.dart';
part 'admin_tools.dart';
part 'admin_verification_panel.dart';
part 'admin_version_editor.dart';

/// Reviewer/admin console (C-14..C-16). Same paper look as the rest (C-17).
class AdminPage extends StatelessWidget {
  const AdminPage({super.key, required this.tab});
  final String tab;
  static const tabs = [
    'actions',
    'feedback',
    'reports',
    'documents',
    'stats',
    'accounts',
  ];

  @override
  Widget build(BuildContext context) {
    final vm = BridgeScope.of(context);
    if (!vm.isStaff) {
      return Text(vm.pair('只有審查者與管理者可以使用。', 'Reviewers and admins only.'));
    }
    final admin = vm.admin!;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Wrap(
          spacing: 12,
          runSpacing: 8,
          children: [
            for (final t in tabs)
              if (t != 'accounts' || vm.isAdmin)
                ChoiceChip(
                  label: Text(switch (t) {
                    'actions' => vm.pair('流程', 'Procedures'),
                    'feedback' => vm.pair('回報審查', 'Reports from students'),
                    'reports' => vm.pair('檢舉', 'Content reports'),
                    'accounts' => vm.pair('權限', 'Access'),
                    'stats' => vm.pair('數據', 'Numbers'),
                    _ => vm.pair('官方文件', 'Official documents'),
                  }),
                  selected: tab == t,
                  onSelected: (_) => context.go('/admin?tab=$t'),
                ),
          ],
        ),
        const SizedBox(height: 24),
        switch (tab) {
          'feedback' => _FeedbackQueue(admin: admin),
          'reports' => _ReportQueue(admin: admin),
          'documents' => _Documents(admin: admin),
          'accounts' when vm.isAdmin => _Accounts(admin: admin),
          'stats' => _Stats(admin: admin),
          _ => _ActionList(admin: admin),
        },
      ],
    );
  }
}

/// Loads with a future and offers retry; simpler than view-model resources for staff screens.
class _Loaded<T> extends StatefulWidget {
  const _Loaded({super.key, required this.load, required this.builder});
  final Future<T> Function() load;
  final Widget Function(BuildContext context, T data, VoidCallback reload)
  builder;
  @override
  State<_Loaded<T>> createState() => _LoadedState<T>();
}

class _LoadedState<T> extends State<_Loaded<T>> {
  late Future<T> _future = widget.load();
  void _reload() => setState(() => _future = widget.load());
  @override
  Widget build(BuildContext context) => FutureBuilder<T>(
    future: _future,
    builder: (context, snapshot) {
      if (snapshot.hasError) {
        return ErrorPanel(
          message: BridgeScope.of(context).errorText(snapshot.error),
          onRetry: _reload,
        );
      }
      if (!snapshot.hasData) return const LoadingNote();
      return widget.builder(context, snapshot.data as T, _reload);
    },
  );
}

Future<void> _guard(
  BuildContext context,
  Future<void> Function() action,
) async {
  final vm = BridgeScope.of(context);
  try {
    await action();
  } on ApiException catch (e) {
    vm.showNotice(e.message ?? '${vm.errorText(e)} (${e.code})');
  }
}

/// Title, subtitle and an action button underneath, aligned right. A ListTile trailing button
/// squeezes the text to nothing on phones with large text (C-17).
class _ListRow extends StatelessWidget {
  const _ListRow({required this.title, required this.subtitle, this.action});
  final Widget title;
  final Widget subtitle;
  final Widget? action;
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 8),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        DefaultTextStyle.merge(
          style: const TextStyle(fontSize: 16),
          child: title,
        ),
        const SizedBox(height: 2),
        DefaultTextStyle.merge(
          style: const TextStyle(fontSize: 14, color: Palette.muted),
          child: subtitle,
        ),
        if (action != null)
          Align(alignment: Alignment.centerRight, child: action),
      ],
    ),
  );
}

// ---------- procedures ----------

class _ActionList extends StatelessWidget {
  const _ActionList({required this.admin});
  final AdminRepository admin;
  @override
  Widget build(BuildContext context) {
    final vm = BridgeScope.of(context);
    return _Loaded<List<AdminActionItem>>(
      load: admin.actions,
      builder: (context, items, _) => Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Align(
            alignment: Alignment.centerLeft,
            child: FilledButton.icon(
              onPressed: () => context.push('/admin/actions/new'),
              icon: const Icon(Icons.add),
              label: Text(vm.pair('新增流程', 'New procedure')),
            ),
          ),
          const SizedBox(height: 16),
          for (final item in items)
            Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: PaperCard(
                padding: const EdgeInsets.all(8),
                // The status tag sits above the title: as a ListTile leading it took the whole
                // row with long English labels and large text.
                child: ListTile(
                  title: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      StatusTag(item.status),
                      const SizedBox(height: 6),
                      Text(item.title.of(vm.english)),
                    ],
                  ),
                  subtitle: Text(
                    [
                      'v${item.latestVersion}',
                      if (item.latestPublished != null)
                        '${vm.t('published')} v${item.latestPublished}',
                      if (item.hasDraft) vm.t('draft'),
                      if (item.archived) vm.pair('已封存', 'Archived'),
                    ].join(' · '),
                  ),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () => context.push('/admin/actions/${item.id}'),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class AdminActionPage extends StatelessWidget {
  const AdminActionPage({super.key, required this.id});
  final String id;
  @override
  Widget build(BuildContext context) {
    final vm = BridgeScope.of(context);
    if (!vm.isStaff || vm.admin == null) return const MissingContent();
    final admin = vm.admin!;
    if (id == 'new') return VersionEditor(admin: admin, version: null);
    return _Loaded<List<AdminVersion>>(
      key: ValueKey(id),
      load: () => admin.versions(id),
      builder: (context, versions, reload) {
        final latest = versions.first;
        return FlowBody(
          maxWidth: 900,
          children: [
            Text(
              Text2(
                latest.content['title_zh'] ?? '',
                latest.content['title_en'] ?? '',
              ).of(vm.english),
              style: displayStyle(25),
            ),
            if (latest.isDraft)
              VersionEditor(
                admin: admin,
                version: latest,
                actionId: id,
                onChanged: reload,
              )
            else
              Align(
                alignment: Alignment.centerLeft,
                child: FilledButton.icon(
                  icon: const Icon(Icons.edit_note),
                  label: Text(
                    vm.pair('建立新版本來修改', 'Create a new version to edit'),
                  ),
                  onPressed: () => _guard(context, () async {
                    await admin.newVersion(id);
                    reload();
                  }),
                ),
              ),
            _VerificationPanel(
              admin: admin,
              version: latest,
              onChanged: reload,
            ),
            PaperHeading(vm.pair('版本紀錄', 'Version history')),
            for (final v in versions)
              Text(
                'v${v.number} · ${v.isDraft ? vm.t('draft') : '${vm.t('published')} ${formatDate(v.publishedAt)}'}'
                ' · ${vm.t(_statusKey(v.status))} · ${v.steps.length} ${vm.pair('步驟', 'steps')}',
              ),
            TextButton(
              onPressed: () => _guard(context, () async {
                await admin.archive(id, true);
                if (context.mounted) context.go('/admin');
              }),
              child: Text(vm.pair('封存這個流程', 'Archive this procedure')),
            ),
          ],
        );
      },
    );
  }
}

String _statusKey(String status) => switch (status) {
  'needs_review' => 'needsReview',
  'community_supported' => 'communitySupported',
  _ => status,
};
