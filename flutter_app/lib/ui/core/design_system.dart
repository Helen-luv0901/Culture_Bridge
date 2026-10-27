import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';

import '../view_models/bridge_view_model.dart';

/// The teammate's scrapbook palette on a notebook-grid page (docs/product/design.md).
/// The notebook palette (docs/product/design.md): paper with a faint grid, cream cards,
/// moss for actions, brick for links and tape.
abstract final class Palette {
  static const paper = Color(0xFFF1EADC), grid = Color(0xFFEBE3D3), // faint, so text over the paper stays easy to read
  header = Color(0xFFF3EDE1), nav = Color(0xFFF4EEE0), high = Color(0xFFFBF6EA), // cards
  soft = Color(0x0D6B5320), // the vote column: a faint brown wash
  chip = Color(0xFFEFE6D2), // pills, fields
  readCard = Color(0xFFFBF6EA), oat = Color(0xFFE4D8BE), // card borders
  edge = Color(0xFFD6C6A6), // dividers
  ink = Color(0xFF39362E), inkSoft = Color(0xFF4F493E), // excerpts
  readInk = Color(0xFF655D4E),
  // At least 4.5:1 (WCAG AA) on paper, cards, the grid and the pills.
  muted = Color(0xFF655D4E), control = Color(0xFF8C8270), // borders of things you tap or type in
  moss = Color(0xFF4C5540), paleMoss = Color(0xFFDEE1CE), brick = Color(0xFF9E5B4A), brickDeep = Color(0xFF79392E), // links
  ochre = Color(0xFFEFE1C3), // stuck, needs review
  ochreInk = Color(0xFF6B5320), bubble = Color(0xFFEFE6D2), danger = Color(0xFFB42318), onMoss = Color(0xFFFFFFFF);
}

/// Corner radii: soft, so cards and posts don't feel sharp.
abstract final class Radii {
  static const card = 12.0, control = 12.0, pill = 999.0;
}

class BridgeScope extends InheritedNotifier<BridgeViewModel> {
  const BridgeScope({
    super.key,
    required BridgeViewModel viewModel,
    required super.child,
  }) : super(notifier: viewModel);
  static BridgeViewModel of(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<BridgeScope>()!.notifier!;
}

OutlineInputBorder _field([BorderSide side = BorderSide.none]) =>
    OutlineInputBorder(
      borderRadius: BorderRadius.circular(Radii.control),
      borderSide: side,
    );

/// Forum layout in the notebook look: paper, cream cards, Noto Sans TC, moss and brick.
ThemeData bridgeTheme() => ThemeData(
  useMaterial3: true,
  // Bundled (pubspec), so Latin and Chinese text never waits on a font download.
  fontFamily: 'NotoSansTC',
  scaffoldBackgroundColor: Palette.paper,
  colorScheme: ColorScheme.fromSeed(
    seedColor: Palette.moss,
    surface: Palette.high,
    onSurface: Palette.ink,
    primary: Palette.moss,
    onPrimary: Palette.onMoss,
    error: Palette.danger,
  ),
  textTheme: const TextTheme(
    bodyLarge: TextStyle(fontSize: 16, height: 1.6, color: Palette.ink),
    bodyMedium: TextStyle(fontSize: 15, height: 1.6, color: Palette.ink),
    bodySmall: TextStyle(fontSize: 13, height: 1.5, color: Palette.muted),
  ),
  dividerTheme: const DividerThemeData(color: Palette.edge, space: 1),
  filledButtonTheme: FilledButtonThemeData(
    style: FilledButton.styleFrom(
      minimumSize: const Size(48, 48),
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
      backgroundColor: Palette.moss,
      foregroundColor: Palette.onMoss,
      textStyle: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700),
      shape: const StadiumBorder(),
    ),
  ),
  // Icon buttons (back, bookmark, report) are 40px by default; 44 is the floor.
  iconButtonTheme: IconButtonThemeData(
    style: IconButton.styleFrom(minimumSize: const Size(44, 44)),
  ),
  textButtonTheme: TextButtonThemeData(
    style: TextButton.styleFrom(
      minimumSize: const Size(44, 44),
      foregroundColor: Palette.brickDeep,
      textStyle: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      shape: const StadiumBorder(),
    ),
  ),
  outlinedButtonTheme: OutlinedButtonThemeData(
    style: OutlinedButton.styleFrom(
      minimumSize: const Size(48, 48),
      foregroundColor: Palette.ink,
      backgroundColor: Palette.high,
      textStyle: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700),
      shape: const StadiumBorder(),
      side: const BorderSide(color: Palette.control),
    ),
  ),
  chipTheme: ChipThemeData(
    backgroundColor: Palette.chip,
    selectedColor: Palette.moss,
    // A theme labelStyle replaces Material's default instead of merging with it, so the
    // font, size and line height are restated here (as labelLarge).
    labelStyle: TextStyle(
      fontFamily: 'NotoSansTC',
      fontSize: 14,
      height: 20 / 14,
      fontWeight: FontWeight.w500,
      letterSpacing: .1,
      color: WidgetStateColor.resolveWith(
        (states) => states.contains(WidgetState.selected)
            ? Palette.onMoss
            : Palette.ink,
      ),
    ),
    secondaryLabelStyle: const TextStyle(color: Palette.onMoss),
    checkmarkColor: Palette.onMoss,
    side: BorderSide.none,
    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 10),
    shape: const StadiumBorder(),
  ),
  inputDecorationTheme: InputDecorationTheme(
    filled: true,
    fillColor: Palette.chip,
    contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
    border: _field(const BorderSide(color: Palette.control)),
    enabledBorder: _field(const BorderSide(color: Palette.control)),
    focusedBorder: _field(const BorderSide(color: Palette.moss, width: 1.5)),
    errorBorder: _field(const BorderSide(color: Palette.danger, width: 1.5)),
    focusedErrorBorder: _field(
      const BorderSide(color: Palette.danger, width: 1.5),
    ),
    hintStyle: const TextStyle(color: Palette.muted),
  ),
  snackBarTheme: const SnackBarThemeData(
    backgroundColor: Palette.ink,
    contentTextStyle: TextStyle(color: Palette.onMoss, fontSize: 14),
    behavior: SnackBarBehavior.floating,
  ),
  dialogTheme: DialogThemeData(
    backgroundColor: Palette.high,
    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
  ),
);

