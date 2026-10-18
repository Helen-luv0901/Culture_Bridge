// The API uses snake_case ids; interface strings (messages.json) use camelCase keys.

const topicKeys = {
  'life_adaptation': 'lifeAdaptation',
  'culture_communication': 'cultureCommunication',
};
const identityKeys = {
  'degree_student': 'degreeStudent',
  'exchange_student': 'exchangeStudent',
  'language_student': 'languageStudent',
  'other': 'otherIdentity',
};
const statusKeys = {
  'verified': 'verified',
  'needs_review': 'needsReview',
  'community_supported': 'communitySupported',
  'unverified': 'unverified',
  'outdated': 'outdated',
};

String topicKey(String apiId) => topicKeys[apiId] ?? apiId;
String identityKey(String apiId) => identityKeys[apiId] ?? apiId;
String statusKey(String apiId) => statusKeys[apiId] ?? apiId;

String apiTopic(String key) =>
    topicKeys.entries.firstWhere((e) => e.value == key).key;
String apiIdentity(String key) =>
    identityKeys.entries.firstWhere((e) => e.value == key).key;

/// Explore and share categories in both languages (zh, en).
const categoryLabels = {
  'all': ('全部', 'All'),
  'official': ('官方', 'Official'),
  'life': ('生活', 'Life'),
  'food': ('美食', 'Food'),
  'housing': ('住宿', 'Housing'),
  'transit': ('交通', 'Transport'),
  'study': ('學業', 'Study'),
  'culture': ('文化', 'Culture'),
  'difference': ('文化差異', 'Cultural differences'),
};
