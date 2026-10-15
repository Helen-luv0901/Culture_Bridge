import 'package:culture_bridge/domain/keys.dart';
import 'package:flutter_test/flutter_test.dart';

import 'test_helpers.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test(
    'Publishing needs a title, text and category, then posts as written',
    () async {
      final app = TestApp();
      addTearDown(app.vm.dispose);
      final (missing, nothing) = await app.vm.publishDraft();
      expect(missing, isNotNull);
      expect(nothing, isNull);
      expect(app.repository.lastPublish, isNull);

      app.vm.updateDraft(title: '  公車要舉手  ', voice: '  第一次等了好久。 ');
      app.vm.updateDraft(category: 'transit');
      app.vm.addCustomTag('公車');
      final (error, item) = await app.vm.publishDraft();
      expect(error, isNull);
      expect(item!.title, '公車要舉手');
      expect(app.repository.lastPublish, containsPair('voice', '第一次等了好久。'));
      expect(app.repository.lastPublish, containsPair('category', 'transit'));
      expect(app.repository.lastPublish!['tags'], ['#公車']);
      expect(app.vm.draft.isEmpty, isTrue);
      expect(app.preferences.draft.title, '');
    },
  );

  test('Custom tags are cleaned, capped and not repeated', () {
    final app = TestApp();
    addTearDown(app.vm.dispose);
    expect(app.vm.addCustomTag('  ##夜 市 '), isNull);
    expect(app.vm.addCustomTag('#夜市'), isNull);
    expect(app.vm.draft.customTags, ['#夜市']);
    expect(app.vm.addCustomTag('   '), isNotNull);
    expect(app.vm.addCustomTag('一二三四五六七八九十十一十二'), isNotNull);
    for (var i = 0; i < 10; i++) {
      app.vm.addCustomTag('tag$i');
    }
    expect(app.vm.draftTags, hasLength(8));
  });

  test('AI tag suggestions follow the text and can be ticked', () async {
    final app = TestApp();
    addTearDown(app.vm.dispose);
    await pumpEventQueue(); // let the test sign-in finish first
    app.vm.updateDraft(voice: '去服務站才知道居留證要先線上預約');
    await app.vm.refreshTagSuggestions();
    expect(app.vm.tagSuggestions, containsAll(['#居留證', '#線上預約']));
    app.vm.toggleChosenTag('#居留證');
    expect(app.vm.draftTags, ['#居留證']);
    app.vm.toggleChosenTag('#居留證');
    expect(app.vm.draftTags, isEmpty);
  });

  test('Tag suggestions failing leaves the draft usable', () async {
    final app = TestApp();
    addTearDown(app.vm.dispose);
    app.repository.aiDown = true;
    app.vm.updateDraft(title: '居留證', voice: '要先線上預約才能去');
    await app.vm.refreshTagSuggestions();
    expect(app.vm.tagSuggestions, isEmpty);
    expect(app.vm.suggestingTags, isFalse);
    expect(app.vm.draft.voice, '要先線上預約才能去');
  });

  test('Categories filter posts and translation follows the reader', () async {
    final app = TestApp();
    addTearDown(app.vm.dispose);
    await app.vm.loadPosts('life');
    final item = app.vm.posts('life').data!.items.single;
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
    await app.vm.loadPosts();
    await app.vm.loadSearch('教授');
    await app.vm.loadExperience('professor-see');
    final item = app.vm.experience('professor-see').data!.item;
    await app.vm.toggleReaction(item, 'experienced_too');
    final listed = app.vm.posts().data!.items.firstWhere(
      (e) => e.id == item.id,
    );
    expect(listed.experiencedTooCount, item.experiencedTooCount + 1);
    expect(
      app.vm.search('教授').data!.experiences.single.experiencedTooCount,
      item.experiencedTooCount + 1,
    );
    expect(
      app.vm.reacted(
        app.vm.experience('professor-see').data!.item,
        'experienced_too',
      ),
      isTrue,
    );
  });

  test('Comments: add, reply, like and delete with replies', () async {
    final app = TestApp();
    addTearDown(app.vm.dispose);
    await app.vm.loadExperience('professor-see');
    expect(await app.vm.addComment('professor-see', '   '), isNotNull);
    expect(await app.vm.addComment('professor-see', '我也是'), isNull);
    final first = app.vm.comments('professor-see').data!.single;
    await app.vm.addComment('professor-see', '謝謝', replyToId: first.id);
    expect(app.vm.comments('professor-see').data, hasLength(2));
    expect(app.vm.experience('professor-see').data!.item.commentCount, 2);

    await app.vm.toggleCommentLike('professor-see', first);
    final liked = app.vm.comments('professor-see').data!.first;
    expect(liked.liked, isTrue);
    expect(liked.likeCount, 1);

    await app.vm.deleteComment('professor-see', liked);
    expect(app.vm.comments('professor-see').data, isEmpty);
    expect(app.vm.experience('professor-see').data!.item.commentCount, 0);
  });

  test('Read posts and saved guides are remembered on the device', () {
    final app = TestApp();
    addTearDown(app.vm.dispose);
    expect(app.vm.isRead('first-rental'), isFalse);
    app.vm.markRead('first-rental');
    expect(app.vm.isRead('first-rental'), isTrue);
    expect(app.preferences.readIds, {'first-rental'});

    app.vm.toggleSavedGuide('arc');
    expect(app.vm.guideSaved('arc'), isTrue);
    expect(app.preferences.savedGuides, {'arc'});
    app.vm.toggleSavedGuide('arc');
    expect(app.vm.guideSaved('arc'), isFalse);
  });

  test('Documents checklist counts what is ready', () {
    final app = TestApp();
    addTearDown(app.vm.dispose);
    app.vm.toggleDocument('arc', 0);
    app.vm.toggleDocument('arc', 1);
    app.vm.toggleDocument('arc', 0);
    expect(app.vm.documentsReady('arc'), 1);
    expect(app.vm.documentReady('arc', 1), isTrue);
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
    expect(categoryLabels.keys, [
      'all',
      'official',
      'life',
      'food',
      'housing',
      'transit',
      'study',
      'culture',
    ]);
  });
}