/// Headings (brand, page and card titles): bold sans.
TextStyle displayStyle(double size, {Color color = Palette.ink}) => TextStyle(
  fontSize: size,
  fontWeight: FontWeight.w700,
  height: 1.35,
  color: color,
);

/// Small section labels.
const labelStyle = TextStyle(
  fontSize: 13,
  fontWeight: FontWeight.w700,
  letterSpacing: .2,
  color: Palette.muted,
);

const mutedStyle = TextStyle(fontSize: 13, color: Palette.muted, height: 1.5);

// ---------- icons (line drawings from the trial, 24×24) ----------

const _iconPaths = {
  'home': '<path d="M3.6 11.3 12 4.5l8.4 6.8"/><path d="M5.7 10.1v8.6c0 .5.4.9.9.9h10.8c.5 0 .9-.4.9-.9v-8.6"/><path d="M9.8 19.6v-4.3c0-.5.4-.9.9-.9h2.6c.5 0 .9.4.9.9v4.3"/>',
  'explore': '<path d="M12 3.8a8.2 8.2 0 1 0 .1 0z"/><path d="M15.6 8.3 10.9 10.8 8.4 15.6 13.1 13.2z"/>',
  'share': '<path d="M19.2 4.7C12.9 4.4 6.3 9.6 6 17.7c7-.2 13.5-4.5 13.2-13z"/><path d="M6 18c1.2-3 3.3-5.4 6.3-6.9"/><path d="M5 19.3 8 16.3"/>',
  'me': '<circle cx="12" cy="8.5" r="3.7"/><path d="M5.4 19.6c0-4.2 3-6.5 6.6-6.5s6.6 2.3 6.6 6.5"/>',
  'bookmark': '<path d="M6.5 3.8h11v16.4l-5.5-3.9-5.5 3.9z"/>',
  'chat': '<path d="M4.5 6.8c0-1.3 1-2.3 2.3-2.3h10.4c1.3 0 2.3 1 2.3 2.3v7c0 1.3-1 2.3-2.3 2.3H11l-4.2 3.4v-3.4h0c-1.3 0-2.3-1-2.3-2.3z"/><path d="M8.6 10.3h.01M12 10.3h.01M15.4 10.3h.01" stroke-width="2.4"/>',
  'bridge': '<path d="M2.8 16.5h18.4"/><path d="M4.6 16.5c1.6-4.3 4.4-6.5 7.4-6.5s5.8 2.2 7.4 6.5"/><path d="M8 16.5v-3.6M12 16.5v-6.5M16 16.5v-3.6"/>',
  'search': '<circle cx="11" cy="11" r="7"/><path d="M20 20l-4-4"/>',
  'close': '<path d="M6 6l12 12M18 6 6 18"/>',
  'back': '<path d="M15 5l-7 7 7 7"/>',
  'chevron': '<path d="M9 6l6 6-6 6"/>',
  'spark': '<path d="M12 3.5v4M12 15.5v4M4.5 12h4M15.5 12h4M6.6 6.6l2.6 2.6M14.8 14.8l2.6 2.6M17.4 6.6l-2.6 2.6M9.2 14.8l-2.6 2.6"/>',
  'settings': '<circle cx="12" cy="12" r="3"/><path d="M19.4 15a1.7 1.7 0 0 0 .3 1.8l.1.1a2 2 0 1 1-2.8 2.8l-.1-.1a1.7 1.7 0 0 0-1.8-.3 1.7 1.7 0 0 0-1 1.5V21a2 2 0 1 1-4 0v-.1a1.7 1.7 0 0 0-1.1-1.5 1.7 1.7 0 0 0-1.8.3l-.1.1a2 2 0 1 1-2.8-2.8l.1-.1a1.7 1.7 0 0 0 .3-1.8 1.7 1.7 0 0 0-1.5-1H3a2 2 0 1 1 0-4h.1a1.7 1.7 0 0 0 1.5-1.1 1.7 1.7 0 0 0-.3-1.8l-.1-.1a2 2 0 1 1 2.8-2.8l.1.1a1.7 1.7 0 0 0 1.8.3H9a1.7 1.7 0 0 0 1-1.5V3a2 2 0 1 1 4 0v.1a1.7 1.7 0 0 0 1 1.5 1.7 1.7 0 0 0 1.8-.3l.1-.1a2 2 0 1 1 2.8 2.8l-.1.1a1.7 1.7 0 0 0-.3 1.8V9a1.7 1.7 0 0 0 1.5 1H21a2 2 0 1 1 0 4h-.1a1.7 1.7 0 0 0-1.5 1z"/>',
  'more': '<path d="M6 12h.01M12 12h.01M18 12h.01" stroke-width="2.6"/>',
  'up': '<path d="M12 5l7 8h-4v6H9v-6H5z"/>',
  'add': '<path d="M12 5v14M5 12h14"/>',
  'guide': '<path d="M7 4.5h10.5c.6 0 1 .4 1 1v13c0 .6-.4 1-1 1H7c-.8 0-1.5-.7-1.5-1.5v-12c0-.8.7-1.5 1.5-1.5z"/><path d="M9 9.2l1.2 1.2 2.3-2.4M9 14.2l1.2 1.2 2.3-2.4M14.6 9.5h1.6M14.6 14.5h1.6"/>',
};

