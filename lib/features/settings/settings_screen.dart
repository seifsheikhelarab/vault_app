import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:package_info_plus/package_info_plus.dart';

import '../../core/network/api_client.dart';
import '../../core/network/connectivity_provider.dart';
import '../../data/sync/sync_providers.dart';
import '../auth/auth_form.dart';
import '../auth/session_controller.dart';

final _packageInfoProvider =
    FutureProvider<PackageInfo>((_) => PackageInfo.fromPlatform());

/// Settings tab: change password (+ revoke other sessions), force resync,
/// version, sign out.
class SettingsScreen extends ConsumerStatefulWidget {
  const SettingsScreen({super.key});

  @override
  ConsumerState<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends ConsumerState<SettingsScreen> {
  final _formKey = GlobalKey<FormState>();
  final _current = TextEditingController();
  final _new = TextEditingController();
  final _confirm = TextEditingController();
  bool _revokeOtherSessions = false;

  bool _changingPassword = false;
  String? _passwordMessage;
  bool _passwordError = false;

  bool _resyncing = false;
  String? _resyncOutcome;
  bool _resyncError = false;

  @override
  void dispose() {
    _current.dispose();
    _new.dispose();
    _confirm.dispose();
    super.dispose();
  }

  bool get _online => ref.read(connectivityProvider).asData?.value ?? true;

  Future<void> _submitChangePassword() async {
    setState(() {
      _passwordMessage = null;
      _passwordError = false;
    });
    if (!_formKey.currentState!.validate()) return;
    if (!_online) {
      setState(() {
        _passwordMessage =
            "You're offline — changing your password needs a connection.";
        _passwordError = true;
      });
      return;
    }
    setState(() => _changingPassword = true);
    String? message;
    var error = false;
    try {
      await ref.read(apiClientProvider).changePassword(
            currentPassword: _current.text,
            newPassword: _new.text,
            revokeOtherSessions: _revokeOtherSessions,
          );
      message = 'Password updated.'
          '${_revokeOtherSessions ? ' Other sessions were signed out.' : ''}';
      _current.clear();
      _new.clear();
      _confirm.clear();
      setState(() => _revokeOtherSessions = false);
    } on ApiException catch (e) {
      // Better Auth bodies carry no usable envelope — status codes only.
      message = switch (e.statusCode) {
        400 || 401 => 'Current password is incorrect.',
        429 => 'Too many attempts. Wait a minute and retry.',
        _ => 'Something went wrong (HTTP ${e.statusCode}).',
      };
      error = true;
    } catch (_) {
      message = 'Network error. Check your connection.';
      error = true;
    }
    if (!mounted) return;
    setState(() {
      _changingPassword = false;
      _passwordMessage = message;
      _passwordError = error;
    });
  }

  Future<bool?> _confirmResync(BuildContext context) {
    return showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Force resync?'),
        content: const Text(
          'Clears local expenses and categories and re-downloads everything '
          'from the server. Unsaved local changes are pushed first.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Resync'),
          ),
        ],
      ),
    );
  }

  Future<void> _runResync() async {
    if (_resyncing) return;
    final confirmed = await _confirmResync(context);
    if (confirmed != true) return;

    setState(() {
      _resyncing = true;
      _resyncOutcome = null;
    });
    final online = _online;
    String outcome;
    var failed = false;
    try {
      final engine = await ref.read(syncEngineProvider.future);
      await engine.forceResync(wipeLocalData: true);
      if (online) {
        await ref.read(syncSchedulerProvider.future).then((s) => s.refresh());
        outcome = 'Local data cleared and re-download started.';
      } else {
        outcome = 'Local data cleared. The re-download needs a connection '
            'and will start automatically when you\'re back online.';
      }
    } catch (_) {
      outcome = 'Could not clear sync state. Try again.';
      failed = true;
    }
    if (!mounted) return;
    setState(() {
      _resyncing = false;
      _resyncOutcome = outcome;
      _resyncError = failed;
    });
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final online = ref.watch(connectivityProvider).asData?.value ?? true;

    return Scaffold(
      body: ListView(
        padding: const EdgeInsets.symmetric(vertical: 8),
        children: [
          _SectionHeader('Account'),
          Padding(
            padding: const EdgeInsets.fromLTRB(24, 0, 24, 8),
            child: Form(
              key: _formKey,
              autovalidateMode: AutovalidateMode.onUserInteraction,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  TextFormField(
                    controller: _current,
                    decoration:
                        const InputDecoration(labelText: 'Current password'),
                    obscureText: true,
                    textInputAction: TextInputAction.next,
                    validator: validatePassword,
                  ),
                  const SizedBox(height: 16),
                  TextFormField(
                    controller: _new,
                    decoration:
                        const InputDecoration(labelText: 'New password'),
                    obscureText: true,
                    textInputAction: TextInputAction.next,
                    validator: validatePassword,
                  ),
                  const SizedBox(height: 16),
                  TextFormField(
                    controller: _confirm,
                    decoration:
                        const InputDecoration(labelText: 'Confirm new password'),
                    obscureText: true,
                    textInputAction: TextInputAction.done,
                    validator: (value) =>
                        value == _new.text ? null : 'Passwords do not match',
                  ),
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    title: const Text('Sign out other devices'),
                    subtitle: const Text(
                        'Revokes every session except this one.'),
                    value: _revokeOtherSessions,
                    onChanged: (value) =>
                        setState(() => _revokeOtherSessions = value),
                  ),
                  const SizedBox(height: 8),
                  AuthSubmitButton(
                    label: 'Update password',
                    busy: _changingPassword,
                    onPressed: _submitChangePassword,
                  ),
                  if (!online)
                    Padding(
                      padding: const EdgeInsets.only(top: 12),
                      child: Row(
                        children: [
                          Icon(Icons.wifi_off,
                              size: 16, color: scheme.onSurfaceVariant),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              'Changing your password needs a connection.',
                              style: TextStyle(color: scheme.onSurfaceVariant),
                            ),
                          ),
                        ],
                      ),
                    ),
                  if (_passwordMessage != null)
                    Padding(
                      padding: const EdgeInsets.only(top: 12),
                      child: Text(
                        _passwordMessage!,
                        style: TextStyle(
                          color: _passwordError
                              ? scheme.error
                              : scheme.onSurfaceVariant,
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ),
          _SectionHeader('Data'),
          ListTile(
            title: const Text('Force resync'),
            subtitle: const Text(
                'Clear local data and re-download everything from the server.'),
            trailing: _resyncing
                ? const SizedBox(
                    height: 22,
                    width: 22,
                    child: CircularProgressIndicator(strokeWidth: 2.4),
                  )
                : const Icon(Icons.sync),
            onTap: _runResync,
          ),
          if (_resyncOutcome != null)
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 0, 24, 8),
              child: Text(
                _resyncOutcome!,
                style: TextStyle(
                  color: _resyncError ? scheme.error : scheme.onSurfaceVariant,
                ),
              ),
            ),
          _SectionHeader('About'),
          ListTile(
            title: const Text('Version'),
            trailing: ref.watch(_packageInfoProvider).maybeWhen(
                  data: (info) => Text(
                    '${info.version}+${info.buildNumber}',
                    style: TextStyle(color: scheme.onSurfaceVariant),
                  ),
                  orElse: () => Text(
                    '…',
                    style: TextStyle(color: scheme.onSurfaceVariant),
                  ),
                ),
          ),
          ListTile(
            title: Text(
              'Sign out',
              style: TextStyle(color: scheme.error),
            ),
            onTap: () => ref.read(sessionProvider.notifier).signOut(),
          ),
        ],
      ),
    );
  }
}

class _SectionHeader extends StatelessWidget {
  const _SectionHeader(this.title);

  final String title;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 16, 24, 8),
      child: Text(
        title.toUpperCase(),
        style: Theme.of(context)
            .textTheme
            .labelLarge
            ?.copyWith(color: Theme.of(context).colorScheme.primary),
      ),
    );
  }
}
