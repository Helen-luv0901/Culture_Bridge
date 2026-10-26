part of 'admin_pages.dart';

/// Sources and verification for the newest version. "Verified" needs a source and a reviewer.
class _VerificationPanel extends StatefulWidget {
  const _VerificationPanel({
    required this.admin,
    required this.version,
    required this.onChanged,
  });
  final AdminRepository admin;
  final AdminVersion version;
  final VoidCallback onChanged;
  @override
  State<_VerificationPanel> createState() => _VerificationPanelState();
}

class _VerificationPanelState extends State<_VerificationPanel> {
  String? _source;
  String _decision = 'verified';
  final _note = TextEditingController();
  final _newTitle = TextEditingController();
  final _newUrl = TextEditingController();
  final _newPublisher = TextEditingController();
  final _evidence = TextEditingController();

  @override
  void dispose() {
    for (final c in [_note, _newTitle, _newUrl, _newPublisher, _evidence]) {
      c.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final vm = BridgeScope.of(context);
    final v = widget.version;
    return PaperCard(
      color: Palette.oat,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          PaperHeading(vm.t('sources'), badge: vm.t(_statusKey(v.status))),
          for (final s in v.sources)
            ListTile(
              contentPadding: EdgeInsets.zero,
              title: Text(s.title),
              subtitle: Text(
                '${s.publisher} · ${s.url}\n${s.evidenceNote ?? ''}',
              ),
            ),
          if (v.isDraft) ...[
            Text(vm.pair('新增來源（發布前）', 'Add a source (before publishing)')),
            LabeledField(
              controller: _newTitle,
              label: vm.pair('文件名稱', 'Document title'),
            ),
            LabeledField(controller: _newUrl, label: 'URL'),
            LabeledField(
              controller: _newPublisher,
              label: vm.pair('發布單位', 'Publisher'),
            ),
            LabeledField(
              controller: _evidence,
              label: vm.pair('這份來源證明了什麼', 'What this source supports'),
            ),
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton(
                onPressed: () => _guard(context, () async {
                  final source = await widget.admin.createSource({
                    'title': _newTitle.text.trim(),
                    'url': _newUrl.text.trim(),
                    'publisher': _newPublisher.text.trim(),
                    'kind': 'official',
                    'accessed_at': DateTime.now().toUtc().toIso8601String(),
                  });
                  await widget.admin.attachSource(
                    v.id,
                    source.id,
                    _evidence.text.trim(),
                  );
                  widget.onChanged();
                }),
                child: Text(vm.pair('加入來源', 'Attach source')),
              ),
            ),
          ],
          if (!v.isDraft && v.sources.isNotEmpty) ...[
            const Divider(color: Palette.edge),
            Text(
              vm.pair(
                '審查紀錄（依來源核對後填寫）',
                'Review (after checking against a source)',
              ),
            ),
            DropdownButton<String>(
              value: _source,
              hint: Text(vm.t('sources')),
              isExpanded: true,
              items: [
                for (final s in v.sources)
                  DropdownMenuItem(value: s.id, child: Text(s.title)),
              ],
              onChanged: (value) => setState(() => _source = value),
            ),
            DropdownButton<String>(
              value: _decision,
              isExpanded: true,
              items: [
                for (final d in ['verified', 'needs_review', 'outdated'])
                  DropdownMenuItem(value: d, child: Text(vm.t(_statusKey(d)))),
              ],
              onChanged: (value) => setState(() => _decision = value!),
            ),
            LabeledField(
              controller: _note,
              label: vm.pair('審查說明', 'Review note'),
            ),
            Align(
              alignment: Alignment.centerLeft,
              child: FilledButton(
                onPressed: _source == null
                    ? null
                    : () => _guard(context, () async {
                        await widget.admin.verify(
                          v.id,
                          _source!,
                          _decision,
                          _note.text.trim(),
                        );
                        widget.onChanged();
                      }),
                child: Text(vm.pair('記錄審查', 'Record review')),
              ),
            ),
          ],
          for (final r in v.verifications)
            Text(
              '${formatDate(r.checkedAt)} · ${vm.t(_statusKey(r.decision))} · ${r.note}',
              style: const TextStyle(fontSize: 13, color: Palette.muted),
            ),
          Wrap(
            spacing: 8,
            children: [
              for (final s in ['community_supported', 'unverified'])
                TextButton(
                  onPressed: () => _guard(context, () async {
                    await widget.admin.setStatus(v.id, s);
                    widget.onChanged();
                  }),
                  child: Text(
                    '${vm.pair('標為', 'Mark')} ${vm.t(_statusKey(s))}',
                  ),
                ),
            ],
          ),
        ],
      ),
    );
  }
}
