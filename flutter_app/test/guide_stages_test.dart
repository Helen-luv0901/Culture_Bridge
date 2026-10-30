import 'package:culture_bridge/domain/api_models.dart';
import 'package:culture_bridge/ui/features/action_pages.dart';
import 'package:culture_bridge/ui/features/guide_stages.dart';
import 'package:flutter_test/flutter_test.dart';

ActionSummary _guide(String slug) => ActionSummary(
  id: 'id-$slug',
  slug: slug,
  versionNumber: 1,
  title: Text2(slug, slug),
  description: const Text2('', ''),
  applicableTo: const Text2('', ''),
  location: null,
  verificationStatus: 'unverified',
  lastVerifiedAt: null,
  recentSuccessCount: 0,
);

void main() {
  final guides = [
    _guide('bank-account'),
    _guide('arc-first'),
    _guide('brand-new-guide'),
    _guide('enrollment-certificate'),
  ];

  test('guides are grouped by stage in the order students need them', () {
    final groups = guidesByStage(guides);
    expect(groups.map((g) => g.$1.key), ['papers', 'money', 'other']);
    expect(groups.first.$2.map((g) => g.slug), [
      'enrollment-certificate',
      'arc-first',
    ]);
    // A guide in no stage is still listed, last.
    expect(groups.last.$2.single.slug, 'brand-new-guide');
  });

  test('a post that names a procedure finds its guide', () {
    final found = guidesMentionedIn('哪裡可以申請在學證明書？', guides);
    expect(found.map((g) => g.slug), ['enrollment-certificate']);
  });

  test('English keywords match whole words only', () {
    expect(guidesMentionedIn('How long does an ARC take?', guides), isNotEmpty);
    expect(guidesMentionedIn('I did some research', guides), isEmpty);
  });

  test('at most two guides are suggested', () {
    final found = guidesMentionedIn('在學證明、居留證、銀行開戶', guides);
    expect(found, hasLength(2));
  });

  test('repeated source names after sentences are dropped', () {
    const sources = [
      SourceInfo(
        title: 't',
        url: 'https://example.gov.tw',
        publisher: '內政部移民署',
        publisherEn: 'National Immigration Agency',
        kind: 'official',
        evidenceNote: '',
      ),
    ];
    expect(
      withoutCitations('入國後30日內申請（內政部移民署）。逾期罰鍰（內政部移民署）。', sources),
      '入國後30日內申請。逾期罰鍰。',
    );
    expect(
      withoutCitations(
        'Apply within 30 days (National Immigration Agency).',
        sources,
      ),
      'Apply within 30 days.',
    );
  });
}
