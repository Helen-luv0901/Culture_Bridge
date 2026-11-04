import 'dart:async';

import 'package:culture_bridge/app.dart';
import 'package:culture_bridge/data/api_client.dart';
import 'package:culture_bridge/data/auth_service.dart';
import 'package:culture_bridge/domain/api_models.dart';
import 'package:culture_bridge/ui/view_models/bridge_view_model.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'fake_repository.dart';
import 'test_helpers.dart';

/// A fake with the knobs these tests need: pages of [pageSize], held or failing
/// list loads, a profile that fails first, and held assistant replies.
class _Repo extends FakeCultureRepository {
  _Repo(super.auth);

  int pageSize = 1000;
  Completer<void>? holdExplore;
  ApiException? exploreError;
  final List<String> exploreCalls = [];

  int profileFailures = 0;
  Completer<void>? holdProfile;
  Completer<void>? holdAsk;
  Object? askError;
  String? failStep;
  Completer<void>? holdFailingStep;
  Completer<void>? holdConfirm;
  int confirmCalls = 0;
  Completer<void>? holdFeedback;
  int feedbackCalls = 0;

  @override
  Future<ExperiencePage> explore({
    String? category,
    String? query,
    String? locale,
    String? actionId,
    String sort = 'new',
    int offset = 0,
  }) async {
    exploreCalls.add('${category ?? 'all'}@$offset');
    final hold = holdExplore;
    if (hold != null && offset > 0) await hold.future;
    final error = exploreError;
    if (error != null) throw error;
    final all = await super.explore(
      category: category,
      query: query,
      locale: locale,
      actionId: actionId,
      sort: sort,
    );
    final items = all.items.skip(offset).take(pageSize).toList();
    final next = offset + items.length < all.items.length
        ? offset + items.length
        : null;
    return ExperiencePage(items, next);
  }

  @override
  Future<Execution> setStep(
    String executionId,
    String stepId,
    String state,
  ) async {
    if (stepId == failStep) {
      await holdFailingStep?.future;
      throw const ApiException(503, 'network_error');
    }
    return super.setStep(executionId, stepId, state);
  }

  @override
  Future<Profile> me() async {
    await holdProfile?.future;
    if (profileFailures > 0) {
      profileFailures--;
      throw const ApiException(503, 'network_error');
    }
    return super.me();
  }

  @override
  Future<AssistantReply> askAssistant({
    required String message,
    required String locale,
    String? conversationId,
    Map<String, String>? screen,
  }) async {
    await holdAsk?.future;
    final error = askError;
    if (error != null) throw error;
    return super.askAssistant(
      message: message,
      locale: locale,
      conversationId: conversationId,
      screen: screen,
    );
  }

  @override
  Future<PendingOperation> confirmOperation(String id) async {
    confirmCalls++;
    await holdConfirm?.future;
    return super.confirmOperation(id);
  }

  @override
  Future<void> sendFeedback(
    String executionId, {
    required String kind,
    String? stepId,
    String? category,
    String? text,
  }) async {
    feedbackCalls++;
    await holdFeedback?.future;
    return super.sendFeedback(
      executionId,
      kind: kind,
      stepId: stepId,
      category: category,
      text: text,
    );
  }
}

class _App {
  _App._() : auth = DevAuthService(null), preferences = MemoryPreferences() {
    repository = _Repo(auth);
    vm = BridgeViewModel(
      repository: repository,
      auth: auth,
      messages: loadMessages(),
      preferences: preferences,
    );
  }

  /// Signing in clears personal data when it lands, so wait for it before a test starts.
  static Future<_App> create({bool signedIn = true}) async {
    final app = _App._();
    if (signedIn) await app.auth.signInAsDev('test');
    await Future<void>.delayed(Duration.zero);
    return app;
  }

