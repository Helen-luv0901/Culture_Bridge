import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import 'api_client.dart';

/// Sends errors the app didn't handle to the server log (`POST /api/client-errors`), so a
/// crash on someone's phone shows up in Cloud Logging instead of nowhere.
class ErrorReporter {
  ErrorReporter(this.api, {this.limit = 20});

  final ApiClient api;

  /// Reports per app session; a broken screen that rebuilds shouldn't send hundreds.
  final int limit;
  int _sent = 0;

  /// Catches framework errors, uncaught async errors, and (in release builds) replaces the
  /// grey error box with a quiet placeholder.
  void install() {
    final previous = FlutterError.onError;
    FlutterError.onError = (details) {
      previous?.call(details);
      unawaited(report(details.exception, details.stack));
    };
    PlatformDispatcher.instance.onError = (error, stack) {
      debugPrint('Uncaught error: $error');
      unawaited(report(error, stack));
      return true;
    };
    if (kReleaseMode) ErrorWidget.builder = (_) => const _BrokenPiece();
  }

  Future<void> report(Object error, StackTrace? stack) async {
    if (_sent >= limit) return;
    _sent++;
    try {
      await api.post('/client-errors', {
        'message': _clip('$error', 1000),
        'stack': ?(stack == null ? null : _clip('$stack', 4000)),
        'route': _clip(Uri.base.path, 300),
        'platform': kIsWeb ? 'web' : defaultTargetPlatform.name,
      });
    } on Exception {
      // Offline or the server is down: the error stays in the device log only.
    }
  }

  static String _clip(String text, int max) =>
      text.length <= max ? text : text.substring(0, max);
}

/// Shown in place of a widget that failed to build, in release builds.
class _BrokenPiece extends StatelessWidget {
  const _BrokenPiece();

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.all(12),
    child: Text(
      '這裡顯示不出來 · This part could not be shown',
      textAlign: TextAlign.center,
      style: Theme.of(context).textTheme.bodySmall,
    ),
  );
}
