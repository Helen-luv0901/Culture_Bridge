import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../core/design_system.dart';

class SharePage extends StatefulWidget {
  const SharePage({super.key});
  @override
  State<SharePage> createState() => _SharePageState();
}

class _SharePageState extends State<SharePage> {
  final _form = GlobalKey<FormState>();
  final _focus = FocusNode();
  TextEditingController? _controller;
  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _controller ??= TextEditingController(
      text: BridgeScope.of(context).draft.voice,
    );
  }

  @override
  void dispose() {
    _controller?.dispose();
    _focus.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final vm = BridgeScope.of(context);
    return FlowBody(
      children: [
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            PaperTag(vm.t('anonymousShare')),
            const SizedBox(height: 16),
            Text(vm.t('whatHappened'), style: displayStyle(28)),
            const SizedBox(height: 12),
            Text(
              vm.t('oneSentence'),
              style: const TextStyle(color: Palette.muted),
            ),
          ],
        ),
        Form(
          key: _form,
          child: TextFormField(
            key: const Key('share-voice'),
            controller: _controller,
            focusNode: _focus,
            minLines: 6,
            maxLines: 12,
            maxLength: 2000,
            keyboardType: TextInputType.multiline,
            decoration: InputDecoration(
              labelText: vm.t('yourOriginalVoice'),
              alignLabelWithHint: true,
            ),
            onChanged: (value) => vm.updateDraft(voice: value),
            validator: (value) => value == null || value.trim().isEmpty
                ? vm.pair(
                    '請先寫下發生了什麼事，再整理你的經驗。',
                    'Write what happened before reviewing your experience.',
                  )
                : null,
          ),
        ),
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            PaperHeading(vm.t('topic')),
            Wrap(
              spacing: 12,
              runSpacing: 8,
              children: [
                for (final topic in ['lifeAdaptation', 'cultureCommunication'])
                  ChoiceChip(
                    label: Text(vm.t(topic)),
                    selected: vm.draft.topic == topic,
                    onSelected: (_) => vm.updateDraft(topic: topic),
                  ),
              ],
            ),
          ],
        ),
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            PaperHeading(vm.t('identityType')),
            Wrap(
              spacing: 12,
              runSpacing: 8,
              children: [
                for (final identity in [
                  'degreeStudent',
                  'exchangeStudent',
                  'languageStudent',
                ])
                  ChoiceChip(
                    label: Text(vm.t(identity)),
                    selected: vm.draft.identity == identity,
                    onSelected: (_) => vm.updateDraft(identity: identity),
                  ),
              ],
            ),
          ],
        ),
        Text(
          vm.t('anonymousNote'),
          style: const TextStyle(fontSize: 14, color: Palette.muted),
        ),
        FilledButton(
          key: const Key('review-draft'),
          onPressed: () {
            if (_form.currentState!.validate() && vm.prepareReview()) {
              context.go('/review');
            } else {
              _focus.requestFocus();
            }
          },
          child: Text(vm.t('askAiToOrganize')),
        ),
      ],
    );
  }
}

