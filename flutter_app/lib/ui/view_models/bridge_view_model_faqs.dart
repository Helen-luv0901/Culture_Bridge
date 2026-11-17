part of 'bridge_view_model.dart';

mixin _BridgeFaqs on _BridgeCore {
  // ---------- official Q&A (MOE NISA) ----------

  /// Every official question with its categories; the list page filters it on the device.
  Resource<FaqCatalog> faqs = const Resource();
  Future<void> loadFaqs() =>
      _load(() => faqs, (r) => faqs = r, repository.faqs);

  final Map<String, Resource<FaqDetail>> _faqDetails = {};
  Resource<FaqDetail> faq(String id) => _faqDetails[id] ?? const Resource();
  Future<void> loadFaq(String id) => _load(
    () => faq(id),
    (r) => _faqDetails[id] = r,
    () => repository.faq(id),
  );

  /// Student posts about the same subject as the question [id].
  Resource<List<ExperienceItem>> faqPosts(String id) =>
      _faqPosts[id] ?? const Resource();
  Future<void> loadFaqPosts(String id) => _load(
    () => faqPosts(id),
    (r) => _faqPosts[id] = r,
    () => repository.faqRelatedPosts(id, locale: locale),
  );

  /// Official questions related to the student post [postId].
  final Map<String, Resource<List<FaqSummary>>> _postFaqs = {};
  Resource<List<FaqSummary>> postFaqs(String postId) =>
      _postFaqs[postId] ?? const Resource();
  Future<void> loadPostFaqs(String postId) => _load(
    () => postFaqs(postId),
    (r) => _postFaqs[postId] = r,
    () => repository.relatedFaqs(postId),
  );
}
