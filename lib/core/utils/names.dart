/// Name / search normalisation shared by the local duplicate pre-check and
/// the search box. Mirrors `mobile_api.dedup.normalize_name` on the server.
const Map<String, String> _arabicFold = {
  'أ': 'ا', // أ
  'إ': 'ا', // إ
  'آ': 'ا', // آ
  'ٱ': 'ا', // ٱ
  'ة': 'ه', // ة → ه
  'ى': 'ي', // ى → ي
  'ـ': '', // tatweel
};

final RegExp _diacritics = RegExp(r'[ً-ٰٟ]');
final RegExp _spaces = RegExp(r'\s+');

String normalizeName(Object? value) {
  if (value == null) return '';
  var text = value.toString();
  text = text.replaceAll(_diacritics, '');
  final buffer = StringBuffer();
  for (final rune in text.runes) {
    final ch = String.fromCharCode(rune);
    buffer.write(_arabicFold[ch] ?? ch);
  }
  return buffer.toString().replaceAll(_spaces, ' ').trim().toLowerCase();
}

String normalizeSearch(String value) => normalizeName(value);

/// Key of the three name parts, used for exact identity matching.
String normalizeNameKey(List<Object?> parts) {
  final normalized = parts.map(normalizeName).toList();
  if (normalized.any((p) => p.isEmpty)) return '';
  return normalized.join('|');
}

String joinNames(List<Object?> parts) =>
    parts.where((p) => p != null && p.toString().trim().isNotEmpty).map((p) => p.toString().trim()).join(' ');
