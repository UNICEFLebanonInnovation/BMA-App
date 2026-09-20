import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:intl/intl.dart' as intl;

import 'app_localizations_ar.dart';
import 'app_localizations_en.dart';

// ignore_for_file: type=lint

/// Callers can lookup localized strings with an instance of AppLocalizations
/// returned by `AppLocalizations.of(context)`.
///
/// Applications need to include `AppLocalizations.delegate()` in their app's
/// `localizationDelegates` list, and the locales they support in the app's
/// `supportedLocales` list. For example:
///
/// ```dart
/// import 'l10n/app_localizations.dart';
///
/// return MaterialApp(
///   localizationsDelegates: AppLocalizations.localizationsDelegates,
///   supportedLocales: AppLocalizations.supportedLocales,
///   home: MyApplicationHome(),
/// );
/// ```
///
/// ## Update pubspec.yaml
///
/// Please make sure to update your pubspec.yaml to include the following
/// packages:
///
/// ```yaml
/// dependencies:
///   # Internationalization support.
///   flutter_localizations:
///     sdk: flutter
///   intl: any # Use the pinned version from flutter_localizations
///
///   # Rest of dependencies
/// ```
///
/// ## iOS Applications
///
/// iOS applications define key application metadata, including supported
/// locales, in an Info.plist file that is built into the application bundle.
/// To configure the locales supported by your app, you’ll need to edit this
/// file.
///
/// First, open your project’s ios/Runner.xcworkspace Xcode workspace file.
/// Then, in the Project Navigator, open the Info.plist file under the Runner
/// project’s Runner folder.
///
/// Next, select the Information Property List item, select Add Item from the
/// Editor menu, then select Localizations from the pop-up menu.
///
/// Select and expand the newly-created Localizations item then, for each
/// locale your application supports, add a new item and select the locale
/// you wish to add from the pop-up menu in the Value field. This list should
/// be consistent with the languages listed in the AppLocalizations.supportedLocales
/// property.
abstract class AppLocalizations {
  AppLocalizations(String locale)
    : localeName = intl.Intl.canonicalizedLocale(locale.toString());

  final String localeName;

  static AppLocalizations of(BuildContext context) {
    return Localizations.of<AppLocalizations>(context, AppLocalizations)!;
  }

  static const LocalizationsDelegate<AppLocalizations> delegate =
      _AppLocalizationsDelegate();

  /// A list of this localizations delegate along with the default localizations
  /// delegates.
  ///
  /// Returns a list of localizations delegates containing this delegate along with
  /// GlobalMaterialLocalizations.delegate, GlobalCupertinoLocalizations.delegate,
  /// and GlobalWidgetsLocalizations.delegate.
  ///
  /// Additional delegates can be added by appending to this list in
  /// MaterialApp. This list does not have to be used at all if a custom list
  /// of delegates is preferred or required.
  static const List<LocalizationsDelegate<dynamic>> localizationsDelegates =
      <LocalizationsDelegate<dynamic>>[
        delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
      ];

  /// A list of this localizations delegate's supported locales.
  static const List<Locale> supportedLocales = <Locale>[
    Locale('ar'),
    Locale('en'),
  ];

  /// No description provided for @appTitle.
  ///
  /// In en, this message translates to:
  /// **'BMA Mobile'**
  String get appTitle;

  /// No description provided for @login.
  ///
  /// In en, this message translates to:
  /// **'Login'**
  String get login;

  /// No description provided for @logout.
  ///
  /// In en, this message translates to:
  /// **'Logout'**
  String get logout;

  /// No description provided for @username.
  ///
  /// In en, this message translates to:
  /// **'Username'**
  String get username;

  /// No description provided for @password.
  ///
  /// In en, this message translates to:
  /// **'Password'**
  String get password;

  /// No description provided for @serverUrl.
  ///
  /// In en, this message translates to:
  /// **'Server URL'**
  String get serverUrl;

  /// No description provided for @serverUrlHint.
  ///
  /// In en, this message translates to:
  /// **'https://bma.example.org'**
  String get serverUrlHint;

  /// No description provided for @signIn.
  ///
  /// In en, this message translates to:
  /// **'Sign in'**
  String get signIn;

  /// No description provided for @signingIn.
  ///
  /// In en, this message translates to:
  /// **'Signing in…'**
  String get signingIn;

  /// No description provided for @loginFailed.
  ///
  /// In en, this message translates to:
  /// **'Login failed: {reason}'**
  String loginFailed(String reason);

  /// No description provided for @offlineLoginHint.
  ///
  /// In en, this message translates to:
  /// **'No connection. Use the last account that signed in on this device.'**
  String get offlineLoginHint;

  /// No description provided for @invalidCredentials.
  ///
  /// In en, this message translates to:
  /// **'Invalid username or password.'**
  String get invalidCredentials;

  /// No description provided for @home.
  ///
  /// In en, this message translates to:
  /// **'Home'**
  String get home;

  /// No description provided for @dashboard.
  ///
  /// In en, this message translates to:
  /// **'Dashboard'**
  String get dashboard;

  /// No description provided for @registrations.
  ///
  /// In en, this message translates to:
  /// **'Registrations'**
  String get registrations;

  /// No description provided for @beneficiaries.
  ///
  /// In en, this message translates to:
  /// **'Beneficiaries'**
  String get beneficiaries;

  /// No description provided for @attendance.
  ///
  /// In en, this message translates to:
  /// **'Attendance'**
  String get attendance;

  /// No description provided for @teachers.
  ///
  /// In en, this message translates to:
  /// **'Teachers'**
  String get teachers;