String _hex(Color c) =>
    '#${(c.toARGB32() & 0xFFFFFF).toRadixString(16).padLeft(6, '0')}';

/// A line icon; [filled] also fills the shape (the saved bookmark).
class AppIcon extends StatelessWidget {
  const AppIcon(
    this.name, {
    super.key,
    this.size = 22,
    this.color = Palette.ink,
    this.filled = false,
    this.strokeWidth = 1.7,
  });
  final String name;
  final double size;
  final Color color;
  final bool filled;
  final double strokeWidth;
  @override
  Widget build(BuildContext context) {
    final hex = _hex(color);
    final svg =
        '<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 24 24" '
        'fill="${filled ? hex : 'none'}" stroke="$hex" stroke-width="$strokeWidth" '
        'stroke-linecap="round" stroke-linejoin="round">${_iconPaths[name] ?? ''}</svg>';
    return ExcludeSemantics(
      child: SvgPicture.string(svg, width: size, height: size),
    );
  }
}

/// The asset icons of the first design (still used by a few admin screens).
class InkIcon extends StatelessWidget {
  const InkIcon(
    this.name, {
    super.key,
    this.size = 24,
    this.color = Palette.ink,
  });
  final String name;
  final double size;
  final Color color;
  @override
  Widget build(BuildContext context) => ExcludeSemantics(
    child: SvgPicture.asset(
      'assets/icons/$name.svg',
      width: size,
      height: size,
      colorFilter: ColorFilter.mode(color, BlendMode.srcIn),
    ),
  );
}

