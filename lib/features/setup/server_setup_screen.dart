import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/config/settings_controller.dart';
import '../../core/layout/app_layout.dart';
import '../../core/network/server_probe.dart';
import '../../core/theme/app_theme.dart';
import '../../core/widgets/bma_logo.dart';
import '../../l10n/app_localizations.dart';
import '../../router.dart';

/// First-run landing page: which BMA-NFE server this device talks to.
///
/// Shown before the sign-in screen until an address has been saved on the
/// device. The address can always be changed later in Settings.
class ServerSetupScreen extends ConsumerStatefulWidget {
  const ServerSetupScreen({super.key});

  @override
  ConsumerState<ServerSetupScreen> createState() => _ServerSetupScreenState();
}

class _ServerSetupScreenState extends ConsumerState<ServerSetupScreen> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _server;
  bool _testing = false;
  ServerCheck? _result;

  @override
  void initState() {
    super.initState();
    _server = TextEditingController(text: ref.read(settingsControllerProvider).serverUrl);
  }

  @override
  void dispose() {
    _server.dispose();
    super.dispose();
  }

  String? _validate(String? value, AppLocalizations l10n) {
    final raw = (value ?? '').trim();
    if (raw.isEmpty) return l10n.requiredField;
    final uri = Uri.tryParse(SettingsController.normaliseServerUrl(raw));
    if (uri == null || uri.host.isEmpty || uri.host.contains(' ')) return l10n.setupInvalidUrl;
    return null;
  }

  Future<void> _test() async {
    final l10n = AppLocalizations.of(context);
    if (_validate(_server.text, l10n) != null) {
      setState(() => _formKey.currentState!.validate());
      return;
    }
    setState(() {
      _testing = true;
      _result = null;
    });
    final result = await ref.read(serverProbeProvider).check(SettingsController.normaliseServerUrl(_server.text));
    if (!mounted) return;
    setState(() {
      _testing = false;
      _result = result;
    });
  }

  Future<void> _continue() async {
    if (!_formKey.currentState!.validate()) return;
    // Saving marks the device as set up, so the redirect stops sending the
    // user back here; the explicit go() then lands on the sign-in screen.
    await ref.read(settingsControllerProvider.notifier).setServerUrl(_server.text);
    if (!mounted) return;
    context.go(Routes.login);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final language = ref.watch(settingsControllerProvider).locale.languageCode;
    return Scaffold(
      // ONE CENTRED CARD at every width — deliberately not split into panes.
      // The cap and the glyph follow the BOX; at compact they resolve to
      // today's literals (440 / 56), which is what keeps the 412x700 + 1.3x
      // Arabic case in server_setup_test.dart free of added height.
      body: SafeArea(
        child: LayoutBuilder(builder: (context, constraints) {
          final wide = AppLayout.forWidth(constraints.maxWidth).width.atLeastMedium;
          return Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(24),
              child: ConstrainedBox(
                constraints: BoxConstraints(maxWidth: wide ? 520 : 440),
                child: Card(
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Form(
                      key: _formKey,
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          // The FIRST screen of the app: the logo is what tells
                          // the worker they opened the right one before they
                          // have any content to recognise it by.
                          BmaLogo(width: wide ? 260 : 200),
                          const SizedBox(height: 16),
                          Icon(Icons.settings_ethernet, size: wide ? 40 : 32, color: AppColors.primary),
                          const SizedBox(height: 8),
                          Text(
                            l10n.setupTitle,
                            textAlign: TextAlign.center,
                            style: Theme.of(context).textTheme.headlineSmall,
                          ),
                          const SizedBox(height: 8),
                          Text(
                            l10n.setupIntro,
                            textAlign: TextAlign.center,
                            style: const TextStyle(color: AppColors.muted),
                          ),
                          const SizedBox(height: 20),
                          SegmentedButton<String>(
                            key: const ValueKey('setup-language'),
                            segments: [
                              ButtonSegment(value: 'en', label: Text(l10n.english)),
                              ButtonSegment(value: 'ar', label: Text(l10n.arabic)),
                            ],
                            selected: {language},
                            showSelectedIcon: false,
                            onSelectionChanged: (s) =>
                                ref.read(settingsControllerProvider.notifier).setLocale(Locale(s.first)),
                          ),
                          const SizedBox(height: 20),
                          TextFormField(
                            key: const ValueKey('setup-url'),
                            controller: _server,
                            decoration: InputDecoration(labelText: l10n.serverUrl, hintText: l10n.serverUrlHint),
                            keyboardType: TextInputType.url,
                            autocorrect: false,
                            textInputAction: TextInputAction.done,
                            onChanged: (_) {
                              if (_result != null) setState(() => _result = null);
                            },
                            onFieldSubmitted: (_) => _testing ? null : _continue(),
                            validator: (v) => _validate(v, l10n),
                          ),
                          const SizedBox(height: 12),
                          OutlinedButton.icon(
                            key: const ValueKey('setup-test'),
                            onPressed: _testing ? null : _test,
                            icon: _testing
                                ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                                : const Icon(Icons.wifi_tethering),
                            label: Text(l10n.setupTestConnection),
                          ),
                          if (_result != null) ...[
                            const SizedBox(height: 12),
                            _ProbeResult(result: _result!),
                          ],
                          const SizedBox(height: 20),
                          FilledButton.icon(
                            key: const ValueKey('setup-continue'),
                            onPressed: _testing ? null : _continue,
                            icon: const Icon(Icons.arrow_forward),
                            label: Text(l10n.setupContinue),
                          ),
                          const SizedBox(height: 12),
                          Text(
                            l10n.setupChangeLater,
                            textAlign: TextAlign.center,
                            style: const TextStyle(color: AppColors.muted, fontSize: 13),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
          );
        }),
      ),
    );
  }
}

/// One line of feedback under the Test connection button.
class _ProbeResult extends StatelessWidget {
  const _ProbeResult({required this.result});

  final ServerCheck result;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final (icon, colour, message) = switch (result) {
      ServerCheck.ok => (Icons.check_circle_outline, AppColors.success, l10n.setupConnectionOk),
      ServerCheck.notBmaServer => (Icons.help_outline, AppColors.warning, l10n.setupConnectionNotBma),
      ServerCheck.unreachable => (Icons.error_outline, AppColors.danger, l10n.setupConnectionFailed),
    };
    return Row(
      key: const ValueKey('setup-result'),
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, size: 20, color: colour),
        const SizedBox(width: 8),
        Expanded(child: Text(message, style: TextStyle(color: colour))),
      ],
    );
  }
}