  /// No description provided for @teacherAttendance.
  ///
  /// In en, this message translates to:
  /// **'Teacher attendance'**
  String get teacherAttendance;

  /// No description provided for @sync.
  ///
  /// In en, this message translates to:
  /// **'Sync'**
  String get sync;

  /// No description provided for @syncCenter.
  ///
  /// In en, this message translates to:
  /// **'Sync centre'**
  String get syncCenter;

  /// No description provided for @settings.
  ///
  /// In en, this message translates to:
  /// **'Settings'**
  String get settings;

  /// No description provided for @language.
  ///
  /// In en, this message translates to:
  /// **'Language'**
  String get language;

  /// No description provided for @english.
  ///
  /// In en, this message translates to:
  /// **'English'**
  String get english;

  /// No description provided for @arabic.
  ///
  /// In en, this message translates to:
  /// **'Arabic'**
  String get arabic;

  /// No description provided for @mscc.
  ///
  /// In en, this message translates to:
  /// **'NFE'**
  String get mscc;

  /// No description provided for @alp.
  ///
  /// In en, this message translates to:
  /// **'ALP schools'**
  String get alp;

  /// No description provided for @clm.
  ///
  /// In en, this message translates to:
  /// **'CLM Bridging'**
  String get clm;

  /// No description provided for @registerNew.
  ///
  /// In en, this message translates to:
  /// **'Register new'**
  String get registerNew;

  /// No description provided for @search.
  ///
  /// In en, this message translates to:
  /// **'Search'**
  String get search;

  /// No description provided for @searchHint.
  ///
  /// In en, this message translates to:
  /// **'Name, ID number or record number'**
  String get searchHint;

  /// No description provided for @noResults.
  ///
  /// In en, this message translates to:
  /// **'No records found.'**
  String get noResults;

  /// No description provided for @pending.
  ///
  /// In en, this message translates to:
  /// **'Pending'**
  String get pending;

  /// No description provided for @synced.
  ///
  /// In en, this message translates to:
  /// **'Synced'**
  String get synced;

  /// No description provided for @pushing.
  ///
  /// In en, this message translates to:
  /// **'Pushing'**
  String get pushing;

  /// No description provided for @duplicate.
  ///
  /// In en, this message translates to:
  /// **'Duplicate'**
  String get duplicate;

  /// No description provided for @conflict.
  ///
  /// In en, this message translates to:
  /// **'Conflict'**
  String get conflict;

  /// No description provided for @error.
  ///
  /// In en, this message translates to:
  /// **'Error'**
  String get error;

  /// No description provided for @discarded.
  ///
  /// In en, this message translates to:
  /// **'Discarded'**
  String get discarded;

  /// No description provided for @pendingChanges.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =0{No pending changes} =1{1 pending change} other{{count} pending changes}}'**
  String pendingChanges(int count);

  /// No description provided for @pushNow.
  ///
  /// In en, this message translates to:
  /// **'Push changes'**
  String get pushNow;

  /// No description provided for @pullNow.
  ///
  /// In en, this message translates to:
  /// **'Download updates'**
  String get pullNow;

  /// No description provided for @fullRefresh.
  ///
  /// In en, this message translates to:
  /// **'Full refresh (reference data + records)'**
  String get fullRefresh;

  /// No description provided for @lastPull.
  ///
  /// In en, this message translates to:
  /// **'Last download: {time}'**
  String lastPull(String time);

  /// No description provided for @never.
  ///
  /// In en, this message translates to:
  /// **'never'**
  String get never;

  /// No description provided for @online.
  ///
  /// In en, this message translates to:
  /// **'Online'**
  String get online;

  /// No description provided for @offline.
  ///
  /// In en, this message translates to:
  /// **'Offline'**
  String get offline;

  /// No description provided for @offlineBanner.
  ///
  /// In en, this message translates to:
  /// **'You are offline. Work is saved on this device and pushed later.'**
  String get offlineBanner;

  /// No description provided for @pushReport.
  ///
  /// In en, this message translates to:
  /// **'Push report'**
  String get pushReport;

  /// No description provided for @syncHistory.
  ///
  /// In en, this message translates to:
  /// **'Sync history'**
  String get syncHistory;

  /// No description provided for @summaryCreated.
  ///
  /// In en, this message translates to:
  /// **'Created'**
  String get summaryCreated;

  /// No description provided for @summaryUpdated.
  ///
  /// In en, this message translates to:
  /// **'Updated'**
  String get summaryUpdated;

  /// No description provided for @summaryMerged.
  ///
  /// In en, this message translates to:
  /// **'Merged'**
  String get summaryMerged;

  /// No description provided for @summaryLinked.
  ///
  /// In en, this message translates to:
  /// **'Linked'**
  String get summaryLinked;

  /// No description provided for @summaryDuplicates.
  ///
  /// In en, this message translates to:
  /// **'Duplicates'**
  String get summaryDuplicates;

  /// No description provided for @summaryConflicts.
  ///
  /// In en, this message translates to:
  /// **'Conflicts'**
  String get summaryConflicts;

  /// No description provided for @summaryErrors.
  ///
  /// In en, this message translates to:
  /// **'Errors'**
  String get summaryErrors;

  /// No description provided for @summarySkipped.
  ///
  /// In en, this message translates to:
  /// **'Skipped'**
  String get summarySkipped;

  /// No description provided for @summaryDiscarded.
  ///
  /// In en, this message translates to:
  /// **'Discarded'**
  String get summaryDiscarded;

