part of 'bridge_view_model.dart';

mixin _BridgePosts on _BridgeCore {
  // ---------- posts: feed, categories, search ----------

  /// Newest student posts in [category] (null: every category).
  /// Student posts, newest first (`'new'`) or most discussed first (`'hot'`:
  /// "me too" taps plus comments).
  Resource<ExperiencePage> posts([String? category, String sort = 'new']) =>
      _explore[_listKey(category, sort, null)] ?? const Resource();
  Future<void> loadPosts([
    String? category,
    bool more = false,
    String sort = 'new',
  ]) => _loadList(category, sort, null, more);

  /// Student posts shared under an official guide.
  Resource<ExperiencePage> postsForAction(String actionId) =>
      _explore[_listKey(null, 'new', actionId)] ?? const Resource();
  Future<void> loadPostsForAction(String actionId) =>
      _loadList(null, 'new', actionId, false);

  Timer? _liveTimer;

  /// Lists on screen now (by [_listKey], counted per view showing them). Only these are
  /// checked for new posts, not every list opened since the app started.
  final Map<String, int> _watching = {};

  /// A view showing this list appeared ([on]) or went away.
  void watchPosts(String? category, String sort, String? actionId, bool on) {
    final key = _listKey(category, sort, actionId);
    final count = (_watching[key] ?? 0) + (on ? 1 : -1);
    if (count > 0) {
      _watching[key] = count;
    } else {
      _watching.remove(key);
    }
  }

  /// Starts looking for new posts every [livePostsEvery] while the app is in view.
  void startLivePosts() {
    final every = livePostsEvery;
    if (every == null) return;
    _liveTimer?.cancel();
    _liveTimer = Timer.periodic(every, (_) => unawaited(refreshNewPosts()));
  }

  /// The app went to the background (no checks) or came back (check now, then keep going).
  void setAppVisible(bool visible) {
    if (!visible) {
      _liveTimer?.cancel();
      _liveTimer = null;
      return;
    }
    unawaited(refreshNewPosts());
    startLivePosts();
  }

  bool _refreshing = false;

  /// Puts posts published since a newest-first list was loaded at its top, without a reload.
  Future<void> refreshNewPosts() async {
    if (_refreshing) return;
    _refreshing = true;
    var changed = false;
    try {
      final keys = [
        for (final entry in _explore.entries)
          if (entry.key.split('|')[1] == 'new' &&
              entry.value.data != null &&
              _watching.containsKey(entry.key))
            entry.key,
      ];
      for (final key in keys) {
        final [category, _, actionId] = key.split('|');
        final ExperiencePage page;
        try {
          page = await repository.explore(
            category: category == 'all' ? null : category,
            actionId: actionId.isEmpty ? null : actionId,
            locale: locale,
          );
        } on ApiException {
          continue; // offline or busy: try again next time
        }
        final resource = _explore[key];
        final current = resource?.data;
        if (resource == null || current == null) continue;
        final known = {for (final e in current.items) e.id};
        final fresh = [
          for (final e in page.items)
            if (!known.contains(e.id)) e,
        ];
        if (fresh.isEmpty) continue;
        _explore[key] = resource.withData(
          ExperiencePage([...fresh, ...current.items], current.nextOffset),
        );
        changed = true;
      }
    } finally {
      _refreshing = false;
    }
    if (changed) notifyListeners();
  }

  Future<void> _loadList(
    String? category,
    String sort,
    String? actionId,
    bool more,
  ) {
    final key = _listKey(category, sort, actionId);
    final current = _explore[key]?.data;
    // A second "more" while one is loading would ask for the same page twice.
    if (more && (_explore[key]?.loading ?? false)) return Future.value();
    return _load(
      () => _explore[key] ?? const Resource<ExperiencePage>(),
      (r) => _explore[key] = r,
      () async {
        final page = await repository.explore(
          category: category,
          actionId: actionId,
          sort: sort,
          locale: locale,
          offset: more ? current?.nextOffset ?? 0 : 0,
        );
        if (!more) return page;
        // Join with the list as it is now (a reaction or new posts may have changed it
        // meanwhile), skipping posts already shown: a post published since the last page
        // pushes the older ones down, so the next page starts with one we have.
        final latest = _explore[key]?.data ?? current;
        if (latest == null) return page;
        final shown = {for (final e in latest.items) e.id};
        return ExperiencePage([
          ...latest.items,
          for (final e in page.items)
            if (!shown.contains(e.id)) e,
        ], page.nextOffset);
      },
    );
  }

  Resource<SearchResults> search(String query) =>
      _searches[query.trim()] ?? const Resource();
  Future<void> loadSearch(String query) {
    final q = query.trim();
    return _load(
      () => search(q),
      (r) => _searches[q] = r,
      () => repository.search(q, locale: locale),
    );
  }

  Resource<List<String>> popularTags = const Resource();
  Future<void> loadPopularTags() =>
      _load(() => popularTags, (r) => popularTags = r, repository.popularTags);

  Resource<ExperienceDetail> experience(String id) =>
      _experiences[id] ?? const Resource();
  Future<void> loadExperience(String id) => _load(
    () => experience(id),
    (r) => _experiences[id] = r,
    () => repository.experience(id),
  );

  bool reacted(ExperienceItem item, String kind) =>
      item.myReactions.contains(kind);

  Future<void> toggleReaction(ExperienceItem item, String kind) async {
    try {
      _updateItem(await repository.react(item.id, kind, !reacted(item, kind)));
    } on ApiException catch (e) {
      showNotice(errorText(e));
    }
  }
}
