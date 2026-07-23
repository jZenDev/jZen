import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:zen_core/zen_core.dart';
import 'package:zen_transport/zen_transport.dart';

import '../l10n/generated/demo_localizations.dart';
import '../providers.dart';

/// The demo hub, ported from
/// ../DartZen/apps/ZenDemo/dartzen_demo_client/lib/src/screens/main_screen.dart: it pings the
/// server in both transport modes, runs the WebSocket echo, and switches language - proving the
/// dual-mode transport, the WebSocket product feature, and a localized surface from one screen.
class DemoDashboardScreen extends ConsumerStatefulWidget {
  const DemoDashboardScreen({super.key});

  @override
  ConsumerState<DemoDashboardScreen> createState() => _DemoDashboardScreenState();
}

class _DemoDashboardScreenState extends ConsumerState<DemoDashboardScreen> {
  String? _pingResult;
  ZenWebSocket? _socket;
  StreamSubscription<WebSocketMessage>? _subscription;
  String _wsStatus = 'disconnected';
  String? _wsEcho;

  @override
  void dispose() {
    _subscription?.cancel();
    unawaited(_socket?.close());
    super.dispose();
  }

  Future<void> _ping(ZenTransportFormat format) async {
    final messages = DemoLocalizations.of(context);
    final language = ref.read(localeProvider).languageCode;
    final result = await ref
        .read(demoRepositoryProvider)
        .ping(format: format, language: language);
    if (!mounted) return;
    result.fold(
      (ping) => setState(
        () => _pingResult = messages.pingResult(format.value, ping.message),
      ),
      (failure) => setState(() => _pingResult = messages.pingError(failure.message)),
    );
  }

  void _connect() {
    final socket = ref.read(demoRepositoryProvider).connectWebSocket();
    _subscription = socket.responses(WebSocketMessage.new).listen(
      (message) {
        if (mounted) setState(() => _wsEcho = message.payload);
      },
      onError: (Object _) {
        if (mounted) setState(() => _wsStatus = 'error');
      },
    );
    setState(() {
      _socket = socket;
      _wsStatus = 'connected';
      _wsEcho = null;
    });
  }

  Future<void> _disconnect() async {
    await _subscription?.cancel();
    _subscription = null;
    await _socket?.close();
    if (!mounted) return;
    setState(() {
      _socket = null;
      _wsStatus = 'disconnected';
    });
  }

  void _send() {
    _socket?.send(
      WebSocketMessage(
        type: 'message',
        payload: 'Hello from zen_demo at ${DateTime.now().toIso8601String()}',
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final messages = DemoLocalizations.of(context);
    final connected = _socket != null;

    return Scaffold(
      appBar: AppBar(
        title: Text(messages.appTitle),
        actions: [_LanguageMenu(label: messages.languageLabel)],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Text(messages.pingSection, style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            children: [
              FilledButton(
                onPressed: () => _ping(ZenTransportFormat.json),
                child: Text(messages.pingJson),
              ),
              FilledButton.tonal(
                onPressed: () => _ping(ZenTransportFormat.protobuf),
                child: Text(messages.pingProtobuf),
              ),
            ],
          ),
          if (_pingResult != null) ...[
            const SizedBox(height: 8),
            Text(_pingResult!),
          ],
          const Divider(height: 32),
          Text(messages.wsSection, style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            children: [
              FilledButton(
                onPressed: connected ? null : _connect,
                child: Text(messages.wsConnect),
              ),
              FilledButton.tonal(
                onPressed: connected ? _send : null,
                child: Text(messages.wsSend),
              ),
              OutlinedButton(
                onPressed: connected ? _disconnect : null,
                child: Text(messages.wsDisconnect),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(messages.wsStatus(_wsStatus)),
          if (_wsEcho != null) Text(messages.wsReceived(_wsEcho!)),
        ],
      ),
    );
  }
}

class _LanguageMenu extends ConsumerWidget {
  const _LanguageMenu({required this.label});

  final String label;

  /// The language each supported locale is offered under, written in that language.
  /// Endonyms are deliberately not localized, so they are the one place in the app that is
  /// not an ARB entry.
  static const Map<String, String> _endonyms = {
    ZenLocales.en: 'English',
    ZenLocales.uk: 'Українська',
  };

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final locale = ref.watch(localeProvider);
    return PopupMenuButton<Locale>(
      icon: const Icon(Icons.translate),
      tooltip: label,
      initialValue: locale,
      // Setting the locale does two things at once (ADR-007 + ADR-009): Localizations
      // re-renders this frame in the new language, and the very next request carries it as
      // Accept-Language, because ZenClient reads this same notifier per request.
      onSelected: (value) => ref.read(localeProvider.notifier).setLocale(value),
      itemBuilder: (context) => [
        for (final tag in ZenLocales.supported)
          PopupMenuItem(value: Locale(tag), child: Text(_endonyms[tag]!)),
      ],
    );
  }
}