  /// No description provided for @resolveDuplicate.
  ///
  /// In en, this message translates to:
  /// **'Resolve duplicate'**
  String get resolveDuplicate;

  /// No description provided for @duplicateExplanation.
  ///
  /// In en, this message translates to:
  /// **'The server found existing records matching this child. Choose what to do.'**
  String get duplicateExplanation;

  /// No description provided for @mergeIntoExisting.
  ///
  /// In en, this message translates to:
  /// **'Merge into existing record'**
  String get mergeIntoExisting;

  /// No description provided for @mergeExplanation.
  ///
  /// In en, this message translates to:
  /// **'Copy the values collected offline onto the selected existing registration.'**
  String get mergeExplanation;

  /// No description provided for @linkExistingChild.
  ///
  /// In en, this message translates to:
  /// **'Same child, new enrolment'**
  String get linkExistingChild;

  /// No description provided for @linkExplanation.
  ///
  /// In en, this message translates to:
  /// **'Create the new registration for the existing child without creating a new child.'**
  String get linkExplanation;

  /// No description provided for @createAnyway.
  ///
  /// In en, this message translates to:
  /// **'Create anyway (different person)'**
  String get createAnyway;

  /// No description provided for @discardLocal.
  ///
  /// In en, this message translates to:
  /// **'Discard my offline record'**
  String get discardLocal;

  /// No description provided for @overwriteServer.
  ///
  /// In en, this message translates to:
  /// **'Overwrite server version'**
  String get overwriteServer;

  /// No description provided for @keepServer.
  ///
  /// In en, this message translates to:
  /// **'Keep server version'**
  String get keepServer;

  /// No description provided for @resolveConflict.
  ///
  /// In en, this message translates to:
  /// **'Resolve conflict'**
  String get resolveConflict;

  /// No description provided for @conflictExplanation.
  ///
  /// In en, this message translates to:
  /// **'This record was changed on the server after you edited it offline.'**
  String get conflictExplanation;

  /// No description provided for @localVersion.
  ///
  /// In en, this message translates to:
  /// **'Your version'**
  String get localVersion;

  /// No description provided for @serverVersion.
  ///
  /// In en, this message translates to:
  /// **'Server version'**
  String get serverVersion;

  /// No description provided for @apply.
  ///
  /// In en, this message translates to:
  /// **'Apply'**
  String get apply;

  /// No description provided for @cancel.
  ///
  /// In en, this message translates to:
  /// **'Cancel'**
  String get cancel;

  /// No description provided for @save.
  ///
  /// In en, this message translates to:
  /// **'Save'**
  String get save;

  /// No description provided for @saveDraft.
  ///
  /// In en, this message translates to:
  /// **'Save locally'**
  String get saveDraft;

  /// No description provided for @next.
  ///
  /// In en, this message translates to:
  /// **'Next'**
  String get next;

  /// No description provided for @back.
  ///
  /// In en, this message translates to:
  /// **'Back'**
  String get back;

  /// No description provided for @submit.
  ///
  /// In en, this message translates to:
  /// **'Submit'**
  String get submit;

  /// No description provided for @confirm.
  ///
  /// In en, this message translates to:
  /// **'Confirm'**
  String get confirm;

  /// No description provided for @delete.
  ///
  /// In en, this message translates to:
  /// **'Delete'**
  String get delete;

  /// No description provided for @edit.
  ///
  /// In en, this message translates to:
  /// **'Edit'**
  String get edit;

  /// No description provided for @close.
  ///
  /// In en, this message translates to:
  /// **'Close'**
  String get close;

  /// No description provided for @retry.
  ///
  /// In en, this message translates to:
  /// **'Retry'**
  String get retry;

  /// No description provided for @requiredField.
  ///
  /// In en, this message translates to:
  /// **'This field is required.'**
  String get requiredField;

  /// No description provided for @invalidNumber.
  ///
  /// In en, this message translates to:
  /// **'Enter a valid number.'**
  String get invalidNumber;

  /// No description provided for @invalidDate.
  ///
  /// In en, this message translates to:
  /// **'Enter a valid date (YYYY-MM-DD).'**
  String get invalidDate;

  /// No description provided for @futureDate.
  ///
  /// In en, this message translates to:
  /// **'Date cannot be in the future.'**
  String get futureDate;

  /// No description provided for @confirmMismatch.
  ///
  /// In en, this message translates to:
  /// **'Values do not match.'**
  String get confirmMismatch;

  /// No description provided for @arabicOnlyHint.
  ///
  /// In en, this message translates to:
  /// **'Arabic only'**
  String get arabicOnlyHint;

  /// No description provided for @attendanceRowsNeedReason.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{1 child still needs a reason for absence.} other{{count} children still need a reason for absence.}}'**
  String attendanceRowsNeedReason(int count);

  /// No description provided for @tooLong.
  ///
  /// In en, this message translates to:
  /// **'Maximum {max} characters.'**
  String tooLong(String max);

  /// No description provided for @tooShort.
  ///
  /// In en, this message translates to:
  /// **'At least {min} characters.'**
  String tooShort(String min);

  /// No description provided for @invalidFormat.
  ///
  /// In en, this message translates to:
  /// **'Invalid format.'**
  String get invalidFormat;

  /// No description provided for @invalidEmail.
  ///
  /// In en, this message translates to:
  /// **'Enter a valid email address.'**
  String get invalidEmail;

  /// No description provided for @invalidChoice.
  ///
  /// In en, this message translates to:
  /// **'Choose one of the listed options.'**
  String get invalidChoice;

