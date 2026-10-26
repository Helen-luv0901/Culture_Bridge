part of 'admin_pages.dart';

class _Documents extends StatefulWidget {
  const _Documents({required this.admin});
  final AdminRepository admin;
  @override
  State<_Documents> createState() => _DocumentsState();
}

class _DocumentsState extends State<_Documents> {
  final _title = TextEditingController();
  final _url = TextEditingController();
  final _publisher = TextEditingController();
  final _action = TextEditingController();
  final _text = TextEditingController();
  int _version = 0;

  @override
  void dispose() {
    for (final c in [_title, _url, _publisher, _action, _text]) {
      c.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final vm = BridgeScope.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          vm.pair(
            '貼上官方文件全文，助理就能依段落引用。過時的文件請停用。',
            'Paste the full text of an official document so the assistant can cite it. Retire outdated ones.',
          ),
        ),
        LabeledField(controller: _title, label: vm.pair('文件名稱', 'Title')),
        LabeledField(controller: _url, label: 'URL'),
        LabeledField(
          controller: _publisher,
          label: vm.pair('發布單位', 'Publisher'),
        ),
        TextField(
          controller: _action,
          decoration: InputDecoration(
            labelText: vm.pair(
              '相關流程 id（選填）',
              'Related procedure id (optional)',
            ),
          ),
        ),
        LabeledField(
          controller: _text,
          label: vm.pair('全文', 'Full text'),
          minLines: 6,
        ),
        Align(
          alignment: Alignment.centerLeft,
          child: FilledButton(
            onPressed: () => _guard(context, () async {
              await widget.admin.addDocument({
                'title': _title.text.trim(),
                'url': _url.text.trim(),
                'publisher': _publisher.text.trim(),
                if (_action.text.trim().isNotEmpty)
                  'action_id': _action.text.trim(),
                'text': _text.text,
              });
              _text.clear();
              setState(() => _version++);
            }),
            child: Text(vm.pair('加入文件', 'Add document')),
          ),
        ),
        const SizedBox(height: 16),
        _Loaded<List<KbDocument>>(
          key: ValueKey(_version),
          load: widget.admin.documents,
          builder: (context, docs, reload) => Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              for (final d in docs)
                _ListRow(
                  title: Text(d.title),
                  subtitle: Text(
                    '${d.publisher} · ${d.chunks} ${vm.pair('段', 'passages')}',
                  ),
                  action: TextButton(
                    onPressed: () => _guard(context, () async {
                      await widget.admin.setDocumentActive(d.id, !d.active);
                      reload();
                    }),
                    child: Text(
                      d.active
                          ? vm.pair('停用', 'Retire')
                          : vm.pair('恢復', 'Restore'),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ],
    );
  }
}

// ---------- access (admin only) ----------

class _Accounts extends StatefulWidget {
  const _Accounts({required this.admin});
  final AdminRepository admin;
  @override
  State<_Accounts> createState() => _AccountsState();
}

class _AccountsState extends State<_Accounts> {
  final _id = TextEditingController();
  String _role = 'reviewer';
  int _version = 0;

  @override
  void dispose() {
    _id.dispose();
    super.dispose();
  }

  String _roleName(String role) {
    final vm = BridgeScope.of(context);
    return switch (role) {
      'admin' => vm.pair('管理者', 'Admin'),
      'reviewer' => vm.pair('審查者', 'Reviewer'),
      _ => vm.pair('學生', 'Student'),
    };
  }

  Future<void> _set(String id, String role) => _guard(context, () async {
    await widget.admin.setRole(id, role);
    setState(() => _version++);
  });

  @override
  Widget build(BuildContext context) {
    final vm = BridgeScope.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          vm.pair(
            '請組員登入後到「我的」→「帳號」複製帳號編號給你，再在這裡設定角色。',
            'Ask the teammate to sign in and copy their account ID from Me → Account, then set a role here.',
          ),
        ),
        LabeledField(controller: _id, label: vm.pair('帳號編號', 'Account ID')),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            for (final role in ['reviewer', 'admin', 'student'])
              ChoiceChip(
                label: Text(_roleName(role)),
                selected: _role == role,
                onSelected: (_) => setState(() => _role = role),
              ),
            FilledButton(
              onPressed: () {
                final id = _id.text.trim();
                if (id.isEmpty) return;
                _set(id, _role).then((_) => _id.clear());
              },
              child: Text(vm.pair('設定角色', 'Set role')),
            ),
          ],
        ),
        const SizedBox(height: 16),
        _Loaded<List<StaffMember>>(
          key: ValueKey(_version),
          load: widget.admin.staff,
          builder: (context, staff, _) => Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              for (final m in staff)
                _ListRow(
                  title: SelectableText(m.id),
                  subtitle: Text(_roleName(m.role)),
                  action: m.id == vm.profile?.id
                      ? Text(vm.pair('（你）', '(you)'))
                      : TextButton(
                          onPressed: () => _set(m.id, 'student'),
                          child: Text(vm.pair('移除權限', 'Remove access')),
                        ),
                ),
            ],
          ),
        ),
      ],
    );
  }
}

