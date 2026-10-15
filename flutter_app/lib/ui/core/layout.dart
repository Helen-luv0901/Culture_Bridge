import 'package:flutter/widgets.dart';

/// The three layouts of the redesign, chosen by window width (not device or orientation).
enum AppLayout {
  /// Bottom tab bar; the assistant opens as a near-full-height panel.
  phone,

  /// iPad portrait (~820): a 76px icon-only sidebar.
  tablet,

  /// iPad landscape and desktop (≥1180): a 232px sidebar and search in the header.
  web;

  static const tabletMin = 768.0;
  static const webMin = 1180.0;

  static AppLayout forWidth(double width) => width >= webMin
      ? web
      : width >= tabletMin
      ? tablet
      : phone;

  static AppLayout of(BuildContext context) =>
      forWidth(MediaQuery.sizeOf(context).width);
}
