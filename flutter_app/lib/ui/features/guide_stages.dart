import '../../domain/api_models.dart';

/// One step of a new student's first months, and the official guides that belong to it,
/// in the order they are usually done. Guides are matched by slug; a guide that is in no
/// stage (a new one) is listed under [otherStage].
class GuideStage {
  const GuideStage(this.key, this.title, this.slugs);
  final String key;
  final (String, String) title;
  final List<String> slugs;
}

const guideStages = [
  GuideStage(
    'arrive',
    ('剛抵達：報到與安頓', 'Just arrived: register and settle in'),
    [
      'fcu-newcomer-registration',
      'myfcu-checklist',
      'fcu-housing',
      'student-medical-insurance',
      'health-check',
    ],
  ),
  GuideStage(
    'papers',
    ('證件：在學證明與居留證', 'Papers: enrolment and your ARC'),
    [
      'enrollment-certificate',
      'arc-first',
      'visitor-to-resident-visa',
      'mandarin-student-residence',
    ],
  ),
  GuideStage(
    'money',
    ('健保與銀行帳戶', 'Health insurance and a bank account'),
    ['nhi', 'bank-account', 'fcu-bank-binding'],
  ),
  GuideStage(
    'daily',
    ('打工與校園生活', 'Part-time work and campus life'),
    ['work-permit', 'leave-request', 'student-id-replacement'],
  ),
  GuideStage(
    'later',
    ('之後會用到', 'Later on'),
    [
      'arc-extension',
      'arc-address-change',
      'arc-replacement',
      'post-graduation-stay',
    ],
  ),
];

const otherStage = GuideStage('other', ('其他指南', 'Other guides'), []);

/// The stages a newcomer works through in the first month (everything but "later").
const firstMonthStages = 4;

/// The guides grouped by stage, each stage in its usual order; empty stages are left out.
List<(GuideStage, List<ActionSummary>)> guidesByStage(
  List<ActionSummary> actions,
) {
  final bySlug = {for (final a in actions) a.slug: a};
  final placed = <String>{};
  final groups = <(GuideStage, List<ActionSummary>)>[];
  for (final stage in guideStages) {
    final guides = [for (final slug in stage.slugs) ?bySlug[slug]];
    placed.addAll(guides.map((g) => g.id));
    if (guides.isNotEmpty) groups.add((stage, guides));
  }
  final others = [
    for (final a in actions)
      if (!placed.contains(a.id)) a,
  ];
  if (others.isNotEmpty) groups.add((otherStage, others));
  return groups;
}

/// Words in a student's post that point at an official guide (by slug).
const _guideKeywords = {
  'enrollment-certificate': [
    '在學證明',
    'enrolment certificate',
    'enrollment certificate',
  ],
  'arc-first': ['居留證', 'ARC', 'residence permit'],
  'nhi': ['健保', 'health insurance', 'NHI'],
  'bank-account': ['銀行', '郵局', '開戶', 'bank account'],
  'work-permit': ['工作許可', '打工', '工讀', 'work permit', 'part-time'],
  'fcu-housing': ['宿舍', '租屋', 'dorm', 'rent'],
  'health-check': ['健檢', '健康檢查', 'health check'],
  'student-medical-insurance': ['僑保', '醫保'],
  'leave-request': ['請假', 'leave of absence'],
  'student-id-replacement': ['學生證', '逢甲卡', 'student ID'],
  'post-graduation-stay': ['畢業後', 'after graduation'],
  'fcu-newcomer-registration': ['新生報到', 'registration'],
};

final _latin = RegExp(r'^[A-Za-z][A-Za-z -]*$');

/// English keywords match whole words only ("ARC" is not inside "search").
bool _mentions(String text, String word) => _latin.hasMatch(word)
    ? RegExp(
        '\\b${RegExp.escape(word)}\\b',
        caseSensitive: false,
      ).hasMatch(text)
    : text.contains(word);

/// Up to [limit] guides whose keywords appear in [text].
List<ActionSummary> guidesMentionedIn(
  String text,
  List<ActionSummary> actions, {
  int limit = 2,
}) {
  final bySlug = {for (final a in actions) a.slug: a};
  return [
    for (final MapEntry(key: slug, value: words) in _guideKeywords.entries)
      if (bySlug[slug] case final guide?)
        if (words.any((w) => _mentions(text, w))) guide,
  ].take(limit).toList();
}