// ---------- numbers (D-19) ----------

class _Stats extends StatefulWidget {
  const _Stats({required this.admin});
  final AdminRepository admin;
  @override
  State<_Stats> createState() => _StatsState();
}

class _StatsState extends State<_Stats> {
  int _days = 30;

  @override
  Widget build(BuildContext context) {
    final vm = BridgeScope.of(context);
    String pct(double? r) => r == null
        ? vm.pair('樣本不足', 'Not enough data')
        : '${(r * 100).round()}%';
    Widget row(String label, String value) => Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(child: Text(label)),
          const SizedBox(width: 12),
          Flexible(
            child: Text(
              value,
              textAlign: TextAlign.end,
              style: const TextStyle(fontWeight: FontWeight.w600),
            ),
          ),
        ],
      ),
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Wrap(
          spacing: 8,
          children: [
            for (final d in const [7, 30, 90])
              ChoiceChip(
                label: Text(vm.pair('近 $d 天', 'Last $d days')),
                selected: _days == d,
                onSelected: (_) => setState(() => _days = d),
              ),
          ],
        ),
        const SizedBox(height: 16),
        _Loaded<UsageStats>(
          key: ValueKey(_days),
          load: () => widget.admin.stats(_days),
          builder: (context, s, _) => Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              row(
                vm.pair('使用人數', 'Active people'),
                '${s.count('active_users')}',
              ),
              row(
                vm.pair('看過學生經驗', 'Read an experience'),
                '${s.count('experience_readers')} · ${pct(s.rate('reader_rate'))}',
              ),
              row(
                vm.pair('分享經驗的人', 'Shared an experience'),
                '${s.count('sharing_authors')} · ${pct(s.rate('share_rate'))}',
              ),
              row(
                vm.pair('AI 摘要後確認發布', 'Published after AI summary'),
                '${s.count('published_after_summary')}/${s.count('drafts_with_ai_summary')}'
                ' · ${pct(s.rate('summary_confirm_rate'))}',
              ),
              row(
                vm.pair('作者修改過摘要', 'Summaries edited by author'),
                '${s.count('confirmed_with_author_edits')}',
              ),
              row(
                vm.pair('「我的經驗不同」回應', '"Mine was different" replies'),
                '${s.count('different_responses')}',
              ),
              row(
                vm.pair('7 天內回訪', 'Came back within 7 days'),
                '${s.count('returned_within_7_days')}/${s.count('return_cohort')}'
                ' · ${pct(s.rate('return_rate'))}',
              ),
              row(
                vm.pair('開始辦理', 'Procedures started'),
                '${s.count('executions_started')}',
              ),
              for (final e in s.outcomes.entries)
                row('· ${e.key}', '${e.value}'),
              if (s.stuckSteps.isNotEmpty) ...[
                const SizedBox(height: 12),
                Text(
                  vm.pair('最常卡住的步驟', 'Where people get stuck'),
                  style: const TextStyle(fontWeight: FontWeight.w600),
                ),
                for (final st in s.stuckSteps)
                  row(
                    '${st.action.of(vm.english)} · ${st.step?.of(vm.english) ?? '—'}',
                    '${st.count}',
                  ),
              ],
              const SizedBox(height: 12),
              Text(
                vm.pair(
                  '只計算登入的使用者；比例的分母是同期間的使用人數。',
                  'Signed-in people only; rates are out of active people in the same period.',
                ),
                style: const TextStyle(fontSize: 13, color: Palette.muted),
              ),
            ],
          ),
        ),
      ],
    );
  }
}