  /// No description provided for @valueTooSmall.
  ///
  /// In en, this message translates to:
  /// **'Must be {min} or more.'**
  String valueTooSmall(String min);

  /// No description provided for @valueTooLarge.
  ///
  /// In en, this message translates to:
  /// **'Must be {max} or less.'**
  String valueTooLarge(String max);

  /// No description provided for @dateTooEarly.
  ///
  /// In en, this message translates to:
  /// **'The date is too early.'**
  String get dateTooEarly;

  /// No description provided for @dateTooLate.
  ///
  /// In en, this message translates to:
  /// **'The date is too late.'**
  String get dateTooLate;

  /// No description provided for @tooManyDecimals.
  ///
  /// In en, this message translates to:
  /// **'At most {max} decimal places.'**
  String tooManyDecimals(String max);

  /// No description provided for @stepIdentity.
  ///
  /// In en, this message translates to:
  /// **'Identity'**
  String get stepIdentity;

  /// No description provided for @stepCaregivers.
  ///
  /// In en, this message translates to:
  /// **'Caregivers & household'**
  String get stepCaregivers;

  /// No description provided for @stepReview.
  ///
  /// In en, this message translates to:
  /// **'Review & confirm'**
  String get stepReview;

  /// No description provided for @possibleDuplicates.
  ///
  /// In en, this message translates to:
  /// **'Possible duplicates on this device'**
  String get possibleDuplicates;

  /// No description provided for @possibleDuplicatesHint.
  ///
  /// In en, this message translates to:
  /// **'A record with the same name, birth date and gender already exists locally. Continue only if this is a different child.'**
  String get possibleDuplicatesHint;

  /// No description provided for @reviewHint.
  ///
  /// In en, this message translates to:
  /// **'Check the values below, then submit. The record is stored on this device and verified by the server on the next push.'**
  String get reviewHint;

  /// No description provided for @profile.
  ///
  /// In en, this message translates to:
  /// **'Profile'**
  String get profile;

  /// No description provided for @info.
  ///
  /// In en, this message translates to:
  /// **'Information'**
  String get info;

  /// No description provided for @services.
  ///
  /// In en, this message translates to:
  /// **'Services'**
  String get services;

  /// No description provided for @educationHistory.
  ///
  /// In en, this message translates to:
  /// **'Education history'**
  String get educationHistory;

  /// No description provided for @addService.
  ///
  /// In en, this message translates to:
  /// **'Add service'**
  String get addService;

  /// No description provided for @newRound.
  ///
  /// In en, this message translates to:
  /// **'New round'**
  String get newRound;

  /// No description provided for @noServices.
  ///
  /// In en, this message translates to:
  /// **'No services recorded yet.'**
  String get noServices;

  /// No description provided for @markDeleted.
  ///
  /// In en, this message translates to:
  /// **'Mark as deleted'**
  String get markDeleted;

  /// No description provided for @selectCenter.
  ///
  /// In en, this message translates to:
  /// **'Centre'**
  String get selectCenter;

  /// No description provided for @selectSchool.
  ///
  /// In en, this message translates to:
  /// **'School'**
  String get selectSchool;

  /// No description provided for @selectRound.
  ///
  /// In en, this message translates to:
  /// **'Round'**
  String get selectRound;

  /// No description provided for @selectProgram.
  ///
  /// In en, this message translates to:
  /// **'Programme'**
  String get selectProgram;

  /// No description provided for @selectSection.
  ///
  /// In en, this message translates to:
  /// **'Section'**
  String get selectSection;

  /// No description provided for @selectDate.
  ///
  /// In en, this message translates to:
  /// **'Date'**
  String get selectDate;

  /// No description provided for @dayOff.
  ///
  /// In en, this message translates to:
  /// **'Day off'**
  String get dayOff;

  /// No description provided for @closeReason.
  ///
  /// In en, this message translates to:
  /// **'Close reason'**
  String get closeReason;

  /// No description provided for @present.
  ///
  /// In en, this message translates to:
  /// **'Present'**
  String get present;

  /// No description provided for @absent.
  ///
  /// In en, this message translates to:
  /// **'Absent'**
  String get absent;

  /// No description provided for @absenceReason.
  ///
  /// In en, this message translates to:
  /// **'Absence reason'**
  String get absenceReason;

  /// No description provided for @absenceReasonOther.
  ///
  /// In en, this message translates to:
  /// **'Other reason'**
  String get absenceReasonOther;

  /// No description provided for @markAllPresent.
  ///
  /// In en, this message translates to:
  /// **'Mark all present'**
  String get markAllPresent;

  /// No description provided for @loadChildren.
  ///
  /// In en, this message translates to:
  /// **'Load children'**
  String get loadChildren;

  /// No description provided for @noChildrenForSelection.
  ///
  /// In en, this message translates to:
  /// **'No enrolled children for this selection.'**
  String get noChildrenForSelection;

  /// No description provided for @attendanceSaved.
  ///
  /// In en, this message translates to:
  /// **'Attendance saved on this device.'**
  String get attendanceSaved;

  /// No description provided for @childMonth.
  ///
  /// In en, this message translates to:
  /// **'Monthly attendance'**
  String get childMonth;

  /// No description provided for @colName.
  ///
  /// In en, this message translates to:
  /// **'Name'**
  String get colName;

  /// No description provided for @colMother.
  ///
  /// In en, this message translates to:
  /// **'Mother'**
  String get colMother;

  /// No description provided for @colBirthday.
  ///
  /// In en, this message translates to:
  /// **'Birth date'**
  String get colBirthday;

