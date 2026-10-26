part of 'admin_pages.dart';

/// Edits a draft version (or creates a procedure when [version] is null).
class VersionEditor extends StatefulWidget {
  const VersionEditor({
    super.key,
    required this.admin,
    required this.version,
    this.actionId,
    this.onChanged,
  });
  final AdminRepository admin;
  final AdminVersion? version;
  final String? actionId;
  final VoidCallback? onChanged;
  @override
  State<VersionEditor> createState() => _VersionEditorState();
}

class _VersionEditorState extends State<VersionEditor> {
  /// Content fields per language: (key, Chinese label, English label, min lines).
  static const fields = {
    'zh': [
      ('title_zh', '標題', 'Title', 1),
      ('description_zh', '說明', 'Description', 3),
      ('applicable_to', '適用對象', 'Applies to', 2),
      ('location', '地點', 'Location', 1),
      ('documents_zh', '要帶的文件（每行一項）', 'What to bring (one per line)', 3),
    ],
    'en': [
      ('title_en', '標題', 'Title', 1),
      ('description_en', '說明', 'Description', 3),
      ('applicable_to_en', '適用對象', 'Applies to', 2),
      ('location_en', '地點', 'Location', 1),
      ('documents_en', '要帶的文件（每行一項）', 'What to bring (one per line)', 3),
    ],
  };
  late final Map<String, TextEditingController> _fields = {
    for (final f in [...fields['zh']!, ...fields['en']!])
      f.$1: TextEditingController(text: widget.version?.content[f.$1] ?? ''),
  };
  final _slug = TextEditingController();
  late final List<_StepFields> _steps = [
    for (final s in widget.version?.steps ?? const <AdminStep>[])
      _StepFields(s.titleZh, s.titleEn, s.notes ?? '', s.notesEn ?? ''),
  ];

  /// Which language's content is shown; starts with the interface language.
  String? _lang;

  @override
  void dispose() {
    for (final c in _fields.values) {
      c.dispose();
    }
    for (final s in _steps) {
      s.dispose();
    }
    _slug.dispose();
    super.dispose();
  }

  /// One document per line; a line missing in one language falls back to the other.
  List<Json> _documents() {
    List<String> lines(String key) => [
      for (final l in _fields[key]!.text.split('\n')) l.trim(),
    ];
    final zh = lines('documents_zh');
    final en = lines('documents_en');
    return [
      for (var i = 0; i < (zh.length > en.length ? zh.length : en.length); i++)
        if ((i < zh.length && zh[i].isNotEmpty) ||
            (i < en.length && en[i].isNotEmpty))
          {
            'zh': i < zh.length && zh[i].isNotEmpty ? zh[i] : en[i],
            'en': i < en.length ? en[i] : '',
          },
    ];
  }

  Json _content() => {
    for (final e in _fields.entries)
      if (!e.key.startsWith('documents'))
        e.key: e.key.startsWith('location') && e.value.text.trim().isEmpty
            ? null
            : e.value.text.trim(),
    'documents': _documents(),
    'steps': [
      for (final s in _steps)
        if (s.zh.text.trim().isNotEmpty || s.en.text.trim().isNotEmpty)
          {
            'title_zh': s.zh.text.trim().isEmpty
                ? s.en.text.trim()
                : s.zh.text.trim(),
            'title_en': s.en.text.trim().isEmpty
                ? s.zh.text.trim()
                : s.en.text.trim(),
            'notes': s.notes.text.trim().isEmpty ? null : s.notes.text.trim(),
            'notes_en': s.notesEn.text.trim().isEmpty
                ? null
                : s.notesEn.text.trim(),
          },
    ],
  };

