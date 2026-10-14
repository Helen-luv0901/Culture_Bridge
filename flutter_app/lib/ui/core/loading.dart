import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../view_models/bridge_view_model.dart';
import 'design_system.dart';

/// Shows API data once loaded; starts the load on first build, with loading and retry states.
class ResourceView<T> extends StatefulWidget {
  const ResourceView({
    super.key,
    required this.resource,
    required this.load,
    required this.builder,
  });
  final Resource<T> Function(BridgeViewModel vm) resource;
  final Future<void> Function(BridgeViewModel vm) load;
  final Widget Function(BuildContext context, T data) builder;

  @override
  State<ResourceView<T>> createState() => _ResourceViewState<T>();
}

class _ResourceViewState<T> extends State<ResourceView<T>> {
  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final vm = BridgeScope.of(context);
    if (widget.resource(vm).needsLoad) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && widget.resource(vm).needsLoad) widget.load(vm);
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final vm = BridgeScope.of(context);
    final resource = widget.resource(vm);
    final data = resource.data;
    if (data != null) return widget.builder(context, data);
    if (resource.error != null) {
      if (resource.error!.status == 404) return const MissingContent();
      return ErrorPanel(
        message: vm.errorText(resource.error),
        onRetry: () => widget.load(vm),
      );
    }
    return const LoadingNote();
  }
}

class LoadingNote extends StatelessWidget {
  const LoadingNote({super.key});
  @override
  Widget build(BuildContext context) => Semantics(
    liveRegion: true,
    child: Padding(
      padding: const EdgeInsets.symmetric(vertical: 24),
      child: Row(
        children: [
          const SizedBox(
            width: 18,
            height: 18,
            child: CircularProgressIndicator(
              strokeWidth: 2,
              color: Palette.moss,
            ),
          ),
          const SizedBox(width: 12),
          Flexible(
            child: Text(
              BridgeScope.of(context).t('loading'),
              style: const TextStyle(color: Palette.muted),
            ),
          ),
        ],
      ),
    ),
  );
}

class ErrorPanel extends StatelessWidget {
  const ErrorPanel({super.key, required this.message, this.onRetry});
  final String message;
  final VoidCallback? onRetry;
  @override
  Widget build(BuildContext context) => Semantics(
    liveRegion: true,
    child: PaperCard(
      color: Palette.ochre,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(message),
          if (onRetry != null)
            TextButton(
              onPressed: onRetry,
              child: Text(BridgeScope.of(context).t('retry')),
            ),
        ],
      ),
    ),
  );
}

class MissingContent extends StatelessWidget {
  const MissingContent({super.key});
  @override
  Widget build(BuildContext context) {
    final vm = BridgeScope.of(context);
    return FlowBody(
      children: [
        Text(
          vm.pair(
            '找不到這筆內容，請回首頁選擇。',
            'This content could not be found. Choose an item from Home.',
          ),
        ),
        TextButton(onPressed: () => context.go('/'), child: Text(vm.t('home'))),
      ],
    );
  }
}

/// True when signed in; otherwise opens the sign-in page, returning here afterwards.
bool ensureSignedIn(BuildContext context) {
  if (BridgeScope.of(context).signedIn) return true;
  final here = GoRouterState.of(context).uri.toString();
  context.push('/signin?next=${Uri.encodeComponent(here)}');
  return false;
}

String formatDate(DateTime? date) => date == null
    ? '—'
    : '${date.year}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';
