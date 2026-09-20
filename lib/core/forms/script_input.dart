import 'package:flutter/services.dart';

/// The Arabic block, U+0600–U+06FF, plus the space.
///
/// This is `checkArabicOnly` from the website's `static/js/validator.js`,
/// character for character:
///
/// ```js
/// var c = ch.charCodeAt(0);
/// return !((c < 1536 || c > 1791) && ch != " ");
/// ```
///
/// 1536 and 1791 are 0x0600 and 0x06FF, so the range is the whole Arabic
/// block — Arabic-Indic digits ٠-٩ and Arabic punctuation included, which is
/// why this is expressed as a range rather than as a list of letters.
const String arabicOnlyPattern = r'^[\u0600-\u06FF ]+$';

final RegExp _arabicChar = RegExp(r'[\u0600-\u06FF ]');

bool isArabicOnly(String text) => RegExp(arabicOnlyPattern).hasMatch(text);

/// Keeps non-Arabic characters out of a field as it is typed.
///
/// The website strips them on blur, which silently empties the field if the
/// whole name was Latin — indistinguishable from a bug, and on an offline
/// device it is lost data rather than a re-typed field. Blocking the keystroke
/// instead reaches the same end state (only Arabic is ever stored) while the
/// text already on screen is never rewritten underneath the worker.
///
/// A blocked keystroke is silent on its own, so every field using this also
/// shows a hint saying the field is Arabic; and the validator still checks the
/// value, because a formatter cannot see a value that arrived from a pull.
class ArabicOnlyFormatter extends TextInputFormatter {
  const ArabicOnlyFormatter();

  @override
  TextEditingValue formatEditUpdate(TextEditingValue oldValue, TextEditingValue newValue) {
    final kept = StringBuffer();
    var removedBeforeCaret = 0;
    final caret = newValue.selection.end;
    for (var i = 0; i < newValue.text.length; i++) {
      final ch = newValue.text[i];
      if (_arabicChar.hasMatch(ch)) {
        kept.write(ch);
      } else if (i < caret) {
        removedBeforeCaret++;
      }
    }
    final text = kept.toString();
    if (text == newValue.text) return newValue;
    // Deleting a character must still work: if nothing survived and the field
    // was already empty, hand back the old value rather than fighting the IME.
    final offset = (caret - removedBeforeCaret).clamp(0, text.length);
    return TextEditingValue(
      text: text,
      selection: TextSelection.collapsed(offset: offset),
      composing: TextRange.empty,
    );
  }
}
