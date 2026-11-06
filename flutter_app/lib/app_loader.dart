import 'dart:async';

import 'package:flutter/material.dart';

import 'app.dart';
import 'data/auth_service.dart';
import 'ui/core/design_system.dart';
import 'ui/core/motion.dart';
import 'ui/view_models/bridge_view_model.dart';

/// Shows the app at once: a branded loading screen while [start] reaches the server, sets
/// up sign-in and loads the profile, then the app. A start that fails or takes longer than
/// [timeout] shows why, with a retry, instead of a blank screen.
class AppLoader extends StatefulWidget {
  const AppLoader({
    super.key,
    required this.start,
    this.onReady,
    this.timeout = const Duration(seconds: 60),
    this.initialLocation,
  });
  final Future<BridgeViewModel> Function() start;

  /// Where the app opens (the link the page was loaded with on the web); null: Home.
  final String? initialLocation;

  /// Called once with the view model the app shows (not with one given up on).
  final void Function(BridgeViewModel vm)? onReady;
  final Duration timeout;

  @override
  State<AppLoader> createState() => _AppLoaderState();
}

class _AppLoaderState extends State<AppLoader> {
  BridgeViewModel? _viewModel;
  Object? _error;

  /// Bumped on every try: a start that answers after it was given up on is not used.
  int _attempt = 0;

  @override
  void initState() {
    super.initState();
    unawaited(_run());
  }

  Future<void> _run() async {
    final attempt = ++_attempt;
    setState(() => _error = null);
    final started = widget.start();
    try {
      final vm = await started.timeout(widget.timeout);
      if (!mounted || attempt != _attempt) return vm.dispose();
      widget.onReady?.call(vm);
      setState(() => _viewModel = vm);
    } on Object catch (error) {
      if (error is TimeoutException) {
        // It may still finish; the next try makes its own.
        unawaited(started.then((vm) => vm.dispose(), onError: (_) {}));
      }
      if (!mounted || attempt != _attempt) return;
      setState(() => _error = error);
    }
  }

  @override
  Widget build(BuildContext context) {
    final vm = _viewModel;
    if (vm != null) {
      return CultureBridgeApp(
        viewModel: vm,
        initialLocation: widget.initialLocation,
      );
    }
    final error = _error;
    return MaterialApp(
      title: 'Culture Bridge',
      debugShowCheckedModeBanner: false,
      theme: bridgeTheme(),
      home: error == null
          ? const _LaunchScreen()
          : _LaunchError(error: error, onRetry: _run),
    );
  }
}

/// The brand on the notebook paper while the app starts.
class _LaunchScreen extends StatelessWidget {
  const _LaunchScreen();
  @override
  Widget build(BuildContext context) => const Scaffold(
    key: Key('launch-screen'),
    backgroundColor: Palette.paper,
    body: Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          _Mark(),
          SizedBox(height: 14),
          _Name(),
          SizedBox(height: 18),
          ThinkingDots(label: '載入中 · Loading', color: Palette.muted),
        ],
      ),
    ),
  );
}

class _Mark extends StatelessWidget {
  const _Mark();
  @override
  Widget build(BuildContext context) => Container(
    width: 64,
    height: 64,
    alignment: Alignment.center,
    decoration: const BoxDecoration(
      color: Palette.moss,
      shape: BoxShape.circle,
    ),
    child: const AppIcon(
      'bridge',
      size: 38,
      color: Palette.onMoss,
      strokeWidth: 2,
    ),
  );
}

class _Name extends StatelessWidget {
  const _Name();
  @override
  Widget build(BuildContext context) =>
      Text('Culture Bridge', style: displayStyle(24));
}

/// Why the app could not start, in both languages (the language setting isn't loaded yet).
class _LaunchError extends StatelessWidget {
  const _LaunchError({required this.error, required this.onRetry});
  final Object error;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final (zh, en) = switch (error) {
      FirebaseSetupError() => (
        '這個版本的登入設定不完整，請更新 App 或聯絡我們。',
        'Sign-in is not set up in this build. Please update the app or contact us.',
      ),
      StartupError(:final zh, :final en) => (zh, en),
      _ => (
        '暫時連不上伺服器，請檢查網路後重試。',
        "Can't reach the server right now. Check your connection and try again.",
      ),
    };
    return Scaffold(
      key: const Key('launch-error'),
      backgroundColor: Palette.paper,
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 420),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const _Mark(),
                  const SizedBox(height: 14),
                  const _Name(),
                  const SizedBox(height: 18),
                  Text(zh, textAlign: TextAlign.center),
                  const SizedBox(height: 4),
                  Text(en, textAlign: TextAlign.center, style: mutedStyle),
                  if (error is FirebaseSetupError) ...[
                    const SizedBox(height: 8),
                    Text(
                      '$error',
                      textAlign: TextAlign.center,
                      style: mutedStyle.copyWith(fontSize: 12),
                    ),
                  ],
                  const SizedBox(height: 20),
                  FilledButton(
                    key: const Key('launch-retry'),
                    onPressed: onRetry,
                    child: const Text('重試 · Retry'),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// A start-up failure with its own message for the person.
class StartupError implements Exception {
  const StartupError(this.zh, this.en, [this.cause]);
  final String zh;
  final String en;
  final Object? cause;
  @override
  String toString() => 'StartupError($en${cause == null ? '' : ': $cause'})';
}
