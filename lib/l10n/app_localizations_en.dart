// ignore: unused_import
import 'package:intl/intl.dart' as intl;

import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for English (`en`).
class AppLocalizationsEn extends AppLocalizations {
  AppLocalizationsEn([String locale = 'en']) : super(locale);

  @override
  String get appTitle => 'BMA Mobile';

  @override
  String get login => 'Login';

  @override
  String get logout => 'Logout';

  @override
  String get username => 'Username';

  @override
  String get password => 'Password';

  @override
  String get serverUrl => 'Server URL';

  @override
  String get serverUrlHint => 'https://bma.example.org';

  @override
  String get signIn => 'Sign in';

  @override
  String get signingIn => 'Signing in…';

  @override
  String loginFailed(String reason) {
    return 'Login failed: $reason';
  }

  @override
  String get offlineLoginHint =>
      'No connection. Use the last account that signed in on this device.';

  @override
  String get invalidCredentials => 'Invalid username or password.';

  @override
  String get home => 'Home';

  @override
  String get dashboard => 'Dashboard';

  @override
  String get registrations => 'Registrations';

  @override
  String get beneficiaries => 'Beneficiaries';

  @override
  String get attendance => 'Attendance';

  @override
  String get teachers => 'Teachers';

  @override
  String get teacherAttendance => 'Teacher attendance';

  @override
  String get sync => 'Sync';

  @override
  String get syncCenter => 'Sync centre';

  @override
  String get settings => 'Settings';

  @override
  String get language => 'Language';

  @override
  String get english => 'English';

  @override
  String get arabic => 'Arabic';

  @override
  String get mscc => 'NFE';

  @override
  String get alp => 'ALP schools';

  @override
  String get clm => 'CLM Bridging';

  @override
  String get registerNew => 'Register new';

  @override
  String get search => 'Search';

  @override
  String get searchHint => 'Name, ID number or record number';

  @override
  String get noResults => 'No records found.';

  @override
  String get pending => 'Pending';

  @override
  String get synced => 'Synced';

  @override
  String get pushing => 'Pushing';

  @override
  String get duplicate => 'Duplicate';

  @override
  String get conflict => 'Conflict';

  @override
  String get error => 'Error';

  @override
  String get discarded => 'Discarded';