  /// No description provided for @colAttendance.
  ///
  /// In en, this message translates to:
  /// **'Attendance'**
  String get colAttendance;

  /// No description provided for @colReason.
  ///
  /// In en, this message translates to:
  /// **'Reason'**
  String get colReason;

  /// No description provided for @notMarked.
  ///
  /// In en, this message translates to:
  /// **'Not marked'**
  String get notMarked;

  /// No description provided for @sessionLabel.
  ///
  /// In en, this message translates to:
  /// **'Session'**
  String get sessionLabel;

  /// No description provided for @rosterLabel.
  ///
  /// In en, this message translates to:
  /// **'Roster'**
  String get rosterLabel;

  /// No description provided for @noSheetForDay.
  ///
  /// In en, this message translates to:
  /// **'No sheet'**
  String get noSheetForDay;

  /// No description provided for @attended.
  ///
  /// In en, this message translates to:
  /// **'Attended'**
  String get attended;

  /// No description provided for @totalRegistrations.
  ///
  /// In en, this message translates to:
  /// **'Registrations'**
  String get totalRegistrations;

  /// No description provided for @byGender.
  ///
  /// In en, this message translates to:
  /// **'By gender'**
  String get byGender;

  /// No description provided for @byNationality.
  ///
  /// In en, this message translates to:
  /// **'By nationality'**
  String get byNationality;

  /// No description provided for @byAgeGroup.
  ///
  /// In en, this message translates to:
  /// **'By age group'**
  String get byAgeGroup;

  /// No description provided for @attendanceRate.
  ///
  /// In en, this message translates to:
  /// **'Attendance rate (30 days)'**
  String get attendanceRate;

  /// No description provided for @servicesDelivered.
  ///
  /// In en, this message translates to:
  /// **'Services delivered'**
  String get servicesDelivered;

  /// No description provided for @kpiPendingPush.
  ///
  /// In en, this message translates to:
  /// **'Waiting to push'**
  String get kpiPendingPush;

  /// No description provided for @kpiDuplicates.
  ///
  /// In en, this message translates to:
  /// **'Need resolution'**
  String get kpiDuplicates;

  /// No description provided for @kpiTodayAttendance.
  ///
  /// In en, this message translates to:
  /// **'Attendance days today'**
  String get kpiTodayAttendance;

  /// No description provided for @moduleDisabled.
  ///
  /// In en, this message translates to:
  /// **'Your account does not have access to this module.'**
  String get moduleDisabled;

  /// No description provided for @serverError.
  ///
  /// In en, this message translates to:
  /// **'Server error: {message}'**
  String serverError(String message);

  /// No description provided for @networkError.
  ///
  /// In en, this message translates to:
  /// **'Cannot reach the server. Check the connection and the server URL.'**
  String get networkError;

  /// No description provided for @sessionExpired.
  ///
  /// In en, this message translates to:
  /// **'Your session expired. Please sign in again.'**
  String get sessionExpired;

  /// No description provided for @loadingReference.
  ///
  /// In en, this message translates to:
  /// **'Downloading reference data…'**
  String get loadingReference;

  /// No description provided for @bootstrapRequired.
  ///
  /// In en, this message translates to:
  /// **'Reference data has not been downloaded yet. Connect to the internet and run a full refresh.'**
  String get bootstrapRequired;

  /// No description provided for @aboutSync.
  ///
  /// In en, this message translates to:
  /// **'Every record you create offline is verified by the BMA-NFE server when pushed. Duplicates are never created silently: you decide whether to merge, link or create.'**
  String get aboutSync;

  /// No description provided for @items.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{1 item} other{{count} items}}'**
  String items(int count);

  /// No description provided for @openRecord.
  ///
  /// In en, this message translates to:
  /// **'Open record'**
  String get openRecord;

  /// No description provided for @reportFor.
  ///
  /// In en, this message translates to:
  /// **'Batch {id}'**
  String reportFor(String id);

  /// No description provided for @noHistory.
  ///
  /// In en, this message translates to:
  /// **'No sync batches yet.'**
  String get noHistory;

  /// No description provided for @fixAndRetry.
  ///
  /// In en, this message translates to:
  /// **'Fix and retry'**
  String get fixAndRetry;

  /// No description provided for @viewServerErrors.
  ///
  /// In en, this message translates to:
  /// **'Server validation messages'**
  String get viewServerErrors;

  /// No description provided for @sectionOther.
  ///
  /// In en, this message translates to:
  /// **'Other'**
  String get sectionOther;

  /// No description provided for @yes.
  ///
  /// In en, this message translates to:
  /// **'Yes'**
  String get yes;

  /// No description provided for @no.
  ///
  /// In en, this message translates to:
  /// **'No'**
  String get no;

  /// No description provided for @unknown.
  ///
  /// In en, this message translates to:
  /// **'Unknown'**
  String get unknown;

  /// No description provided for @childAge.
  ///
  /// In en, this message translates to:
  /// **'Age'**
  String get childAge;

  /// No description provided for @childNumber.
  ///
  /// In en, this message translates to:
  /// **'Record number'**
  String get childNumber;

  /// No description provided for @unicefId.
  ///
  /// In en, this message translates to:
  /// **'UNICEF ID'**
  String get unicefId;

  /// No description provided for @registeredAt.
  ///
  /// In en, this message translates to:
  /// **'Registered at'**
  String get registeredAt;

  /// No description provided for @matchReason.
  ///
  /// In en, this message translates to:
  /// **'Match: {reason}'**
  String matchReason(String reason);

