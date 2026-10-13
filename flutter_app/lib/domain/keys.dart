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
