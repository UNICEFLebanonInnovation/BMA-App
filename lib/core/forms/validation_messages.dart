import '../../l10n/app_localizations.dart';
import 'schema_form_controller.dart';

/// Build the validator's message set from the interface language.
///
/// One builder rather than a literal at each form, because the three call
/// sites used to pass four messages each and let the rest fall back to the
/// English defaults compiled into [ValidationMessages] -- so an Arabic worker
/// who typed a digit into a name got an English "Invalid format.". A form
/// cannot now be wired up with a partial set.
///
/// The templates keep their `{max}` / `{min}` token: [ValidationMessages]
/// substitutes the real bound per field, so the string is fetched once here
/// rather than once per failing value.
ValidationMessages validationMessages(AppLocalizations l10n, String languageCode) => ValidationMessages(
      required: l10n.requiredField,
      invalidNumber: l10n.invalidNumber,
      invalidDate: l10n.invalidDate,
      invalidFormat: l10n.invalidFormat,
      confirmMismatch: l10n.confirmMismatch,
      tooLongTemplate: l10n.tooLong('{max}'),
      tooShortTemplate: l10n.tooShort('{min}'),
      invalidEmail: l10n.invalidEmail,
      invalidChoice: l10n.invalidChoice,
      valueTooSmallTemplate: l10n.valueTooSmall('{min}'),
      valueTooLargeTemplate: l10n.valueTooLarge('{max}'),
      dateInFuture: l10n.futureDate,
      dateTooEarly: l10n.dateTooEarly,
      dateTooLate: l10n.dateTooLate,
      tooManyDecimalsTemplate: l10n.tooManyDecimals('{max}'),
      languageCode: languageCode,
    );
