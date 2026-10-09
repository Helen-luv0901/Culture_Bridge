import 'package:flutter_test/flutter_test.dart';
import 'package:culture_bridge/data/content_repository.dart';
import 'package:culture_bridge/ui/view_models/bridge_view_model.dart';

import 'test_helpers.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late AssetContentRepository repository;
  setUpAll(() async {
    repository = await AssetContentRepository.load();
  });
  test('Only a non-empty current draft can enter review', () {
    final vm = BridgeViewModel(
      content: repository,
      preferences: MemoryPreferences(),
    );
    addTearDown(vm.dispose);
    expect(vm.prepareReview(), false);
    vm.updateDraft(voice: '  My experience  ');
    expect(vm.prepareReview(), true);
    expect(vm.reviewedDraft!.voice, 'My experience');
    vm.updateDraft(voice: 'Changed');
    expect(vm.reviewedDraft, isNull);
  });
  test('Filter and translated content retain the source story', () {
    final vm = BridgeViewModel(
      content: repository,
      preferences: MemoryPreferences(),
    );
    addTearDown(vm.dispose);
    expect(vm.filtered('lifeAdaptation').single.id, 'first-rental');
    final experience = vm.experience('first-rental')!;
    expect(experience.text('originalVoice', false), contains('第一次'));
    expect(experience.text('originalVoice', true), contains('rental'));
  });
  test(
    'Steps stay scoped to the task and starting again preserves progress',
    () {
      final vm = BridgeViewModel(
        content: repository,
        preferences: MemoryPreferences(),
      );
      addTearDown(vm.dispose);
      vm.startAction('work-permit');
      vm.toggleStep('work-permit', 0);
      vm.startAction('work-permit');
      expect(vm.completed('work-permit'), {0});
      expect(vm.completed('arc'), isEmpty);
      vm.toggleStep('work-permit', 0);
      expect(vm.completed('work-permit'), isEmpty);
    },
  );
  test('Helpful toggles do not alter repository sample counts', () {
    final vm = BridgeViewModel(
      content: repository,
      preferences: MemoryPreferences(),
    );
    addTearDown(vm.dispose);
    final count = vm.experience('professor-see')!.helpfulCount;
    vm.toggleHelpful('professor-see');
    expect(vm.helpful('professor-see'), true);
    expect(vm.experience('professor-see')!.helpfulCount, count);
    vm.toggleHelpful('professor-see');
    expect(vm.helpful('professor-see'), false);
  });
}
