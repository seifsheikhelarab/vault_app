import 'package:flutter/services.dart';

/// Blocks anything that is not a valid in-progress money string: digits and
/// at most one decimal point with at most two decimals. Invalid edits
/// (paste of `"12.345"`, a second dot, letters) are dropped wholesale.
class MoneyInputFormatter extends TextInputFormatter {
  static final _inProgress = RegExp(r'^\d{0,9}(\.\d{0,2})?$');

  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) {
    if (newValue.text.isEmpty || _inProgress.hasMatch(newValue.text)) {
      return newValue;
    }
    return oldValue;
  }
}