  /// No description provided for @welcome.
  ///
  /// In en, this message translates to:
  /// **'Welcome, {name}'**
  String welcome(String name);

  /// No description provided for @deviceInfo.
  ///
  /// In en, this message translates to:
  /// **'Device'**
  String get deviceInfo;

  /// No description provided for @version.
  ///
  /// In en, this message translates to:
  /// **'Version'**
  String get version;

  /// No description provided for @clearLocalData.
  ///
  /// In en, this message translates to:
  /// **'Clear local data'**
  String get clearLocalData;

  /// No description provided for @clearLocalDataWarning.
  ///
  /// In en, this message translates to:
  /// **'This removes all downloaded records and unsent work from this device. Pending changes will be lost.'**
  String get clearLocalDataWarning;

  /// No description provided for @gradings.
  ///
  /// In en, this message translates to:
  /// **'Assessments & grading'**
  String get gradings;

  /// No description provided for @referral.
  ///
  /// In en, this message translates to:
  /// **'Referral'**
  String get referral;

  /// No description provided for @followUp.
  ///
  /// In en, this message translates to:
  /// **'Follow-up'**
  String get followUp;

  /// No description provided for @schoolProfile.
  ///
  /// In en, this message translates to:
  /// **'School profile'**
  String get schoolProfile;

  /// No description provided for @teacherForm.
  ///
  /// In en, this message translates to:
  /// **'Teacher'**
  String get teacherForm;

  /// No description provided for @deleteConfirm.
  ///
  /// In en, this message translates to:
  /// **'Delete this record?'**
  String get deleteConfirm;

  /// No description provided for @confirmRegistration.
  ///
  /// In en, this message translates to:
  /// **'Confirm registration'**
  String get confirmRegistration;

  /// No description provided for @resolvedLocally.
  ///
  /// In en, this message translates to:
  /// **'Resolution saved. Push again to apply it.'**
  String get resolvedLocally;

  /// No description provided for @noTeachers.
  ///
  /// In en, this message translates to:
  /// **'No teachers recorded yet.'**
  String get noTeachers;

  /// No description provided for @viewReport.
  ///
  /// In en, this message translates to:
  /// **'View report'**
  String get viewReport;

  /// No description provided for @serverRecordId.
  ///
  /// In en, this message translates to:
  /// **'Server record #{id}'**
  String serverRecordId(String id);

  /// No description provided for @total.
  ///
  /// In en, this message translates to:
  /// **'Total'**
  String get total;

  /// No description provided for @chooseCandidate.
  ///
  /// In en, this message translates to:
  /// **'Choose the matching existing record'**
  String get chooseCandidate;

  /// No description provided for @attendanceDays.
  ///
  /// In en, this message translates to:
  /// **'Attendance days'**
  String get attendanceDays;

  /// No description provided for @needsResolution.
  ///
  /// In en, this message translates to:
  /// **'Records needing your decision'**
  String get needsResolution;

  /// No description provided for @noPendingWork.
  ///
  /// In en, this message translates to:
  /// **'Everything on this device is synchronised.'**
  String get noPendingWork;

  /// No description provided for @fieldDifferences.
  ///
  /// In en, this message translates to:
  /// **'Fields that differ'**
  String get fieldDifferences;

  /// No description provided for @localOnlyHint.
  ///
  /// In en, this message translates to:
  /// **'Created on this device, not yet on the server.'**
  String get localOnlyHint;

  /// No description provided for @selectionIncomplete.
  ///
  /// In en, this message translates to:
  /// **'Select all filters first.'**
  String get selectionIncomplete;

  /// No description provided for @teachersPresent.
  ///
  /// In en, this message translates to:
  /// **'{count} present'**
  String teachersPresent(int count);

  /// No description provided for @monthSummary.
  ///
  /// In en, this message translates to:
  /// **'{present} present · {absent} absent'**
  String monthSummary(int present, int absent);

  /// No description provided for @tipsTitle.
  ///
  /// In en, this message translates to:
  /// **'Getting started'**
  String get tipsTitle;

  /// No description provided for @tipsStep.
  ///
  /// In en, this message translates to:
  /// **'Step {current} of {total}'**
  String tipsStep(int current, int total);

  /// No description provided for @skip.
  ///
  /// In en, this message translates to:
  /// **'Skip'**
  String get skip;

  /// No description provided for @done.
  ///
  /// In en, this message translates to:
  /// **'Done'**
  String get done;

  /// No description provided for @gotIt.
  ///
  /// In en, this message translates to:
  /// **'Got it'**
  String get gotIt;

  /// No description provided for @tipsShowAgain.
  ///
  /// In en, this message translates to:
  /// **'Show tips again'**
  String get tipsShowAgain;

  /// No description provided for @tipsDataReady.
  ///
  /// In en, this message translates to:
  /// **'Reference data is on this device.'**
  String get tipsDataReady;

  /// No description provided for @tipsWelcomeTitle.
  ///
  /// In en, this message translates to:
  /// **'Works without internet'**
  String get tipsWelcomeTitle;

  /// No description provided for @tipsWelcomeBody.
  ///
  /// In en, this message translates to:
  /// **'Everything is saved on this device first: register children, record services and take attendance with no connection. Each change stays Pending until you push it to the BMA-NFE server. A banner at the top shows when you are offline.'**
  String get tipsWelcomeBody;

  /// No description provided for @tipsDataTitle.
  ///
  /// In en, this message translates to:
  /// **'Your data on this device'**
  String get tipsDataTitle;