  final DevAuthService auth;
  final MemoryPreferences preferences;
  late final _Repo repository;
  late final BridgeViewModel vm;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('Live posts', () {
    test('only lists on screen are checked for new posts', () async {
      final app = await _App.create();
      await app.vm.loadPosts(null);
      await app.vm.loadPosts('food');
      app.vm.watchPosts(null, 'new', null, true);
      app.repository.exploreCalls.clear();
      await app.vm.refreshNewPosts();
      expect(app.repository.exploreCalls, ['all@0']);

      app.vm.watchPosts(null, 'new', null, false);
      app.repository.exploreCalls.clear();
      await app.vm.refreshNewPosts();
      expect(app.repository.exploreCalls, isEmpty);
    });
  });

  group('Load more', () {
    test('a tap on a card meanwhile does not throw the next page away', () async {
      final app = await _App.create();
      app.repository.pageSize = 1;
      await app.vm.loadPosts(null);
      expect(app.vm.posts().data!.items, hasLength(1));
      app.repository.holdExplore = Completer();
      final more = app.vm.loadPosts(null, true);
      // A reaction while the next page is on its way replaces the cached list.
      await app.vm.toggleReaction(
        app.vm.posts().data!.items.first,
        'experienced_too',
      );
      app.repository.holdExplore!.complete();
      await more;
      expect(app.vm.posts().data!.items, hasLength(2));
      expect(app.vm.posts().loading, isFalse);
      // The reaction made meanwhile is kept.
      expect(
        app.vm.posts().data!.items.first.myReactions,
        contains('experienced_too'),
      );
    });

    test('a post that moved down a page is not shown twice', () async {
      final app = await _App.create();
      app.repository.pageSize = 2;
      await app.vm.loadPosts(null);
      final first = app.vm.posts().data!.items.map((e) => e.id).toList();
      // Someone publishes: every older post moves down one place.
      await app.repository.publishPost(
        title: '新貼文',
        voice: '把舊貼文往下推一格。',
        category: 'life',
        tags: const [],
        sourceLocale: 'zh-Hant',
      );
      await app.vm.loadPosts(null, true);
      final ids = app.vm.posts().data!.items.map((e) => e.id).toList();
      expect(ids.take(2), first);
      expect(ids.toSet(), hasLength(ids.length)); // no duplicates
    });
  });