  @override
  Widget build(BuildContext context) {
    final vm = BridgeScope.of(context);
    final creating = widget.version == null;
    final lang = _lang ??= vm.english ? 'en' : 'zh';
    return PaperCard(
      color: Palette.high,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          PaperHeading(
            creating
                ? vm.pair('新增流程', 'New procedure')
                : '${vm.t('draft')} v${widget.version!.number}',
          ),
          if (creating)
            LabeledField(
              label: vm.pair(
                '網址代稱（英文小寫與 -，例如 arc-extension）',
                'Slug (lowercase letters and -, e.g. arc-extension)',
              ),
              controller: _slug,
            ),
          Wrap(
            spacing: 8,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              Text(
                vm.pair('編輯語言', 'Editing'),
                style: const TextStyle(fontSize: 13, color: Palette.muted),
              ),
              for (final l in const ['zh', 'en'])
                ChoiceChip(
                  label: Text(l == 'zh' ? '中文' : 'English'),
                  selected: lang == l,
                  onSelected: (_) => setState(() => _lang = l),
                ),
            ],
          ),
          const SizedBox(height: 16),
          for (final f in fields[lang]!)
            LabeledField(
              key: ValueKey(f.$1),
              label: vm.pair(f.$2, f.$3),
              controller: _fields[f.$1]!,
              minLines: f.$4,
            ),
          const SizedBox(height: 8),
          PaperHeading(vm.t('stepPreview')),
          for (final (i, step) in _steps.indexed)
            Padding(
              key: ObjectKey(step),
              padding: const EdgeInsets.only(bottom: 12),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Padding(
                    padding: const EdgeInsets.only(top: 24, right: 12),
                    child: PaperTag('${i + 1}'),
                  ),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        LabeledField(
                          key: ValueKey('$lang-title'),
                          label: vm.pair('步驟標題', 'Step title'),
                          controller: lang == 'zh' ? step.zh : step.en,
                        ),
                        LabeledField(
                          key: ValueKey('$lang-notes'),
                          label: lang == 'zh'
                              ? vm.pair(
                                  '補充說明（文件、費用、期限）',
                                  'Notes (documents, fees, deadlines)',
                                )
                              : vm.pair(
                                  '英文補充說明（空白時顯示中文）',
                                  'English notes (Chinese shows if empty)',
                                ),
                          controller: lang == 'zh' ? step.notes : step.notesEn,
                          minLines: 2,
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    padding: const EdgeInsets.only(top: 20),
                    tooltip: vm.t('delete'),
                    icon: const Icon(Icons.remove_circle_outline),
                    onPressed: () => setState(() {
                      _steps.removeAt(i).dispose();
                    }),
                  ),
                ],
              ),
            ),
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton.icon(
              onPressed: () => setState(() => _steps.add(_StepFields())),
              icon: const Icon(Icons.add),
              label: Text(vm.pair('新增步驟', 'Add step')),
            ),
          ),
          Wrap(
            spacing: 12,
            runSpacing: 8,
            children: [
              FilledButton(
                onPressed: () => _guard(context, () async {
                  if (creating) {
                    final slug = _slug.text.trim();
                    await widget.admin.createAction(slug, _content());
                    // A procedure's id is its slug.
                    if (context.mounted) context.go('/admin/actions/$slug');
                  } else {
                    await widget.admin.saveDraft(
                      widget.version!.id,
                      _content(),
                    );
                    vm.showNotice(vm.pair('草稿已儲存。', 'Draft saved.'));
                    widget.onChanged?.call();
                  }
                }),
                child: Text(
                  creating
                      ? vm.pair('建立草稿', 'Create draft')
                      : vm.pair('儲存草稿', 'Save draft'),
                ),
              ),
              if (!creating)
                OutlinedButton(
                  onPressed: () => _guard(context, () async {
                    await widget.admin.saveDraft(
                      widget.version!.id,
                      _content(),
                    );
                    await widget.admin.publish(widget.version!.id);
                    vm.showNotice(
                      vm.pair(
                        '已發布；內容從此凍結。',
                        'Published; this version is now frozen.',
                      ),
                    );
                    widget.onChanged?.call();
                  }),
                  child: Text(vm.pair('儲存並發布', 'Save and publish')),
                ),
            ],
          ),
        ],
      ),
    );
  }
}

class _StepFields {
  _StepFields([
    String zh = '',
    String en = '',
    String notes = '',
    String notesEn = '',
  ]) : zh = TextEditingController(text: zh),
       en = TextEditingController(text: en),
       notes = TextEditingController(text: notes),
       notesEn = TextEditingController(text: notesEn);
  final TextEditingController zh, en, notes, notesEn;
  void dispose() {
    zh.dispose();
    en.dispose();
    notes.dispose();
    notesEn.dispose();
  }
}