/// The official account's mark next to "Culture Bridge": a small moss square with the
/// bridge, no text and no check mark. Screen readers hear "official account".
class OfficialSeal extends StatelessWidget {
  const OfficialSeal({super.key, this.size = 16});
  final double size;
  static const _svg =
      '<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 24 24">'
      '<rect x="1" y="1" width="22" height="22" rx="6" fill="#4C5540"/>'
      '<path d="M4.5 16.5h15M6 16.5c1.4-3.8 3.6-5.6 6-5.6s4.6 1.8 6 5.6M9 16.5v-2.6M12 16.5v-5.4M15 16.5v-2.6" '
      'fill="none" stroke="#FFFFFF" stroke-width="1.9" stroke-linecap="round" stroke-linejoin="round"/></svg>';
  @override
  Widget build(BuildContext context) => Semantics(
    label: BridgeScope.of(context).pair('官方帳號', 'Official account'),
    child: ExcludeSemantics(
      child: SvgPicture.string(_svg, width: size, height: size),
    ),
  );
}

/// A round avatar: the person's photo if they have one, else the author's initial,
/// or the team logo mark for Culture Bridge itself (no initial).
class Avatar extends StatelessWidget {
  const Avatar({super.key, this.initial, this.size = 32, this.imageUrl});
  final String? initial;
  final double size;

  /// A profile photo; the initial shows instead if it fails to load.
  final String? imageUrl;
  @override
  Widget build(BuildContext context) => ExcludeSemantics(
    child: Container(
      width: size,
      height: size,
      alignment: Alignment.center,
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        // The purple logo reads best on white; people's initials sit on pale moss.
        color: initial == null && imageUrl == null
            ? Colors.white
            : Palette.paleMoss,
        shape: BoxShape.circle,
        border: initial == null && imageUrl == null
            ? Border.all(color: Palette.edge)
            : null,
      ),
      child: imageUrl == null
          ? _fallback()
          : Image.network(
              imageUrl!,
              width: size,
              height: size,
              fit: BoxFit.cover,
              errorBuilder: (_, _, _) => _fallback(),
            ),
    ),
  );

  Widget _fallback() => initial == null
      ? Image.asset(
          'assets/images/logo-mark.png',
          width: size * .72,
          height: size * .72,
          fit: BoxFit.contain,
        )
      : Text(
          initial!,
          style: TextStyle(
            fontSize: size * .4,
            fontWeight: FontWeight.w700,
            color: Palette.moss,
            height: 1,
          ),
        );
}

// ---------- paper ----------

/// One of the hand-drawn botanical stickers from the team's asset library; decoration only.
class Sticker extends StatelessWidget {
  const Sticker(this.index, {super.key, this.size = 120});
  final int index;
  final double size;
  static const count = 5;
  @override
  Widget build(BuildContext context) => IgnorePointer(
    child: ExcludeSemantics(
      child: Image.asset(
        'assets/images/botanical-${index % count}.webp',
        width: size,
        fit: BoxFit.contain,
      ),
    ),
  );
}

class NotebookBackground extends StatelessWidget {
  const NotebookBackground({super.key, required this.child});
  final Widget child;
  @override
  Widget build(BuildContext context) =>
      CustomPaint(painter: const _GridPainter(), isComplex: true, child: child);
}

/// Warm paper with a flat 1px notebook grid every 20px.
class _GridPainter extends CustomPainter {
  const _GridPainter();
  static const step = 20.0;
  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawRect(Offset.zero & size, Paint()..color = Palette.paper);
    final line = Paint()
      ..color = Palette.grid
      ..strokeWidth = 1;
    for (double x = .5; x < size.width; x += step) {
      canvas.drawLine(Offset(x, 0), Offset(x, size.height), line);
    }
    for (double y = .5; y < size.height; y += step) {
      canvas.drawLine(Offset(0, y), Offset(size.width, y), line);
    }
  }

  @override
  bool shouldRepaint(_GridPainter old) => false;
}

/// A soft shadow under a sheet of paper.
const paperShadow = BoxDecoration(
  borderRadius: BorderRadius.all(Radius.circular(Radii.card)),
  boxShadow: [
    BoxShadow(color: Color(0x1439362E), blurRadius: 16, offset: Offset(0, 3)),
  ],
);

