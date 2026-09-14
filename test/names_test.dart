import 'package:bma_app/core/utils/names.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('normalizeName', () {
    test('lower-cases, trims and collapses whitespace', () {
      expect(normalizeName('  Mohamad   AHMAD '), 'mohamad ahmad');
    });

    test('folds Arabic alef, taa marbuta and alef maqsura variants', () {
      expect(normalizeName('أحمد'), normalizeName('احمد'));
      expect(normalizeName('فاطمة'), normalizeName('فاطمه'));
      expect(normalizeName('مصطفى'), normalizeName('مصطفي'));
    });

    test('removes diacritics and tatweel', () {
      expect(normalizeName('مُحَمَّد'), 'محمد');
      expect(normalizeName('محـــمد'), 'محمد');
    });
  });

  test('normalizeNameKey is empty when any part is missing', () {
    expect(normalizeNameKey(['Mohamad', '', 'Sayed']), '');
    expect(normalizeNameKey(['Mohamad', 'Ahmad', 'Sayed']), 'mohamad|ahmad|sayed');
  });

  test('joinNames skips blanks', () {
    expect(joinNames(['Mohamad', null, ' ', 'Sayed']), 'Mohamad Sayed');
  });
}
