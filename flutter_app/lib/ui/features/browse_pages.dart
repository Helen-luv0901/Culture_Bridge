import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../domain/keys.dart';
import '../core/design_system.dart';
import '../core/loading.dart';

export '../core/loading.dart' show MissingContent;

/// Verification status of an official guide (used by the admin console).
class StatusTag extends StatelessWidget {
  const StatusTag(this.status, {super.key});
  final String status;
  @override
  Widget build(BuildContext context) => PaperTag(
    BridgeScope.of(context).t(statusKey(status)),
    color: switch (status) {
      'verified' => Palette.paleMoss,
      'needs_review' || 'outdated' => Palette.ochre,
      _ => Palette.oat,
    },
  );
}

/// Report or block from a student post (B-18, B-19; Google Play UGC policy).
class ModerationMenu extends StatelessWidget {
  const ModerationMenu({super.key, required this.experienceId});
  final String experienceId;
  @override
  Widget build(BuildContext context) {
    final vm = BridgeScope.of(context);
    return PopupMenuButton<String>(
      key: const Key('moderation-menu'),
      tooltip: vm.pair('檢舉或封鎖', 'Report or block'),
      icon: const AppIcon('more', color: Palette.muted),
      color: Palette.high,
      onSelected: (choice) async {
        if (!ensureSignedIn(context)) return;
        if (choice == 'report') {
          await showReportDialog(
            context,
            (reason, note) => vm.report(experienceId, reason, note),
          );
        } else {
          final ok = await confirmDialog(
            context,
            vm.t('blockAuthor'),
            vm.t('blockConfirm'),
          );
          if (ok && await vm.blockAuthor(experienceId) && context.mounted) {
            context.go('/explore');
          }
        }
      },
      itemBuilder: (_) => [
        PopupMenuItem(value: 'report', child: Text(vm.t('report'))),
        PopupMenuItem(value: 'block', child: Text(vm.t('blockAuthor'))),
      ],
    );
  }
}

/// Asks for a reason, then sends the report with [send] (a post or a comment).
Future<void> showReportDialog(
  BuildContext context,
  Future<bool> Function(String reason, String? note) send,
) {
  final vm = BridgeScope.of(context);
  return showDialog<void>(
    context: context,
    builder: (_) => BridgeScope(
      viewModel: vm,
      child: ReportDialog(send: send),
    ),
  );
}

class ReportDialog extends StatefulWidget {
  const ReportDialog({super.key, required this.send});
  final Future<bool> Function(String reason, String? note) send;
  @override
  State<ReportDialog> createState() => _ReportDialogState();
}

class _ReportDialogState extends State<ReportDialog> {
  String? _reason;
  final _note = TextEditingController();
  static const reasons = {
    'spam': ('垃圾訊息或廣告', 'Spam or advertising'),
    'harassment': ('騷擾或霸凌', 'Harassment or bullying'),
    'hate': ('仇恨或歧視', 'Hate or discrimination'),
    'sexual': ('色情內容', 'Sexual content'),
    'personal_info': ('洩漏個人資料', 'Personal information'),
    'misinformation': ('錯誤或誤導的資訊', 'False or misleading information'),
    'other': ('其他', 'Other'),
  };

  @override
  void dispose() {
    _note.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final vm = BridgeScope.of(context);
    return AlertDialog(
      title: Text(vm.t('reportTitle'), style: displayStyle(18)),
      content: SingleChildScrollView(
        child: RadioGroup<String>(
          groupValue: _reason,
          onChanged: (value) => setState(() => _reason = value),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              for (final entry in reasons.entries)
                RadioListTile<String>(
                  value: entry.key,
                  activeColor: Palette.moss,
                  title: Text(vm.pair(entry.value.$1, entry.value.$2)),
                ),
              TextField(
                controller: _note,
                maxLength: 1000,
                decoration: InputDecoration(labelText: vm.t('tellMore')),
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: Text(vm.t('cancel')),
        ),
        FilledButton(
          onPressed: _reason == null
              ? null
              : () async {
                  await widget.send(_reason!, _note.text);
                  if (context.mounted) Navigator.pop(context);
                },
          child: Text(vm.t('send')),
        ),
      ],
    );
  }
}

Future<bool> confirmDialog(
  BuildContext context,
  String title,
  String body, {
  String? confirm,
  bool danger = false,
}) async {
  final vm = BridgeScope.of(context);
  return await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: Text(title, style: displayStyle(18)),
          content: Text(body),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: Text(vm.t('cancel')),
            ),
            FilledButton(
              style: danger
                  ? FilledButton.styleFrom(backgroundColor: Palette.danger)
                  : null,
              onPressed: () => Navigator.pop(context, true),
              child: Text(confirm ?? vm.t('confirm')),
            ),
          ],
        ),
      ) ??
      false;
}