/// A cream card on the paper: rounded, a hairline and a soft shadow. [read] keeps it (titles
/// dim instead).
class NoteCard extends StatelessWidget {
  const NoteCard({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(16),
    this.read = false,
    this.color,
    this.borderColor,
    this.onTap,
  });
  final Widget child;
  final EdgeInsetsGeometry padding;
  final bool read;
  final Color? color;
  final Color? borderColor;

  /// Makes the whole card one tap target; buttons inside keep their own actions.
  final VoidCallback? onTap;
  @override
  Widget build(BuildContext context) => DecoratedBox(
    decoration: paperShadow,
    child: Material(
      color: color ?? (read ? Palette.readCard : Palette.high),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(Radii.card),
        side: BorderSide(
          color: borderColor ?? Palette.oat,
          width: borderColor == null ? 1 : 1.5,
        ),
      ),
      clipBehavior: Clip.antiAlias,
      child: onTap == null
          ? Padding(padding: padding, child: child)
          : InkWell(
              onTap: onTap,
              child: Padding(padding: padding, child: child),
            ),
    ),
  );
}

/// Older screens' name for a card.
class PaperCard extends StatelessWidget {
  const PaperCard({
    super.key,
    required this.child,
    this.color = Palette.high,
    this.padding = const EdgeInsets.all(20),
  });
  final Widget child;
  final Color color;
  final EdgeInsets padding;
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 8),
    child: NoteCard(color: color, padding: padding, child: child),
  );
}

/// A typewriter section label with an optional muted note after it.
class SectionLabel extends StatelessWidget {
  const SectionLabel(this.title, {super.key, this.note});
  final String title;
  final String? note;
  @override
  Widget build(BuildContext context) => Wrap(
    spacing: 8,
    runSpacing: 2,
    crossAxisAlignment: WrapCrossAlignment.end,
    children: [
      Semantics(
        header: true,
        child: Text(title.toUpperCase(), style: labelStyle),
      ),
      if (note != null) Text(note!, style: mutedStyle),
    ],
  );
}

/// Older screens' section heading.
class PaperHeading extends StatelessWidget {
  const PaperHeading(this.title, {super.key, this.badge});
  final String title;
  final String? badge;
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 14),
    child: Wrap(
      spacing: 12,
      runSpacing: 8,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        Text(title.toUpperCase(), style: labelStyle),
        if (badge != null) PaperTag(badge!),
      ],
    ),
  );
}

/// A small gray pill, e.g. a post's category.
class PaperTag extends StatelessWidget {
  const PaperTag(this.text, {super.key, this.color = Palette.chip});
  final String text;
  final Color color;
  @override
  Widget build(BuildContext context) => Container(
    decoration: BoxDecoration(
      color: color,
      borderRadius: BorderRadius.circular(Radii.pill),
    ),
    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
    child: Text(
      text,
      style: const TextStyle(fontSize: 12, height: 1.3, color: Palette.inkSoft),
    ),
  );
}

