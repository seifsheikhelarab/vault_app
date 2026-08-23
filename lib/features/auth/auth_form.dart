import 'package:flutter/material.dart';

import '../../core/network/api_client.dart';

String? validateEmail(String? value) {
  final v = value?.trim() ?? '';
  if (v.isEmpty) return 'Enter your email';
  if (!RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$').hasMatch(v)) {
    return 'Enter a valid email';
  }
  return null;
}

String? validatePassword(String? value) {
  if (value == null || value.isEmpty) return 'Enter your password';
  if (value.length < 8) return 'Use at least 8 characters';
  return null;
}

/// Shared submit plumbing for the auth forms: one busy flag, one error
/// mapper (status codes, since auth routes have no usable error envelope),
/// one SnackBar surface.
mixin AuthFormMixin<T extends StatefulWidget> on State<T> {
  bool _busy = false;
  bool get busy => _busy;

  Future<void> runAuth(Future<Object?> Function() action) async {
    if (_busy) return;
    setState(() => _busy = true);
    String? error;
    try {
      await action();
    } on ApiException catch (e) {
      error = switch (e.statusCode) {
        401 => 'Wrong email or password.',
        429 => 'Too many attempts. Wait a minute and retry.',
        _ => 'Something went wrong (HTTP ${e.statusCode}).',
      };
    } catch (_) {
      error = 'Network error. Check your connection.';
    }
    if (!mounted) return;
    setState(() => _busy = false);
    if (error != null) {
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(error)));
    }
  }
}

/// Submit button with inline busy spinner (design: primary FilledButton,
/// no ember on auth surfaces).
class AuthSubmitButton extends StatelessWidget {
  const AuthSubmitButton({
    required this.label,
    required this.busy,
    this.onPressed,
    super.key,
  });

  final String label;
  final bool busy;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    return FilledButton(
      onPressed: busy ? null : onPressed,
      child: busy
          ? const SizedBox(
              height: 22,
              width: 22,
              child: CircularProgressIndicator(strokeWidth: 2.4),
            )
          : Text(label),
    );
  }
}
