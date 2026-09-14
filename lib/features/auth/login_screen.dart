import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/auth/auth_controller.dart';
import '../../core/config/settings_controller.dart';
import '../../core/db/providers.dart';
import '../../core/db/reference_dao.dart';
import '../../core/network/api_exception.dart';
import '../../core/sync/connectivity_service.dart';
import '../../core/sync/sync_engine.dart';
import '../../core/theme/app_theme.dart';
import '../../l10n/app_localizations.dart';

class LoginScreen extends ConsumerStatefulWidget {
  const LoginScreen({super.key});

  @override
  ConsumerState<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends ConsumerState<LoginScreen> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _server;
  final _username = TextEditingController();
  final _password = TextEditingController();
  bool _busy = false;
  String? _status;
  String? _error;

  @override
  void initState() {
    super.initState();
    _server = TextEditingController(text: ref.read(settingsControllerProvider).serverUrl);
  }

  @override
  void dispose() {
    _server.dispose();
    _username.dispose();
    _password.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final l10n = AppLocalizations.of(context);
    if (!_formKey.currentState!.validate()) return;
    setState(() {
      _busy = true;
      _error = null;
      _status = l10n.signingIn;
    });
    try {
      await ref.read(settingsControllerProvider.notifier).setServerUrl(_server.text);
      await ref.read(authControllerProvider.notifier).login(_username.text, _password.text);
      final auth = ref.read(authControllerProvider);
      final hasBootstrap = await ref.read(referenceDaoProvider).hasBootstrap;
      if (!auth.offline && !hasBootstrap) {
        setState(() => _status = l10n.loadingReference);
        final engine = ref.read(syncEngineProvider.notifier);
        await engine.bootstrap();
        await engine.pull(full: true);
      }
      bumpDataVersion(ref);
    } on ApiException catch (e) {
      setState(() {
        _error = switch (e.kind) {
          ApiErrorKind.unauthorized => l10n.invalidCredentials,
          ApiErrorKind.network => '${l10n.networkError}\n${l10n.offlineLoginHint}',
          _ => l10n.serverError(e.message),
        };
      });
    } catch (e) {
      setState(() => _error = l10n.loginFailed(e.toString()));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final online = ref.watch(isOnlineProvider);
    return Scaffold(
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 440),
            child: Card(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Form(
                  key: _formKey,
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      const Icon(Icons.school, size: 56, color: AppColors.primary),
                      const SizedBox(height: 8),
                      Text(l10n.appTitle,
                          textAlign: TextAlign.center, style: Theme.of(context).textTheme.headlineSmall),
                      const SizedBox(height: 4),
                      Text('BMA-NFE', textAlign: TextAlign.center,
                          style: const TextStyle(color: AppColors.muted)),
                      const SizedBox(height: 24),
                      TextFormField(
                        controller: _server,
                        decoration: InputDecoration(labelText: l10n.serverUrl, hintText: l10n.serverUrlHint),
                        keyboardType: TextInputType.url,
                        autocorrect: false,
                        validator: (v) => (v == null || v.trim().isEmpty) ? l10n.requiredField : null,
                      ),
                      const SizedBox(height: 12),
                      TextFormField(
                        controller: _username,
                        decoration: InputDecoration(labelText: l10n.username),
                        autocorrect: false,
                        textInputAction: TextInputAction.next,
                        validator: (v) => (v == null || v.trim().isEmpty) ? l10n.requiredField : null,
                      ),
                      const SizedBox(height: 12),
                      TextFormField(
                        controller: _password,
                        decoration: InputDecoration(labelText: l10n.password),
                        obscureText: true,
                        textInputAction: TextInputAction.done,
                        onFieldSubmitted: (_) => _busy ? null : _submit(),
                        validator: (v) => (v == null || v.isEmpty) ? l10n.requiredField : null,
                      ),
                      const SizedBox(height: 16),
                      if (!online)
                        Padding(
                          padding: const EdgeInsets.only(bottom: 12),
                          child: Text(l10n.offlineLoginHint,
                              style: const TextStyle(color: AppColors.warning), textAlign: TextAlign.center),
                        ),
                      if (_error != null)
                        Padding(
                          padding: const EdgeInsets.only(bottom: 12),
                          child: Text(_error!, style: const TextStyle(color: AppColors.danger)),
                        ),
                      FilledButton(
                        onPressed: _busy ? null : _submit,
                        child: _busy
                            ? Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                                const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2)),
                                const SizedBox(width: 12),
                                Text(_status ?? l10n.signingIn),
                              ])
                            : Text(l10n.signIn),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