  /// No description provided for @tipsDataBody.
  ///
  /// In en, this message translates to:
  /// **'At sign-in the app downloaded reference data (centres, rounds, programmes, forms) and the records your account may see. If Home shows a warning, connect and run Full refresh. The last account that signed in on this device can sign in offline.'**
  String get tipsDataBody;

  /// No description provided for @tipsRegisterTitle.
  ///
  /// In en, this message translates to:
  /// **'Registering a child'**
  String get tipsRegisterTitle;

  /// No description provided for @tipsRegisterBody.
  ///
  /// In en, this message translates to:
  /// **'Search the beneficiaries list first to avoid duplicates. Tap Register new and follow the steps: Identity, Caregivers & household, then Review & confirm. Names, gender, birth date and nationality are required; copy the ID number exactly as written on the document.'**
  String get tipsRegisterBody;

  /// No description provided for @tipsDailyTitle.
  ///
  /// In en, this message translates to:
  /// **'Services and attendance'**
  String get tipsDailyTitle;

  /// No description provided for @tipsDailyBody.
  ///
  /// In en, this message translates to:
  /// **'Open a child\'s profile and tap Add service to record a service form. For attendance: choose centre or school, round, programme and date, tap Load children, then Mark all present, set absentees to Absent with a reason, and Save.'**
  String get tipsDailyBody;

  /// No description provided for @tipsPushTitle.
  ///
  /// In en, this message translates to:
  /// **'Push and read the report'**
  String get tipsPushTitle;

  /// No description provided for @tipsPushBody.
  ///
  /// In en, this message translates to:
  /// **'When connected, open Sync centre and tap Push changes. The server checks every record and returns a result: Created, Updated, Merged, Linked, Duplicate, Conflict, Error or Skipped. Open the Push report to see why. Errors show the server\'s messages in the form: fix and retry.'**
  String get tipsPushBody;

  /// No description provided for @tipsResolveTitle.
  ///
  /// In en, this message translates to:
  /// **'Duplicates and conflicts'**
  String get tipsResolveTitle;

  /// No description provided for @tipsResolveBody.
  ///
  /// In en, this message translates to:
  /// **'The server compares each registration with existing children: UNICEF ID, names with birth date and gender, ID numbers and near matches. You decide in Sync centre: merge into the existing record, same child new enrolment, create anyway or discard. For conflicts, overwrite or keep the server version.'**
  String get tipsResolveBody;

  /// No description provided for @tipsSafeTitle.
  ///
  /// In en, this message translates to:
  /// **'Keep your data safe'**
  String get tipsSafeTitle;

  /// No description provided for @tipsSafeBody.
  ///
  /// In en, this message translates to:
  /// **'Unsent work exists only on this device: push every day you have a connection, and never clear local data with pending changes. This app holds children\'s personal data: never share your account. Switch language in Settings. Reopen this guide from the ? icon on Home.'**
  String get tipsSafeBody;

  /// No description provided for @tipHomeSync.
  ///
  /// In en, this message translates to:
  /// **'Push changes whenever you have a connection. The number on the cloud icon counts work waiting to push or needing your decision; tap it to open Sync centre.'**
  String get tipHomeSync;

  /// No description provided for @tipRegistrationsSearch.
  ///
  /// In en, this message translates to:
  /// **'Search by name, ID number or record number before registering. The icon on each row shows its sync state: Pending, Synced, Duplicate, Conflict.'**
  String get tipRegistrationsSearch;

  /// No description provided for @tipAttendanceFlow.
  ///
  /// In en, this message translates to:
  /// **'Choose the centre or school, round, programme and date, then tap Load children. Mark all present, switch anyone absent to Absent with a reason, then Save. Use Day off to close a day.'**
  String get tipAttendanceFlow;

  /// No description provided for @tipSyncCenter.
  ///
  /// In en, this message translates to:
  /// **'Push changes and Download updates need a connection; downloading never overwrites unsent work. Records needing your decision are listed below; tap one to resolve it.'**
  String get tipSyncCenter;

  /// No description provided for @setupTitle.
  ///
  /// In en, this message translates to:
  /// **'Set up the server'**
  String get setupTitle;

  /// No description provided for @setupIntro.
  ///
  /// In en, this message translates to:
  /// **'Tell this device which BMA-NFE server it should talk to. Ask your programme focal point if you are not sure.'**
  String get setupIntro;

  /// No description provided for @setupTestConnection.
  ///
  /// In en, this message translates to:
  /// **'Test connection'**
  String get setupTestConnection;

  /// No description provided for @setupConnectionOk.
  ///
  /// In en, this message translates to:
  /// **'Connected. This server runs the BMA-NFE mobile API.'**
  String get setupConnectionOk;

  /// No description provided for @setupConnectionNotBma.
  ///
  /// In en, this message translates to:
  /// **'The address answered, but the BMA-NFE mobile API is not installed there. Check the address.'**
  String get setupConnectionNotBma;

  /// No description provided for @setupConnectionFailed.
  ///
  /// In en, this message translates to:
  /// **'Could not reach this address. Check the spelling and your internet connection.'**
  String get setupConnectionFailed;

  /// No description provided for @setupInvalidUrl.
  ///
  /// In en, this message translates to:
  /// **'Enter a web address, for example https://bma-nfe.example.org'**
  String get setupInvalidUrl;

  /// No description provided for @setupContinue.
  ///
  /// In en, this message translates to:
  /// **'Continue'**
  String get setupContinue;