  testWidgets('A failed load under a list says so, with a retry', (
    tester,
  ) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(1280, 2400);
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final app = (await tester.runAsync(_App.create))!;
    addTearDown(app.vm.dispose);
    await tester.pumpWidget(
      CultureBridgeApp(viewModel: app.vm, initialLocation: '/'),
    );
    await tester.pumpAndSettle();
    app.repository.exploreError = const ApiException(0, 'network_error');
    await app.vm.loadPosts(null);
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('list-error')), findsOneWidget);
    app.repository.exploreError = null;
    await tester.tap(find.byKey(const Key('list-error-retry')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('list-error')), findsNothing);
  });

  test('Signing out forgets the unpublished draft on this device', () async {
    final app = await _App.create();
    app.vm.updateDraft(title: '還沒發的標題', voice: '只有我看得到的內容');
    await app.vm.signOut();
    expect(app.vm.draft.title, isEmpty);
    expect(app.vm.draft.voice, isEmpty);
    expect(app.preferences.draft.voice, isEmpty);
  });

  test(
    'Being signed out by the app (an expired login) keeps the draft',
    () async {
      final app = await _App.create();
      app.vm.updateDraft(title: '寫到一半', voice: '登入過期也不能弄丟');
      await app.auth
          .signOut(); // not the person's choice: e.g. a 401 or a dead token
      expect(app.vm.draft.voice, '登入過期也不能弄丟');
    },
  );

  test('A profile answer that arrives after signing out is dropped', () async {
    final app = await _App.create(signedIn: false);
    app.repository.holdProfile = Completer();
    await app.auth.signInAsDev('test');
    await Future<void>.delayed(
      Duration.zero,
    ); // the profile request is on its way
    await app.vm.signOut();
    app.repository.holdProfile!.complete();
    await Future<void>.delayed(const Duration(milliseconds: 20));
    expect(app.vm.profile, isNull);
  });

  test('A profile that failed to load is tried again', () async {
    final app = await _App.create(signedIn: false);
    app.vm.profileRetryAfter = const Duration(milliseconds: 10);
    app.repository.profileFailures = 1;
    app.auth.signInAsDev('test');
    await Future<void>.delayed(const Duration(milliseconds: 5));
    expect(app.vm.profile, isNull);
    await Future<void>.delayed(const Duration(milliseconds: 60));
    expect(app.vm.profile, isNotNull);
  });

  group('Assistant', () {
    test('a reply to a cleared chat does not come back', () async {
      final app = await _App.create();
      app.repository.holdAsk = Completer();
      final asked = app.vm.ask('居留證要準備什麼？');
      await app.vm.clearChat();
      app.repository.holdAsk!.complete();
      await asked;
      expect(app.vm.chat, isEmpty);
      expect(app.vm.conversationId, isNull);
      expect(app.vm.asking, isFalse);
    });

    test('a reply after signing out does not reach the next person', () async {
      final app = await _App.create();
      app.repository.holdAsk = Completer();
      final asked = app.vm.ask('居留證要準備什麼？');
      await app.auth.signOut();
      app.repository.holdAsk!.complete();
      await asked;
      expect(app.vm.chat, isEmpty);
      expect(app.vm.conversationId, isNull);
    });

    test('an unreadable reply does not leave the chat stuck', () async {
      final app = await _App.create();
      app.repository.askError = TypeError();
      await app.vm.ask('居留證要準備什麼？');
      expect(app.vm.asking, isFalse);
      expect(app.vm.chat.last.failed, isTrue);
      app.repository.askError = null;
      await app.vm.ask('再問一次');
      expect(app.vm.chat.last.failed, isFalse);
    });

    test('confirming twice sends one request', () async {
      final app = await _App.create();
      app.repository.holdConfirm = Completer();
      final operation = PendingOperation(
        id: 'op1',
        summary: '開始辦理',
        status: 'pending',
        expiresAt: DateTime.now().add(const Duration(hours: 1)),
        targetId: 'arc',
        result: null,
      );
      final first = app.vm.resolveOperation(operation, true);
      final second = app.vm.resolveOperation(operation, true);
      expect(app.vm.resolvingOperation('op1'), isTrue);
      app.repository.holdConfirm!.complete();
      await Future.wait([first, second]);
      expect(app.repository.confirmCalls, 1);
      expect(app.vm.resolvingOperation('op1'), isFalse);
    });
  });

  test('Sending "I am stuck" twice sends one report', () async {
    final app = await _App.create();
    final execution = (await app.vm.startAction('arc'))!;
    app.repository.holdFeedback = Completer();
    final step = execution.steps.first.stepId;
    final first = app.vm.reportStuck(execution, step, 'dontUnderstandStep', '');
    final second = app.vm.reportStuck(
      execution,
      step,
      'dontUnderstandStep',
      '',
    );
    expect(app.vm.reportingStuck, isTrue);
    app.repository.holdFeedback!.complete();
    await Future.wait([first, second]);
    expect(app.repository.feedbackCalls, 1);
    expect(app.vm.reportingStuck, isFalse);
  });

  test('Undoing a failed tick leaves a later tick alone', () async {
    final app = await _App.create();
    final execution = (await app.vm.startAction('arc'))!;
    final a = execution.steps[0].stepId;
    final b = execution.steps[1].stepId;
    app.repository.failStep = a;
    app.repository.holdFailingStep = Completer();
    final tickA = app.vm.setStepDone(execution, a, true);
    await app.vm.setStepDone(app.vm.openExecution('arc')!, b, true); // succeeds
    app.repository.holdFailingStep!.complete();
    await tickA;
    final steps = app.vm.openExecution('arc')!.steps;
    expect(steps[0].state, isNot('done')); // A put back
    expect(steps[1].state, 'done'); // B kept
  });

  test('A ticked step shows as done before the server answers', () async {
    final app = await _App.create();
    final execution = (await app.vm.startAction('arc'))!;
    final step = execution.steps.first.stepId;
    final done = app.vm.setStepDone(execution, step, true);
    final shown = app.vm.openExecution('arc')!.steps.first;
    expect(shown.state, 'done');
    await done;
    expect(app.vm.openExecution('arc')!.steps.first.state, 'done');
  });
}