/// "#tag" in brick ink; tapping searches for it. The tap area stays 44px tall.
class TagLink extends StatelessWidget {
  const TagLink(this.tag, {super.key, this.onTap, this.large = false});
  final String tag;
  final VoidCallback? onTap;
  final bool large;
  @override
  Widget build(BuildContext context) {
    final vm = BridgeScope.of(context);
    return Semantics(
      button: onTap != null,
      label: onTap == null ? tag : vm.pair('搜尋 $tag', 'Search $tag'),
      excludeSemantics: true,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(Radii.control),
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: 44),
          child: Padding(
            padding: EdgeInsets.symmetric(horizontal: large ? 10 : 6),
            child: Center(
              widthFactor: 1,
              child: Text(
                tag,
                style: TextStyle(
                  fontSize: large ? 14 : 13,
                  color: Palette.brickDeep,
                  height: 1.2,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// A choice pill: moss when chosen, oat when not.
class NoteChip extends StatelessWidget {
  const NoteChip({
    super.key,
    required this.label,
    required this.selected,
    required this.onTap,
    this.dense = false,
  });
  final String label;
  final bool selected;
  final VoidCallback? onTap;
  final bool dense;
  @override
  Widget build(BuildContext context) => Semantics(
    button: true,
    selected: selected,
    child: Material(
      color: selected ? Palette.moss : Palette.chip,
      shape: const StadiumBorder(),
      child: InkWell(
        onTap: onTap,
        customBorder: const StadiumBorder(),
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: 44),
          child: Padding(
            padding: EdgeInsets.symmetric(horizontal: dense ? 14 : 16),
            child: Center(
              widthFactor: 1,
              child: Text(
                label,
                style: TextStyle(
                  fontSize: dense ? 13 : 14,
                  color: selected ? Palette.onMoss : Palette.ink,
                  fontWeight: selected ? FontWeight.w700 : FontWeight.w400,
                ),
              ),
            ),
          ),
        ),
      ),
    ),
  );
}

/// Long text cut to [maxLines] with 看更多 / 收起, so a page can be scanned first and
/// read in full only where the reader wants to.
class ExpandableText extends StatefulWidget {
  const ExpandableText(this.text, {super.key, this.maxLines = 3, this.style});
  final String text;
  final int maxLines;
  final TextStyle? style;
  @override
  State<ExpandableText> createState() => _ExpandableTextState();
}

class _ExpandableTextState extends State<ExpandableText> {
  bool _open = false;
  @override
  Widget build(BuildContext context) {
    final vm = BridgeScope.of(context);
    return LayoutBuilder(
      builder: (context, box) {
        final painter = TextPainter(
          text: TextSpan(
            text: widget.text,
            style: DefaultTextStyle.of(context).style.merge(widget.style),
          ),
          maxLines: widget.maxLines,
          textDirection: Directionality.of(context),
          textScaler: MediaQuery.textScalerOf(context),
        )..layout(maxWidth: box.maxWidth);
        final long = painter.didExceedMaxLines;
        painter.dispose();
        final cut = long && !_open;
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              widget.text,
              style: widget.style,
              maxLines: cut ? widget.maxLines : null,
              overflow: cut ? TextOverflow.ellipsis : null,
            ),
            if (long)
              TextButton(
                style: TextButton.styleFrom(
                  padding: EdgeInsets.zero,
                  visualDensity: VisualDensity.compact,
                ),
                onPressed: () => setState(() => _open = !_open),
                child: Text(
                  _open
                      ? vm.pair('收起', 'Show less')
                      : vm.pair('看更多', 'Show more'),
                ),
              ),
          ],
        );
      },
    );
  }
}

/// The page's own heading (Young Serif).
class PageTitle extends StatelessWidget {
  const PageTitle(this.text, {super.key, this.size = 26});
  final String text;
  final double size;
  @override
  Widget build(BuildContext context) =>
      Semantics(header: true, child: Text(text, style: displayStyle(size)));
}

/// A vertical list with even gaps, capped to a comfortable reading width.
class FlowBody extends StatelessWidget {
  const FlowBody({
    super.key,
    required this.children,
    this.maxWidth = 880,
    this.gap = 18,
  });
  final List<Widget> children;
  final double maxWidth;
  final double gap;
  @override
  Widget build(BuildContext context) => Align(
    alignment: Alignment.topCenter,
    child: ConstrainedBox(
      constraints: BoxConstraints(maxWidth: maxWidth),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (int i = 0; i < children.length; i++) ...[
            if (i > 0) SizedBox(height: gap),
            children[i],
          ],
        ],
      ),
    ),
  );
}

/// A form field with its label above the line, so stacked fields never overlap.
class LabeledField extends StatelessWidget {
  const LabeledField({
    super.key,
    required this.label,
    required this.controller,
    this.minLines = 1,
    this.hint,
  });
  final String label;
  final TextEditingController controller;
  final int minLines;
  final String? hint;
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 16),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(label, style: mutedStyle),
        TextField(
          controller: controller,
          minLines: minLines,
          maxLines: null,
          keyboardType: TextInputType.multiline,
          decoration: InputDecoration(hintText: hint),
        ),
      ],
    ),
  );
}

/// How long ago, in the reader's language ("3 小時前" / "3 h ago").
String timeAgo(BridgeViewModel vm, DateTime when, {DateTime? now}) {
  final minutes = (now ?? DateTime.now()).difference(when).inMinutes;
  if (minutes < 1) return vm.pair('剛剛', 'just now');
  if (minutes < 60) return vm.pair('$minutes 分鐘前', '$minutes min ago');
  final hours = minutes ~/ 60;
  if (hours < 24) return vm.pair('$hours 小時前', '$hours h ago');
  final days = hours ~/ 24;
  if (days < 7) return vm.pair('$days 天前', '$days d ago');
  final weeks = days ~/ 7;
  if (weeks < 9) return vm.pair('$weeks 週前', '$weeks wk ago');
  return '${when.year}-${when.month.toString().padLeft(2, '0')}-'
      '${when.day.toString().padLeft(2, '0')}';
}