  /// No description provided for @setupChangeLater.
  ///
  /// In en, this message translates to:
  /// **'You can change the server later in Settings.'**
  String get setupChangeLater;

  /// No description provided for @centerProfile.
  ///
  /// In en, this message translates to:
  /// **'Centre profile'**
  String get centerProfile;

  /// No description provided for @profileNoCenter.
  ///
  /// In en, this message translates to:
  /// **'Your account is not linked to a centre.'**
  String get profileNoCenter;

  /// No description provided for @profileNoSchool.
  ///
  /// In en, this message translates to:
  /// **'Your account is not linked to a school.'**
  String get profileNoSchool;

  /// No description provided for @profileNotDownloaded.
  ///
  /// In en, this message translates to:
  /// **'The details arrive with the reference data. Connect and run a full refresh.'**
  String get profileNotDownloaded;

  /// No description provided for @partner.
  ///
  /// In en, this message translates to:
  /// **'Partner'**
  String get partner;

  /// No description provided for @governorate.
  ///
  /// In en, this message translates to:
  /// **'Governorate'**
  String get governorate;

  /// No description provided for @district.
  ///
  /// In en, this message translates to:
  /// **'District'**
  String get district;

  /// No description provided for @cadaster.
  ///
  /// In en, this message translates to:
  /// **'Cadaster'**
  String get cadaster;

  /// No description provided for @facilityType.
  ///
  /// In en, this message translates to:
  /// **'Type'**
  String get facilityType;

  /// No description provided for @programmes.
  ///
  /// In en, this message translates to:
  /// **'Programmes'**
  String get programmes;

  /// No description provided for @packagesOffered.
  ///
  /// In en, this message translates to:
  /// **'Services offered'**
  String get packagesOffered;

  /// No description provided for @statusLabel.
  ///
  /// In en, this message translates to:
  /// **'Status'**
  String get statusLabel;

  /// No description provided for @activeLabel.
  ///
  /// In en, this message translates to:
  /// **'Active'**
  String get activeLabel;

  /// No description provided for @inactiveLabel.
  ///
  /// In en, this message translates to:
  /// **'Inactive'**
  String get inactiveLabel;

  /// No description provided for @schoolNumber.
  ///
  /// In en, this message translates to:
  /// **'School number'**
  String get schoolNumber;

  /// No description provided for @bmaSchool.
  ///
  /// In en, this message translates to:
  /// **'BMA school'**
  String get bmaSchool;

  /// No description provided for @closedLabel.
  ///
  /// In en, this message translates to:
  /// **'Closed'**
  String get closedLabel;

  /// No description provided for @openLabel.
  ///
  /// In en, this message translates to:
  /// **'Open'**
  String get openLabel;

  /// No description provided for @workingDays.
  ///
  /// In en, this message translates to:
  /// **'Working days'**
  String get workingDays;

  /// No description provided for @weekendLabel.
  ///
  /// In en, this message translates to:
  /// **'Weekend'**
  String get weekendLabel;

  /// No description provided for @coordinates.
  ///
  /// In en, this message translates to:
  /// **'Coordinates'**
  String get coordinates;

  /// No description provided for @locationLabel.
  ///
  /// In en, this message translates to:
  /// **'Location'**
  String get locationLabel;

  /// No description provided for @atAGlance.
  ///
  /// In en, this message translates to:
  /// **'At a glance'**
  String get atAGlance;

  /// No description provided for @quickActions.
  ///
  /// In en, this message translates to:
  /// **'Quick actions'**
  String get quickActions;

  /// No description provided for @yourProgrammes.
  ///
  /// In en, this message translates to:
  /// **'Your programmes'**
  String get yourProgrammes;

  /// No description provided for @registeredChildren.
  ///
  /// In en, this message translates to:
  /// **'Registered children'**
  String get registeredChildren;

  /// No description provided for @notRecorded.
  ///
  /// In en, this message translates to:
  /// **'Not recorded'**
  String get notRecorded;

  /// No description provided for @viewProfile.
  ///
  /// In en, this message translates to:
  /// **'View profile'**
  String get viewProfile;

  /// No description provided for @selectBeneficiary.
  ///
  /// In en, this message translates to:
  /// **'Select a beneficiary to see their profile.'**
  String get selectBeneficiary;

  /// No description provided for @switchModule.
  ///
  /// In en, this message translates to:
  /// **'Switch programme'**
  String get switchModule;

  /// No description provided for @unsavedChanges.
  ///
  /// In en, this message translates to:
  /// **'Leave this form? Unsaved changes will be lost.'**
  String get unsavedChanges;
}

class _AppLocalizationsDelegate
    extends LocalizationsDelegate<AppLocalizations> {
  const _AppLocalizationsDelegate();

  @override
  Future<AppLocalizations> load(Locale locale) {
    return SynchronousFuture<AppLocalizations>(lookupAppLocalizations(locale));
  }

  @override
  bool isSupported(Locale locale) =>
      <String>['ar', 'en'].contains(locale.languageCode);

  @override
  bool shouldReload(_AppLocalizationsDelegate old) => false;
}

AppLocalizations lookupAppLocalizations(Locale locale) {
  // Lookup logic when only language code is specified.
  switch (locale.languageCode) {
    case 'ar':
      return AppLocalizationsAr();
    case 'en':
      return AppLocalizationsEn();
  }

  throw FlutterError(
    'AppLocalizations.delegate failed to load unsupported locale "$locale". This is likely '
    'an issue with the localizations generation tool. Please file an issue '
    'on GitHub with a reproducible sample app and the gen-l10n configuration '
    'that was used.',
  );
}
