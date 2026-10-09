# Responsive Culture Bridge

The active React app is a responsive website. Desktop, tablet and phone use the same routes and components; the phone mockup gallery is no longer the entry point.

## Layout

| Width | Navigation | Content |
| --- | --- | --- |
| 1101px and up | Left sidebar | Two-column home and experience list |
| 768–1100px | Compact left sidebar | Single-column content |
| Below 768px | Fixed bottom navigation | Single-column content with safe-area clearance |

The visual system keeps the v4.2 paper textures, hand-drawn SVGs, layered paper and botanical assets. Body text is 16px, reading flows are capped at 760px, and interactive controls are at least 44px high. Impact numbers use 42–48px text.

## Interaction and accessibility

- Main navigation uses hash links and supports browser back/forward.
- Experience and action details include the item ID in the URL.
- Explore filters use buttons with `aria-pressed`; the selected topic remains in the URL.
- Returning from an experience restores its source page and topic filter.
- Empty experience submissions display an inline error and focus the writing field.
- Sharing drafts remain mounted while switching pages or editing a review.
- Keyboard focus, a skip link, route heading focus, reduced motion and mobile safe areas are supported.
- The review/publish flow remains a frontend preview; it does not publish to a service.

## Verification

Edge was used to check Home, Explore, Share and My at 320, 375, 768, 812 (landscape), 1024 and 1440px: 24 route/viewport checks. Checked filtering, detail/back, empty submission, review/edit draft preservation, action progress toggling, mobile navigation and reduced motion. Also inspected Traditional Chinese versions of all nine routes for overflow and undersized text.

Design references: the supplied v4.2 HTML, UI/UX Pro Max's collage style and interaction/responsive guidance, and Vercel Web Interface Guidelines. Automated recommendations were adapted to the supplied visual direction.