class ReviewPage extends StatelessWidget {
  const ReviewPage({super.key});
  @override
  Widget build(BuildContext context) {
    final vm = BridgeScope.of(context);
    final draft = vm.reviewedDraft;
    if (draft == null) return const SizedBox.shrink();
    return FlowBody(
      children: [
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(vm.t('reviewTitle'), style: displayStyle(28)),
            const SizedBox(height: 12),
            Text(vm.t('reviewNote')),
            const SizedBox(height: 8),
            Text(
              vm.pair(
                '這是示範整理，尚未連接 AI 服務。',
                'This is a preview summary; no AI service is connected.',
              ),
              style: const TextStyle(fontSize: 14, color: Palette.muted),
            ),
          ],
        ),
        PaperCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              PaperHeading(vm.t('yourOriginalVoice')),
              Text('「${draft.voice}」'),
            ],
          ),
        ),
        PaperCard(
          color: Palette.oat,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              PaperHeading(vm.t('aiDraft')),
              Text(
                vm.t('situation'),
                style: const TextStyle(fontWeight: FontWeight.bold),
              ),
              Text(
                vm.pair(
                  '${vm.t(draft.identity)}分享一則關於「${vm.t(draft.topic)}」的經驗。',
                  'A ${vm.t(draft.identity).toLowerCase()} is sharing an experience about ${vm.t(draft.topic).toLowerCase()}.',
                ),
              ),
              const SizedBox(height: 16),
              Text(
                vm.t('reminder'),
                style: const TextStyle(fontWeight: FontWeight.bold),
              ),
              Text(
                vm.pair(
                  '每個人的情境與感受可能不同；這段原話提供另一種理解。',
                  'Situations and feelings can differ. This original voice offers another perspective.',
                ),
              ),
            ],
          ),
        ),
        Wrap(
          spacing: 16,
          runSpacing: 12,
          children: [
            OutlinedButton(
              key: const Key('edit-draft'),
              onPressed: () => context.go('/share'),
              child: Text(vm.t('editOriginal')),
            ),
            FilledButton(
              onPressed: () {
                vm.finishPreview();
                context.go('/profile');
              },
              child: Text(vm.pair('確認並完成預覽', 'Confirm and finish preview')),
            ),
          ],
        ),
      ],
    );
  }
}

class ProfilePage extends StatelessWidget {
  const ProfilePage({super.key});
  @override
  Widget build(BuildContext context) {
    final vm = BridgeScope.of(context);
    return FlowBody(
      maxWidth: 880,
      children: [
        Row(
          children: [
            const CircleAvatar(
              backgroundColor: Palette.paleMoss,
              foregroundColor: Palette.moss,
              child: Text('Y'),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    vm.t('anonymousShare'),
                    style: const TextStyle(color: Palette.muted, fontSize: 14),
                  ),
                  Text(
                    vm.pair('匿名學生', 'Anonymous student'),
                    style: displayStyle(23),
                  ),
                ],
              ),
            ),
          ],
        ),
        if (vm.previewNotice != null)
          Semantics(
            liveRegion: true,
            child: PaperCard(
              color: Palette.paleMoss,
              child: Text(vm.previewNotice!),
            ),
          ),
        PaperHeading(vm.t('mySharedExperiences')),
        PaperCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              PaperTag(vm.t('cultureCommunication')),
              const SizedBox(height: 12),
              Text(
                vm.pair(
                  '我不確定教授的語氣是不是不滿意',
                  'I could not tell whether my professor was unhappy',
                ),
                style: const TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                vm.t('aiSummaryConfirmed'),
                style: const TextStyle(color: Palette.muted),
              ),
              TextButton(
                onPressed: () => context.push(
                  '/experiences/professor-see?from=${Uri.encodeComponent('/profile')}',
                ),
                child: Text('3 ${vm.t('reactions')}'),
              ),
            ],
          ),
        ),
        PaperCard(
          color: Palette.oat,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              PaperHeading(vm.t('yourImpact')),
              LayoutBuilder(
                builder: (context, c) => Wrap(
                  spacing: 24,
                  runSpacing: 24,
                  children: [
                    SizedBox(
                      width: (c.maxWidth - 24) / 2,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            '3',
                            style: displayStyle(48)
                                .copyWith(color: Palette.moss),
                          ),
                          Text(vm.pair('匿名分享', 'anonymized shares')),
                        ],
                      ),
                    ),
                    SizedBox(
                      width: (c.maxWidth - 24) / 2,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            '7',
                            style: displayStyle(48)
                                .copyWith(color: Palette.moss),
                          ),
                          Text(
                            vm.pair('位學生認為有幫助', 'students found them helpful'),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 12),
              Text(
                vm.pair('目前為示範資料。', 'Currently showing sample data.'),
                style: const TextStyle(fontSize: 13, color: Palette.muted),
              ),
            ],
          ),
        ),
        Wrap(
          spacing: 16,
          runSpacing: 8,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            Text(vm.t('language')),
            ChoiceChip(
              label: const Text('繁中'),
              selected: !vm.english,
              onSelected: (_) => vm.setEnglish(false),
            ),
            ChoiceChip(
              label: const Text('English'),
              selected: vm.english,
              onSelected: (_) => vm.setEnglish(true),
            ),
          ],
        ),
      ],
    );
  }
}
