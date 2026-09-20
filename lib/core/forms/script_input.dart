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

final RegExp _notArabic = RegExp(r'[^\u0600-\u06FF ]');

bool isArabicOnly(String text) => RegExp(arabicOnlyPattern).hasMatch(text);

bool _isHighSurrogate(int unit) => unit >= 0xD800 && unit <= 0xDBFF;
bool _isLowSurrogate(int unit) => unit >= 0xDC00 && unit <= 0xDFFF;

/// Keeps non-Arabic characters out of a field as it is typed.
///
/// The website strips them on blur, which silently empties the field if the
/// whole name was Latin — indistinguishable from a bug, and on an offline
/// device it is lost data rather than a re-typed field. Blocking the keystroke
/// instead reaches the same end state (only Arabic is ever stored) while the
/// text already on screen is never rewritten underneath the worker.
///
/// Only what an edit ADDS is filtered. Text that was already in the field is
/// handed back exactly as it was, whatever script it is in, because a pulled
/// record legitimately holds a Latin name: twelve of the twenty-eight names in
/// a real pull are, and the form controller accepts an unchanged one on
/// purpose so a worker can fix a birth date without retyping a name they never
/// touched. Filtering the whole value would blank that name on the first
/// keystroke — including on a Backspace — which is the silent data loss this
/// class exists to prevent, not a stricter version of it.
///
/// Editing such a name is still held to the rule: the value is no longer
/// unchanged, so the validator asks for Arabic and says so.
///
/// A blocked keystroke is silent on its own, so every field using this also
/// shows a hint saying the field is Arabic; and the validator still checks the
/// value, because a formatter cannot see a value that arrived from a pull.
class ArabicOnlyFormatter extends TextInputFormatter {
  const ArabicOnlyFormatter();

  @override
  TextEditingValue formatEditUpdate(TextEditingValue oldValue, TextEditingValue newValue) {
    final before = oldValue.text;
    final after = newValue.text;

    // The edit is whatever lies between the text the two values still share at
    // each end. Everything outside it is untouched and must stay untouched.
    final shared = before.length < after.length ? before.length : after.length;
    var head = 0;
    while (head < shared && before.codeUnitAt(head) == after.codeUnitAt(head)) {
      head++;
    }
    var tail = 0;
    while (tail < shared - head &&
        before.codeUnitAt(before.length - 1 - tail) == after.codeUnitAt(after.length - 1 - tail)) {
      tail++;
    }
    // A boundary that falls between the halves of one code point would let a
    // filtered edit leave half of it behind, so move it off the pair. Both
    // halves then sit in the edit and are judged together.
    if (head > 0 && head < after.length &&
        _isLowSurrogate(after.codeUnitAt(head)) &&
        _isHighSurrogate(after.codeUnitAt(head - 1))) {
      head--;
    }
    if (tail > 0 &&
        tail < after.length &&
        _isLowSurrogate(after.codeUnitAt(after.length - tail)) &&
        _isHighSurrogate(after.codeUnitAt(after.length - tail - 1))) {
      tail--;
    }

    final inserted = after.substring(head, after.length - tail);
    final kept = inserted.replaceAll(_notArabic, '');
    // Nothing was added, or everything added is Arabic. A deletion, a caret
    // move and a legal keystroke all arrive here and pass through as they are,
    // which is what keeps deleting a Latin name working one key at a time.
    if (kept == inserted) return newValue;

    final text = after.substring(0, head) + kept + after.substring(after.length - tail);
    return TextEditingValue(
      text: text,
      // After the characters that survived, which is where the worker was
      // typing. The caret never jumps to the end of a name they are editing.
      selection: TextSelection.collapsed(offset: head + kept.length),
      composing: TextRange.empty,
    );
  }
}