  @override
  String pendingChanges(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count pending changes',
      one: '1 pending change',
      zero: 'No pending changes',
    );
    return '$_temp0';
  }

  @override
  String get pushNow => 'Push changes';

  @override
  String get pullNow => 'Download updates';

  @override
  String get fullRefresh => 'Full refresh (reference data + records)';

  @override
  String lastPull(String time) {
    return 'Last download: $time';
  }

  @override
  String get never => 'never';

  @override
  String get online => 'Online';

  @override
  String get offline => 'Offline';

  @override
  String get offlineBanner =>
      'You are offline. Work is saved on this device and pushed later.';

  @override
  String get pushReport => 'Push report';

  @override
  String get syncHistory => 'Sync history';

  @override
  String get summaryCreated => 'Created';

  @override
  String get summaryUpdated => 'Updated';

  @override
  String get summaryMerged => 'Merged';

  @override
  String get summaryLinked => 'Linked';

  @override
  String get summaryDuplicates => 'Duplicates';

  @override
  String get summaryConflicts => 'Conflicts';

  @override
  String get summaryErrors => 'Errors';

  @override
  String get summarySkipped => 'Skipped';

  @override
  String get summaryDiscarded => 'Discarded';

  @override
  String get resolveDuplicate => 'Resolve duplicate';

  @override
  String get duplicateExplanation =>
      'The server found existing records matching this child. Choose what to do.';

  @override
  String get mergeIntoExisting => 'Merge into existing record';

  @override
  String get mergeExplanation =>
      'Copy the values collected offline onto the selected existing registration.';

  @override
  String get linkExistingChild => 'Same child, new enrolment';

  @override
  String get linkExplanation =>
      'Create the new registration for the existing child without creating a new child.';

  @override
  String get createAnyway => 'Create anyway (different person)';

  @override
  String get discardLocal => 'Discard my offline record';

  @override
  String get overwriteServer => 'Overwrite server version';

  @override
  String get keepServer => 'Keep server version';

  @override
  String get resolveConflict => 'Resolve conflict';

  @override
  String get conflictExplanation =>
      'This record was changed on the server after you edited it offline.';

  @override
  String get localVersion => 'Your version';

  @override
  String get serverVersion => 'Server version';

  @override
  String get apply => 'Apply';

  @override
  String get cancel => 'Cancel';

  @override
  String get save => 'Save';

  @override
  String get saveDraft => 'Save locally';

  @override
  String get next => 'Next';

  @override
  String get back => 'Back';

  @override
  String get submit => 'Submit';

  @override
  String get confirm => 'Confirm';

  @override
  String get delete => 'Delete';

  @override
  String get edit => 'Edit';

  @override
  String get close => 'Close';

  @override
  String get retry => 'Retry';

  @override
  String get requiredField => 'This field is required.';

  @override
  String get invalidNumber => 'Enter a valid number.';

  @override
  String get invalidDate => 'Enter a valid date (YYYY-MM-DD).';

  @override
  String get futureDate => 'Date cannot be in the future.';

  @override
  String get onlyLetters => 'Only letters are allowed.';

  @override
  String get confirmMismatch => 'Values do not match.';

  @override
  String get stepIdentity => 'Identity';

  @override
  String get stepCaregivers => 'Caregivers & household';

  @override
  String get stepReview => 'Review & confirm';

  @override
  String get possibleDuplicates => 'Possible duplicates on this device';

  @override
  String get possibleDuplicatesHint =>
      'A record with the same name, birth date and gender already exists locally. Continue only if this is a different child.';

  @override
  String get reviewHint =>
      'Check the values below, then submit. The record is stored on this device and verified by the server on the next push.';

  @override
  String get profile => 'Profile';

  @override
  String get info => 'Information';

  @override
  String get services => 'Services';

  @override
  String get educationHistory => 'Education history';

  @override
  String get addService => 'Add service';

  @override
  String get newRound => 'New round';

  @override
  String get noServices => 'No services recorded yet.';

  @override
  String get markDeleted => 'Mark as deleted';

  @override
  String get selectCenter => 'Centre';

  @override
  String get selectSchool => 'School';

  @override
  String get selectRound => 'Round';

  @override
  String get selectProgram => 'Programme';

  @override
  String get selectSection => 'Section';

  @override
  String get selectDate => 'Date';

  @override
  String get dayOff => 'Day off';

  @override
  String get closeReason => 'Close reason';

  @override
  String get present => 'Present';

  @override
  String get absent => 'Absent';

  @override
  String get absenceReason => 'Absence reason';

  @override
  String get absenceReasonOther => 'Other reason';

  @override
  String get markAllPresent => 'Mark all present';

  @override
  String get loadChildren => 'Load children';

  @override
  String get noChildrenForSelection =>
      'No enrolled children for this selection.';

  @override
  String get attendanceSaved => 'Attendance saved on this device.';

  @override
  String get childMonth => 'Monthly attendance';

  @override
  String get colName => 'Name';

  @override
  String get colMother => 'Mother';

  @override
  String get colBirthday => 'Birth date';

  @override
  String get colAttendance => 'Attendance';

  @override
  String get colReason => 'Reason';

  @override
  String get notMarked => 'Not marked';

  @override
  String get sessionLabel => 'Session';

  @override
  String get rosterLabel => 'Roster';

  @override
  String get noSheetForDay => 'No sheet';

  @override
  String get attended => 'Attended';

  @override
  String get totalRegistrations => 'Registrations';

  @override
  String get byGender => 'By gender';

  @override
  String get byNationality => 'By nationality';

  @override
  String get byAgeGroup => 'By age group';

  @override
  String get attendanceRate => 'Attendance rate (30 days)';

  @override
  String get servicesDelivered => 'Services delivered';

  @override
  String get kpiPendingPush => 'Waiting to push';

  @override
  String get kpiDuplicates => 'Need resolution';

  @override
  String get kpiTodayAttendance => 'Attendance days today';

  @override
  String get moduleDisabled =>
      'Your account does not have access to this module.';

  @override
  String serverError(String message) {
    return 'Server error: $message';
  }

  @override
  String get networkError =>
      'Cannot reach the server. Check the connection and the server URL.';

  @override
  String get sessionExpired => 'Your session expired. Please sign in again.';

  @override
  String get loadingReference => 'Downloading reference data…';

  @override
  String get bootstrapRequired =>
      'Reference data has not been downloaded yet. Connect to the internet and run a full refresh.';

  @override
  String get aboutSync =>
      'Every record you create offline is verified by the BMA-NFE server when pushed. Duplicates are never created silently: you decide whether to merge, link or create.';

  @override
  String items(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count items',
      one: '1 item',
    );
    return '$_temp0';
  }

  @override
  String get openRecord => 'Open record';

  @override
  String reportFor(String id) {
    return 'Batch $id';
  }

  @override
  String get noHistory => 'No sync batches yet.';

  @override
  String get fixAndRetry => 'Fix and retry';

  @override
  String get viewServerErrors => 'Server validation messages';

  @override
  String get sectionOther => 'Other';

  @override
  String get yes => 'Yes';

  @override
  String get no => 'No';

  @override
  String get unknown => 'Unknown';

  @override
  String get childAge => 'Age';

  @override
  String get childNumber => 'Record number';

  @override
  String get unicefId => 'UNICEF ID';

  @override
  String get registeredAt => 'Registered at';

  @override
  String matchReason(String reason) {
    return 'Match: $reason';
  }

  @override
  String welcome(String name) {
    return 'Welcome, $name';
  }

  @override
  String get deviceInfo => 'Device';

  @override
  String get version => 'Version';

  @override
  String get clearLocalData => 'Clear local data';

  @override
  String get clearLocalDataWarning =>
      'This removes all downloaded records and unsent work from this device. Pending changes will be lost.';

  @override
  String get gradings => 'Assessments & grading';

  @override
  String get referral => 'Referral';

  @override
  String get followUp => 'Follow-up';

  @override
  String get schoolProfile => 'School profile';

  @override
  String get teacherForm => 'Teacher';

  @override
  String get deleteConfirm => 'Delete this record?';

  @override
  String get confirmRegistration => 'Confirm registration';

  @override
  String get resolvedLocally => 'Resolution saved. Push again to apply it.';

  @override
  String get noTeachers => 'No teachers recorded yet.';

  @override
  String get viewReport => 'View report';

  @override
  String serverRecordId(String id) {
    return 'Server record #$id';
  }

  @override
  String get total => 'Total';

  @override
  String get chooseCandidate => 'Choose the matching existing record';

  @override
  String get attendanceDays => 'Attendance days';

  @override
  String get needsResolution => 'Records needing your decision';

  @override
  String get noPendingWork => 'Everything on this device is synchronised.';

  @override
  String get fieldDifferences => 'Fields that differ';

  @override
  String get localOnlyHint => 'Created on this device, not yet on the server.';

  @override
  String get selectionIncomplete => 'Select all filters first.';

  @override
  String teachersPresent(int count) {
    return '$count present';
  }

  @override
  String monthSummary(int present, int absent) {
    return '$present present · $absent absent';
  }

  @override
  String get tipsTitle => 'Getting started';

  @override
  String tipsStep(int current, int total) {
    return 'Step $current of $total';
  }

  @override
  String get skip => 'Skip';

  @override
  String get done => 'Done';

  @override
  String get gotIt => 'Got it';

  @override
  String get tipsShowAgain => 'Show tips again';

  @override
  String get tipsDataReady => 'Reference data is on this device.';

  @override
  String get tipsWelcomeTitle => 'Works without internet';

  @override
  String get tipsWelcomeBody =>
      'Everything is saved on this device first: register children, record services and take attendance with no connection. Each change stays Pending until you push it to the BMA-NFE server. A banner at the top shows when you are offline.';

  @override
  String get tipsDataTitle => 'Your data on this device';

  @override
  String get tipsDataBody =>
      'At sign-in the app downloaded reference data (centres, rounds, programmes, forms) and the records your account may see. If Home shows a warning, connect and run Full refresh. The last account that signed in on this device can sign in offline.';

  @override
  String get tipsRegisterTitle => 'Registering a child';

  @override
  String get tipsRegisterBody =>
      'Search the beneficiaries list first to avoid duplicates. Tap Register new and follow the steps: Identity, Caregivers & household, then Review & confirm. Names, gender, birth date and nationality are required; copy the ID number exactly as written on the document.';

  @override
  String get tipsDailyTitle => 'Services and attendance';

  @override
  String get tipsDailyBody =>
      'Open a child\'s profile and tap Add service to record a service form. For attendance: choose centre or school, round, programme and date, tap Load children, then Mark all present, set absentees to Absent with a reason, and Save.';

  @override
  String get tipsPushTitle => 'Push and read the report';

  @override
  String get tipsPushBody =>
      'When connected, open Sync centre and tap Push changes. The server checks every record and returns a result: Created, Updated, Merged, Linked, Duplicate, Conflict, Error or Skipped. Open the Push report to see why. Errors show the server\'s messages in the form: fix and retry.';

  @override
  String get tipsResolveTitle => 'Duplicates and conflicts';

  @override
  String get tipsResolveBody =>
      'The server compares each registration with existing children: UNICEF ID, names with birth date and gender, ID numbers and near matches. You decide in Sync centre: merge into the existing record, same child new enrolment, create anyway or discard. For conflicts, overwrite or keep the server version.';

  @override
  String get tipsSafeTitle => 'Keep your data safe';

  @override
  String get tipsSafeBody =>
      'Unsent work exists only on this device: push every day you have a connection, and never clear local data with pending changes. This app holds children\'s personal data: never share your account. Switch language in Settings. Reopen this guide from the ? icon on Home.';

  @override
  String get tipHomeSync =>
      'Push changes whenever you have a connection. The number on the cloud icon counts work waiting to push or needing your decision; tap it to open Sync centre.';

  @override
  String get tipRegistrationsSearch =>
      'Search by name, ID number or record number before registering. The icon on each row shows its sync state: Pending, Synced, Duplicate, Conflict.';

  @override
  String get tipAttendanceFlow =>
      'Choose the centre or school, round, programme and date, then tap Load children. Mark all present, switch anyone absent to Absent with a reason, then Save. Use Day off to close a day.';

  @override
  String get tipSyncCenter =>
      'Push changes and Download updates need a connection; downloading never overwrites unsent work. Records needing your decision are listed below; tap one to resolve it.';

  @override
  String get setupTitle => 'Set up the server';

  @override
  String get setupIntro =>
      'Tell this device which BMA-NFE server it should talk to. Ask your programme focal point if you are not sure.';

  @override
  String get setupTestConnection => 'Test connection';

  @override
  String get setupConnectionOk =>
      'Connected. This server runs the BMA-NFE mobile API.';

  @override
  String get setupConnectionNotBma =>
      'The address answered, but the BMA-NFE mobile API is not installed there. Check the address.';

  @override
  String get setupConnectionFailed =>
      'Could not reach this address. Check the spelling and your internet connection.';

  @override
  String get setupInvalidUrl =>
      'Enter a web address, for example https://bma-nfe.example.org';

  @override
  String get setupContinue => 'Continue';

  @override
  String get setupChangeLater => 'You can change the server later in Settings.';

  @override
  String get centerProfile => 'Centre profile';

  @override
  String get profileNoCenter => 'Your account is not linked to a centre.';

  @override
  String get profileNoSchool => 'Your account is not linked to a school.';

  @override
  String get profileNotDownloaded =>
      'The details arrive with the reference data. Connect and run a full refresh.';

  @override
  String get partner => 'Partner';

  @override
  String get governorate => 'Governorate';

  @override
  String get district => 'District';

  @override
  String get cadaster => 'Cadaster';

  @override
  String get facilityType => 'Type';

  @override
  String get programmes => 'Programmes';

  @override
  String get packagesOffered => 'Services offered';

  @override
  String get statusLabel => 'Status';

  @override
  String get activeLabel => 'Active';

  @override
  String get inactiveLabel => 'Inactive';

  @override
  String get schoolNumber => 'School number';

  @override
  String get bmaSchool => 'BMA school';

  @override
  String get closedLabel => 'Closed';

  @override
  String get openLabel => 'Open';

  @override
  String get workingDays => 'Working days';

  @override
  String get weekendLabel => 'Weekend';

  @override
  String get coordinates => 'Coordinates';

  @override
  String get locationLabel => 'Location';

  @override
  String get atAGlance => 'At a glance';

  @override
  String get quickActions => 'Quick actions';

  @override
  String get yourProgrammes => 'Your programmes';

  @override
  String get registeredChildren => 'Registered children';

  @override
  String get notRecorded => 'Not recorded';

  @override
  String get viewProfile => 'View profile';

  @override
  String get selectBeneficiary => 'Select a beneficiary to see their profile.';

  @override
  String get switchModule => 'Switch programme';

  @override
  String get unsavedChanges => 'Leave this form? Unsaved changes will be lost.';
}
