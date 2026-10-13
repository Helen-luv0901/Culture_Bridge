import 'package:culture_bridge/domain/keys.dart';
import 'package:flutter_test/flutter_test.dart';

import 'test_helpers.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('Blank drafts never reach the AI', () async {
    final app = TestApp();
    addTearDown(app.vm.dispose);
    expect(await app.vm.prepareReview(), '');
    app.vm.updateDraft(voice: '  My experience  ');
    expect(await app.vm.prepareReview(), isNull);
    expect(app.repository.mine.values.single.originalVoice, 'My experience');
    expect(app.vm.reviewSummary, isNotNull);
    app.vm.updateDraft(voice: 'Changed');
    expect(app.vm.reviewSummary, isNull);
  });

  test('Re-organizing reuses the same server draft', () async {
    final app = TestApp();
    addTearDown(app.vm.dispose);
    app.vm.updateDraft(voice: 'first');
    await app.vm.prepareReview();
    app.vm.updateDraft(voice: 'second');
    await app.vm.prepareReview();
    expect(app.repository.mine.length, 1);
    expect(app.preferences.draft.serverId, app.repository.mine.keys.single);
  });

  test('Explore filters by topic and translation follows the reader', () async {
    final app = TestApp();
    addTearDown(app.vm.dispose);
    await app.vm.loadExplore('lifeAdaptation');
    final item = app.vm.explore('lifeAdaptation').data!.items.single;
    expect(item.id, 'first-rental');
    expect(app.vm.translated(item), isFalse);
    app.vm.setEnglish(true);
    expect(app.vm.translated(item), isTrue);
    expect(item.voice(true), contains('rental'));
    await app.vm.toggleTranslation(item);
    expect(app.vm.translated(item), isFalse);
  });

  test('Starting twice resumes the same execution', () async {
    final app = TestApp();
    addTearDown(app.vm.dispose);
    final first = await app.vm.startAction('work-permit');
    final again = await app.vm.startAction('work-permit');
    expect(again!.id, first!.id);
    await app.vm.setStepDone(first, first.steps.first.stepId, true);
    expect(app.vm.openExecution('work-permit')!.doneCount, 1);
    expect(app.vm.openExecution('arc'), isNull);
  });

  test('Reactions update every cached copy', () async {
    final app = TestApp();
    addTearDown(app.vm.dispose);
    await app.vm.loadExplore('all');
    await app.vm.loadExperience('professor-see');
    final item = app.vm.experience('professor-see').data!.item;
    await app.vm.toggleReaction(item, 'helpful');
    final listed = app.vm
        .explore('all')
        .data!
        .items
        .firstWhere((e) => e.id == item.id);
    expect(listed.helpfulCount, item.helpfulCount + 1);
    expect(
      app.vm.reacted(app.vm.experience('professor-see').data!.item, 'helpful'),
      isTrue,
    );
  });

  test('Signing out clears personal data', () async {
    final app = TestApp();
    addTearDown(app.vm.dispose);
    await app.vm.startAction('arc');
    await app.vm.loadExecutions();
    expect(app.vm.executions.data, isNotEmpty);
    await app.vm.signOut();
    expect(app.vm.executions.data, isNull);
    expect(app.vm.profile, isNull);
  });

  test('Key mapping round-trips', () {
    expect(apiTopic(topicKey('life_adaptation')), 'life_adaptation');
    expect(apiIdentity(identityKey('other')), 'other');
    expect(statusKey('needs_review'), 'needsReview');
  });
}
