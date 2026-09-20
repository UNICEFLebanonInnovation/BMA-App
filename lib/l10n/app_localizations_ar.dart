// ignore: unused_import
import 'package:intl/intl.dart' as intl;

import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for Arabic (`ar`).
class AppLocalizationsAr extends AppLocalizations {
  AppLocalizationsAr([String locale = 'ar']) : super(locale);

  @override
  String get appTitle => 'تطبيق BMA';

  @override
  String get login => 'تسجيل الدخول';

  @override
  String get logout => 'تسجيل الخروج';

  @override
  String get username => 'اسم المستخدم';

  @override
  String get password => 'كلمة المرور';

  @override
  String get serverUrl => 'عنوان الخادم';

  @override
  String get serverUrlHint => 'https://bma.example.org';

  @override
  String get signIn => 'دخول';

  @override
  String get signingIn => 'جارٍ تسجيل الدخول…';

  @override
  String loginFailed(String reason) {
    return 'فشل تسجيل الدخول: $reason';
  }

  @override
  String get offlineLoginHint =>
      'لا يوجد اتصال. استخدم آخر حساب سجّل الدخول على هذا الجهاز.';

  @override
  String get invalidCredentials => 'اسم المستخدم أو كلمة المرور غير صحيحة.';

  @override
  String get home => 'الرئيسية';

  @override
  String get dashboard => 'لوحة المعلومات';

  @override
  String get registrations => 'التسجيلات';

  @override
  String get beneficiaries => 'المستفيدون';

  @override
  String get attendance => 'الحضور';

  @override
  String get teachers => 'المعلمون';

  @override
  String get teacherAttendance => 'حضور المعلمين';

  @override
  String get sync => 'المزامنة';

  @override
  String get syncCenter => 'مركز المزامنة';

  @override
  String get settings => 'الإعدادات';

  @override
  String get language => 'اللغة';

  @override
  String get english => 'الإنجليزية';

  @override
  String get arabic => 'العربية';

  @override
  String get mscc => 'التعليم غير النظامي';

  @override
  String get alp => 'مدارس ALP';

  @override
  String get clm => 'CLM Bridging';

  @override
  String get registerNew => 'تسجيل جديد';

  @override
  String get search => 'بحث';

  @override
  String get searchHint => 'الاسم أو رقم الهوية أو رقم السجل';

  @override
  String get noResults => 'لا توجد سجلات.';

  @override
  String get pending => 'قيد الانتظار';

  @override
  String get synced => 'متزامن';

  @override
  String get pushing => 'جارٍ الإرسال';

  @override
  String get duplicate => 'مكرر';

  @override
  String get conflict => 'تعارض';

  @override
  String get error => 'خطأ';

  @override
  String get discarded => 'مهمل';

  @override
  String pendingChanges(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count تغييرات معلّقة',
      one: 'تغيير واحد معلّق',
      zero: 'لا توجد تغييرات معلّقة',
    );
    return '$_temp0';
  }

  @override
  String get pushNow => 'إرسال التغييرات';

  @override
  String get pullNow => 'تنزيل التحديثات';

  @override
  String get fullRefresh => 'تحديث كامل (البيانات المرجعية + السجلات)';

  @override
  String lastPull(String time) {
    return 'آخر تنزيل: $time';
  }

  @override
  String get never => 'أبداً';

  @override
  String get online => 'متصل';

  @override
  String get offline => 'غير متصل';

  @override
  String get offlineBanner =>
      'أنت غير متصل. يتم حفظ العمل على هذا الجهاز وإرساله لاحقاً.';

  @override
  String get pushReport => 'تقرير الإرسال';

  @override
  String get syncHistory => 'سجل المزامنة';

  @override
  String get summaryCreated => 'تم الإنشاء';

  @override
  String get summaryUpdated => 'تم التحديث';

  @override
  String get summaryMerged => 'تم الدمج';

  @override
  String get summaryLinked => 'تم الربط';

  @override
  String get summaryDuplicates => 'مكررات';

  @override
  String get summaryConflicts => 'تعارضات';

  @override
  String get summaryErrors => 'أخطاء';

  @override
  String get summarySkipped => 'تم التخطي';

  @override
  String get summaryDiscarded => 'مهملة';

  @override
  String get resolveDuplicate => 'معالجة التكرار';

  @override
  String get duplicateExplanation =>
      'وجد الخادم سجلات موجودة تطابق هذا الطفل. اختر ما تريد فعله.';

  @override
  String get mergeIntoExisting => 'دمج في السجل الموجود';

  @override
  String get mergeExplanation =>
      'نسخ القيم المجمّعة دون اتصال إلى التسجيل الموجود المحدد.';

  @override
  String get linkExistingChild => 'نفس الطفل، تسجيل جديد';

  @override
  String get linkExplanation =>
      'إنشاء التسجيل الجديد للطفل الموجود دون إنشاء طفل جديد.';

  @override
  String get createAnyway => 'إنشاء على أي حال (شخص مختلف)';

  @override
  String get discardLocal => 'إهمال سجلي غير المتصل';

  @override
  String get overwriteServer => 'استبدال نسخة الخادم';

  @override
  String get keepServer => 'الاحتفاظ بنسخة الخادم';

  @override
  String get resolveConflict => 'حل التعارض';

  @override
  String get conflictExplanation =>
      'تم تغيير هذا السجل على الخادم بعد تعديلك له دون اتصال.';

  @override
  String get localVersion => 'نسختك';

  @override
  String get serverVersion => 'نسخة الخادم';

  @override
  String get apply => 'تطبيق';

  @override
  String get cancel => 'إلغاء';

  @override
  String get save => 'حفظ';

  @override
  String get saveDraft => 'حفظ محلياً';

  @override
  String get next => 'التالي';

  @override
  String get back => 'رجوع';

  @override
  String get submit => 'إرسال';

  @override
  String get confirm => 'تأكيد';

  @override
  String get delete => 'حذف';

  @override
  String get edit => 'تعديل';

  @override
  String get close => 'إغلاق';

  @override
  String get retry => 'إعادة المحاولة';

  @override
  String get requiredField => 'هذا الحقل مطلوب.';

  @override
  String get invalidNumber => 'أدخل رقماً صحيحاً.';

  @override
  String get invalidDate => 'أدخل تاريخاً صحيحاً (YYYY-MM-DD).';

  @override
  String get futureDate => 'لا يمكن أن يكون التاريخ في المستقبل.';

  @override
  String get confirmMismatch => 'القيم غير متطابقة.';

  @override
  String get arabicOnlyHint => 'بالعربية فقط';

  @override
  String attendanceRowsNeedReason(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count أطفال بحاجة إلى سبب غياب.',
      one: 'طفل واحد بحاجة إلى سبب غياب.',
    );
    return '$_temp0';
  }

  @override
  String tooLong(String max) {
    return 'الحد الأقصى $max حرفًا.';
  }

  @override
  String tooShort(String min) {
    return '$min أحرف على الأقل.';
  }

  @override
  String get invalidFormat => 'صيغة غير صحيحة.';

  @override
  String get invalidEmail => 'أدخل بريدًا إلكترونيًا صحيحًا.';

  @override
  String get invalidChoice => 'اختر أحد الخيارات المتاحة.';

  @override
  String valueTooSmall(String min) {
    return 'يجب أن يكون $min أو أكثر.';
  }

  @override
  String valueTooLarge(String max) {
    return 'يجب أن يكون $max أو أقل.';
  }

  @override
  String get dateTooEarly => 'التاريخ مبكر جدًا.';

  @override
  String get dateTooLate => 'التاريخ متأخر جدًا.';

  @override
  String tooManyDecimals(String max) {
    return 'بحد أقصى $max منازل عشرية.';
  }

  @override
  String get stepIdentity => 'الهوية';

  @override
  String get stepCaregivers => 'مقدمو الرعاية والأسرة';

  @override
  String get stepReview => 'المراجعة والتأكيد';

  @override
  String get possibleDuplicates => 'تكرارات محتملة على هذا الجهاز';

  @override
  String get possibleDuplicatesHint =>
      'يوجد سجل محلي بنفس الاسم وتاريخ الميلاد والجنس. تابع فقط إذا كان هذا طفلاً مختلفاً.';

  @override
  String get reviewHint =>
      'راجع القيم أدناه ثم أرسل. يُحفظ السجل على هذا الجهاز ويتحقق منه الخادم عند الإرسال التالي.';

  @override
  String get profile => 'الملف';

  @override
  String get info => 'المعلومات';

  @override
  String get services => 'الخدمات';

  @override
  String get educationHistory => 'السجل التعليمي';

  @override
  String get addService => 'إضافة خدمة';

  @override
  String get newRound => 'جولة جديدة';

  @override
  String get noServices => 'لم تُسجل خدمات بعد.';

  @override
  String get markDeleted => 'وضع علامة محذوف';

  @override
  String get selectCenter => 'المركز';

  @override
  String get selectSchool => 'المدرسة';

  @override
  String get selectRound => 'الجولة';

  @override
  String get selectProgram => 'البرنامج';

  @override
  String get selectSection => 'الشعبة';

  @override
  String get selectDate => 'التاريخ';

  @override
  String get dayOff => 'يوم عطلة';

  @override
  String get closeReason => 'سبب الإغلاق';

  @override
  String get present => 'حاضر';

  @override
  String get absent => 'غائب';

  @override
  String get absenceReason => 'سبب الغياب';

  @override
  String get absenceReasonOther => 'سبب آخر';

  @override
  String get markAllPresent => 'تحديد الجميع حاضرين';

  @override
  String get loadChildren => 'تحميل الأطفال';

  @override
  String get noChildrenForSelection => 'لا يوجد أطفال مسجلون لهذا الاختيار.';

  @override
  String get attendanceSaved => 'تم حفظ الحضور على هذا الجهاز.';

  @override
  String get childMonth => 'الحضور الشهري';

  @override
  String get colName => 'الاسم';

  @override
  String get colMother => 'الأم';

  @override
  String get colBirthday => 'الميلاد';

  @override
  String get colAttendance => 'الحضور';

  @override
  String get colReason => 'السبب';

  @override
  String get notMarked => 'غير محدد';

  @override
  String get sessionLabel => 'الجلسة';

  @override
  String get rosterLabel => 'القائمة';

  @override
  String get noSheetForDay => 'لا يوجد سجل';

  @override
  String get attended => 'حضر';

  @override
  String get totalRegistrations => 'التسجيلات';

  @override
  String get byGender => 'حسب الجنس';

  @override
  String get byNationality => 'حسب الجنسية';

  @override
  String get byAgeGroup => 'حسب الفئة العمرية';

  @override
  String get attendanceRate => 'نسبة الحضور (30 يوماً)';

  @override
  String get servicesDelivered => 'الخدمات المقدمة';

  @override
  String get kpiPendingPush => 'بانتظار الإرسال';

  @override
  String get kpiDuplicates => 'بحاجة إلى معالجة';

  @override
  String get kpiTodayAttendance => 'أيام الحضور اليوم';

  @override
  String get moduleDisabled => 'لا يملك حسابك صلاحية الوصول إلى هذه الوحدة.';

  @override
  String serverError(String message) {
    return 'خطأ في الخادم: $message';
  }

  @override
  String get networkError =>
      'تعذر الوصول إلى الخادم. تحقق من الاتصال وعنوان الخادم.';

  @override
  String get sessionExpired => 'انتهت جلستك. يرجى تسجيل الدخول مجدداً.';

  @override
  String get loadingReference => 'جارٍ تنزيل البيانات المرجعية…';

  @override
  String get bootstrapRequired =>
      'لم يتم تنزيل البيانات المرجعية بعد. اتصل بالإنترنت وقم بتحديث كامل.';

  @override
  String get aboutSync =>
      'يتحقق خادم BMA-NFE من كل سجل تنشئه دون اتصال عند إرساله. لا تُنشأ التكرارات بصمت: أنت تقرر الدمج أو الربط أو الإنشاء.';

  @override
  String items(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count عناصر',
      one: 'عنصر واحد',
    );
    return '$_temp0';
  }

  @override
  String get openRecord => 'فتح السجل';

  @override
  String reportFor(String id) {
    return 'الدفعة $id';
  }

  @override
  String get noHistory => 'لا توجد دفعات مزامنة بعد.';

  @override
  String get fixAndRetry => 'تصحيح وإعادة المحاولة';

  @override
  String get viewServerErrors => 'رسائل التحقق من الخادم';

  @override
  String get sectionOther => 'أخرى';

  @override
  String get yes => 'نعم';

  @override
  String get no => 'لا';

  @override
  String get unknown => 'غير معروف';

  @override
  String get childAge => 'العمر';

  @override
  String get childNumber => 'رقم السجل';

  @override
  String get unicefId => 'معرّف اليونيسف';

  @override
  String get registeredAt => 'مسجل في';

  @override
  String matchReason(String reason) {
    return 'التطابق: $reason';
  }

  @override
  String welcome(String name) {
    return 'مرحباً، $name';
  }

  @override
  String get deviceInfo => 'الجهاز';

  @override
  String get version => 'الإصدار';

  @override
  String get clearLocalData => 'مسح البيانات المحلية';

  @override
  String get clearLocalDataWarning =>
      'سيؤدي هذا إلى إزالة جميع السجلات المنزّلة والعمل غير المرسل من هذا الجهاز. ستُفقد التغييرات المعلّقة.';

  @override
  String get gradings => 'التقييمات والدرجات';

  @override
  String get referral => 'الإحالة';

  @override
  String get followUp => 'المتابعة';

  @override
  String get schoolProfile => 'ملف المدرسة';

  @override
  String get teacherForm => 'المعلم';

  @override
  String get deleteConfirm => 'حذف هذا السجل؟';

  @override
  String get confirmRegistration => 'تأكيد التسجيل';

  @override
  String get resolvedLocally => 'تم حفظ القرار. أرسل مرة أخرى لتطبيقه.';

  @override
  String get noTeachers => 'لم يُسجل معلمون بعد.';

  @override
  String get viewReport => 'عرض التقرير';

  @override
  String serverRecordId(String id) {
    return 'سجل الخادم رقم $id';
  }

  @override
  String get total => 'المجموع';

  @override
  String get chooseCandidate => 'اختر السجل الموجود المطابق';

  @override
  String get attendanceDays => 'أيام الحضور';

  @override
  String get needsResolution => 'سجلات بحاجة إلى قرارك';

  @override
  String get noPendingWork => 'كل شيء على هذا الجهاز متزامن.';

  @override
  String get fieldDifferences => 'الحقول المختلفة';

  @override
  String get localOnlyHint => 'أُنشئ على هذا الجهاز ولم يُرسل إلى الخادم بعد.';

  @override
  String get selectionIncomplete => 'اختر جميع المرشحات أولاً.';

  @override
  String teachersPresent(int count) {
    return '$count حاضر';
  }

  @override
  String monthSummary(int present, int absent) {
    return '$present حاضر · $absent غائب';
  }

  @override
  String get tipsTitle => 'دليل البدء';

  @override
  String tipsStep(int current, int total) {
    return 'الخطوة $current من $total';
  }

  @override
  String get skip => 'تخطي';

  @override
  String get done => 'تم';

  @override
  String get gotIt => 'فهمت';

  @override
  String get tipsShowAgain => 'عرض النصائح مرة أخرى';

  @override
  String get tipsDataReady => 'البيانات المرجعية موجودة على هذا الجهاز.';

  @override
  String get tipsWelcomeTitle => 'يعمل دون إنترنت';

  @override
  String get tipsWelcomeBody =>
      'يُحفظ كل شيء على هذا الجهاز أولاً: سجّل الأطفال ودوّن الخدمات وخذ الحضور دون اتصال. يبقى كل تغيير «قيد الانتظار» حتى ترسله إلى خادم BMA-NFE. يظهر شريط في أعلى الشاشة عندما تكون غير متصل.';

  @override
  String get tipsDataTitle => 'بياناتك على هذا الجهاز';

  @override
  String get tipsDataBody =>
      'عند تسجيل الدخول نزّل التطبيق البيانات المرجعية (المراكز والجولات والبرامج والنماذج) والسجلات التي يحق لحسابك رؤيتها. إذا ظهر تحذير في الشاشة الرئيسية، اتصل بالإنترنت وقم بتحديث كامل. يستطيع آخر حساب سجّل الدخول على هذا الجهاز الدخول دون اتصال.';

  @override
  String get tipsRegisterTitle => 'تسجيل طفل';

  @override
  String get tipsRegisterBody =>
      'ابحث في قائمة المستفيدين أولاً لتجنب التكرار. اضغط «تسجيل جديد» واتبع الخطوات: الهوية، مقدمو الرعاية والأسرة، ثم المراجعة والتأكيد. الأسماء والجنس وتاريخ الميلاد والجنسية حقول مطلوبة؛ انسخ رقم الهوية كما هو مكتوب في الوثيقة.';

  @override
  String get tipsDailyTitle => 'الخدمات والحضور';

  @override
  String get tipsDailyBody =>
      'افتح ملف الطفل واضغط «إضافة خدمة» لتسجيل نموذج خدمة. للحضور: اختر المركز أو المدرسة والجولة والبرنامج والتاريخ، واضغط «تحميل الأطفال»، ثم «تحديد الجميع حاضرين»، وحوّل الغائبين إلى «غائب» مع سبب الغياب، ثم احفظ.';

  @override
  String get tipsPushTitle => 'الإرسال وقراءة التقرير';

  @override
  String get tipsPushBody =>
      'عند الاتصال، افتح «مركز المزامنة» واضغط «إرسال التغييرات». يتحقق الخادم من كل سجل ويعيد نتيجة: تم الإنشاء، تم التحديث، تم الدمج، تم الربط، مكرر، تعارض، خطأ أو تم التخطي. افتح «تقرير الإرسال» لمعرفة السبب. عند الخطأ تظهر رسائل الخادم في النموذج: صحّح وأعد المحاولة.';

  @override
  String get tipsResolveTitle => 'التكرارات والتعارضات';

  @override
  String get tipsResolveBody =>
      'يقارن الخادم كل تسجيل بالأطفال الموجودين: معرّف اليونيسف، والأسماء مع تاريخ الميلاد والجنس، وأرقام الهوية، والتطابقات القريبة. أنت تقرر من «مركز المزامنة»: دمج في السجل الموجود، أو نفس الطفل تسجيل جديد، أو إنشاء على أي حال، أو إهمال. وعند التعارض: استبدال نسخة الخادم أو الاحتفاظ بها.';

  @override
  String get tipsSafeTitle => 'حافظ على أمان بياناتك';

  @override
  String get tipsSafeBody =>
      'العمل غير المرسل موجود على هذا الجهاز فقط: أرسل التغييرات كل يوم تتوفر فيه شبكة، ولا تمسح البيانات المحلية وفيها تغييرات معلّقة. يحتوي هذا التطبيق على بيانات شخصية لأطفال: لا تشارك حسابك مع أحد. بدّل اللغة من «الإعدادات». أعد فتح هذا الدليل من أيقونة «؟» في الشاشة الرئيسية.';

  @override
  String get tipHomeSync =>
      'أرسل التغييرات كلما توفر اتصال. يعرض الرقم على أيقونة السحابة العمل الذي ينتظر الإرسال أو يحتاج إلى قرارك؛ اضغط عليها لفتح مركز المزامنة.';

  @override
  String get tipRegistrationsSearch =>
      'ابحث بالاسم أو رقم الهوية أو رقم السجل قبل التسجيل. تعرض الأيقونة في كل صف حالة المزامنة: قيد الانتظار، متزامن، مكرر، تعارض.';

  @override
  String get tipAttendanceFlow =>
      'اختر المركز أو المدرسة والجولة والبرنامج والتاريخ، ثم اضغط «تحميل الأطفال». حدد الجميع حاضرين، وحوّل الغائبين إلى «غائب» مع سبب الغياب، ثم احفظ. استخدم «يوم عطلة» لإغلاق يوم.';

  @override
  String get tipSyncCenter =>
      'يتطلب «إرسال التغييرات» و«تنزيل التحديثات» اتصالاً بالإنترنت؛ ولا يستبدل التنزيل عملك غير المرسل أبداً. السجلات التي تحتاج إلى قرارك مدرجة أدناه؛ اضغط على أحدها لمعالجته.';

  @override
  String get setupTitle => 'إعداد الخادم';

  @override
  String get setupIntro =>
      'حدّد لهذا الجهاز خادم BMA-NFE الذي سيتصل به. راجع منسّق البرنامج إذا لم تكن متأكداً.';

  @override
  String get setupTestConnection => 'اختبار الاتصال';

  @override
  String get setupConnectionOk =>
      'تم الاتصال. يعمل على هذا الخادم واجهة BMA-NFE للتطبيق.';

  @override
  String get setupConnectionNotBma =>
      'استجاب العنوان، لكن واجهة BMA-NFE للتطبيق غير مثبّتة عليه. تحقق من العنوان.';

  @override
  String get setupConnectionFailed =>
      'تعذّر الوصول إلى هذا العنوان. تحقق من كتابته ومن اتصالك بالإنترنت.';

  @override
  String get setupInvalidUrl =>
      'أدخل عنوان موقع، مثل https://bma-nfe.example.org';

  @override
  String get setupContinue => 'متابعة';

  @override
  String get setupChangeLater => 'يمكنك تغيير الخادم لاحقاً من «الإعدادات».';

  @override
  String get centerProfile => 'ملف المركز';

  @override
  String get profileNoCenter => 'حسابك غير مرتبط بمركز.';

  @override
  String get profileNoSchool => 'حسابك غير مرتبط بمدرسة.';

  @override
  String get profileNotDownloaded =>
      'تصل التفاصيل مع البيانات المرجعية. اتصل بالإنترنت وقم بتحديث كامل.';

  @override
  String get partner => 'الشريك';

  @override
  String get governorate => 'المحافظة';

  @override
  String get district => 'القضاء';

  @override
  String get cadaster => 'المنطقة العقارية';

  @override
  String get facilityType => 'النوع';

  @override
  String get programmes => 'البرامج';

  @override
  String get packagesOffered => 'الخدمات المتاحة';

  @override
  String get statusLabel => 'الحالة';

  @override
  String get activeLabel => 'نشط';

  @override
  String get inactiveLabel => 'غير نشط';

  @override
  String get schoolNumber => 'رقم المدرسة';

  @override
  String get bmaSchool => 'مدرسة BMA';

  @override
  String get closedLabel => 'مغلقة';

  @override
  String get openLabel => 'مفتوحة';

  @override
  String get workingDays => 'أيام الدوام';

  @override
  String get weekendLabel => 'العطلة الأسبوعية';

  @override
  String get coordinates => 'الإحداثيات';

  @override
  String get locationLabel => 'الموقع';

  @override
  String get atAGlance => 'نظرة سريعة';

  @override
  String get quickActions => 'إجراءات سريعة';

  @override
  String get yourProgrammes => 'برامجك';

  @override
  String get registeredChildren => 'الأطفال المسجلون';

  @override
  String get notRecorded => 'غير مسجل';

  @override
  String get viewProfile => 'عرض الملف';

  @override
  String get selectBeneficiary => 'اختر مستفيدًا لعرض ملفه.';

  @override
  String get switchModule => 'تبديل البرنامج';

  @override
  String get unsavedChanges => 'مغادرة النموذج؟ ستفقد التغييرات غير المحفوظة.';

  @override
  String get analytics => 'التحليلات';

  @override
  String get analyticsHubIntro =>
      'لوحات محسوبة من السجلات المنزّلة على هذا الجهاز. تنطبق عوامل التصفية على ما هو مخزّن محلياً.';

  @override
  String get advancedAnalytics => 'التحليلات المتقدمة';

  @override
  String get advancedAnalyticsDescription =>
      'التسجيلات والمعلمون والمراكز والبرامج: الاتجاه والتوزيعات وجدول متقاطع للبرنامج حسب الفئة العمرية.';

  @override
  String get alpRegistrationInsights => 'مؤشرات التسجيل';

  @override
  String get alpRegistrationInsightsDescription =>
      'التسجيلات ونتائج التعلم وأرقام الأسرة والدمج والانتقال.';

  @override
  String get alpTeacherDashboard => 'لوحة المعلمين';

  @override
  String get alpTeacherDashboardDescription =>
      'تغطية الكادر التعليمي والقدرة التدريسية والتطوير المهني.';

  @override
  String get alpAttendanceDashboard => 'لوحة الحضور';

  @override
  String get alpAttendanceDashboardDescription =>
      'خرائط حرارية للحضور حسب الشهر واليوم للسنة المختارة، إجمالاً ولكل برنامج.';

  @override
  String get alpSchoolDashboard => 'لوحة المدارس';

  @override
  String get alpSchoolDashboardDescription =>
      'مواقع المدارس على الخريطة مع أعداد الطلاب والمعلمين والتفاصيل التشغيلية.';

  @override
  String get noAnalyticsForModule =>
      'لا تتوفر لوحات تحليلية لهذا البرنامج بعد.';

  @override
  String get filters => 'عوامل التصفية';

  @override
  String get dateFrom => 'من';

  @override
  String get dateTo => 'إلى';

  @override
  String get anyDate => 'أي تاريخ';

  @override
  String get allPartners => 'كل الشركاء';

  @override
  String get allCenters => 'كل المراكز';

  @override
  String get allProgrammes => 'كل البرامج';

  @override
  String get allSchools => 'كل المدارس';

  @override
  String get allRounds => 'كل الجولات';

  @override
  String get allNationalities => 'كل الجنسيات';

  @override
  String get allGenders => 'كل الأجناس';

  @override
  String get moreFilters => 'المزيد من عوامل التصفية';

  @override
  String get ageMin => 'الحد الأدنى للعمر';

  @override
  String get ageMax => 'الحد الأقصى للعمر';

  @override
  String get resetFilters => 'إعادة ضبط';

  @override
  String get yearLabel => 'السنة';

  @override
  String get partners => 'الشركاء';

  @override
  String get centers => 'المراكز';

  @override
  String get programmeLabel => 'البرنامج';

  @override
  String get ageGroup => 'الفئة العمرية';

  @override
  String get gender => 'الجنس';

  @override
  String get nationality => 'الجنسية';

  @override
  String get notSpecified => 'غير محدد';

  @override
  String get noDataForFilters => 'لا توجد بيانات لعوامل التصفية المختارة.';

  @override
  String registrationsCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count تسجيلاً',
      one: 'تسجيل واحد',
    );
    return '$_temp0';
  }

  @override
  String teachersCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count معلماً',
      one: 'معلم واحد',
    );
    return '$_temp0';
  }

  @override
  String childrenCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count طفلاً',
      one: 'طفل واحد',
    );
    return '$_temp0';
  }

  @override
  String percentOfTotal(String percent) {
    return '$percent٪ من الإجمالي';
  }

  @override
  String get showAll => 'عرض الكل';

  @override
  String get showLess => 'عرض أقل';

  @override
  String get offlineFiguresNote =>
      'الأرقام محسوبة من السجلات الموجودة على هذا الجهاز؛ نزّل التحديثات لتحديثها.';

  @override
  String get registrationTrend => 'اتجاه التسجيل';

  @override
  String get dailyRegistrations => 'التسجيلات اليومية';

  @override
  String dailyRegistrationsLastDays(int count) {
    return 'التسجيلات اليومية، آخر $count يوماً';
  }

  @override
  String get registrationsByCenter => 'التسجيلات حسب المركز';

  @override
  String get genderDistribution => 'التوزيع حسب الجنس';

  @override
  String get nationalityDistribution => 'التوزيع حسب الجنسية';

  @override
  String get teacherGenderDistribution => 'توزيع المعلمين حسب الجنس';

  @override
  String get teacherNationalityDistribution => 'توزيع المعلمين حسب الجنسية';

  @override
  String get teachersByCenter => 'المعلمون حسب المركز';

  @override
  String get programmeVsAgeGroup => 'البرنامج مقابل الفئة العمرية';

  @override
  String get programmeVsAgeGroupHint =>
      'التسجيلات حسب آخر برنامج والفئة العمرية؛ الخلايا الأغمق تضم أطفالاً أكثر.';

  @override
  String get operationalInsights => 'المؤشرات التشغيلية';

  @override
  String get activeSchools => 'المدارس النشطة';

  @override
  String get programRounds => 'جولات البرنامج';

  @override
  String get learningOutcomes => 'نتائج التعلم';

  @override
  String get learningOutcomesHint =>
      'أحدث نتائج التقييم والتقدم للأطفال في برنامج التعلم المسرّع.';

  @override
  String get childrenAssessed => 'الأطفال المقيَّمون';

  @override
  String get averageAchievement => 'متوسط التحصيل';

  @override
  String get followUpAssessments => 'تقييمات المتابعة';

  @override
  String get childrenImproving => 'الأطفال المتحسنون';

  @override
  String get latestPerformance => 'أحدث أداء';

  @override
  String get progressSinceFirst => 'التقدم منذ أول تقييم';

  @override
  String get achievementBySubject => 'التحصيل حسب المادة';

  @override
  String get bandOnTrack => 'على المسار';

  @override
  String get bandDeveloping => 'قيد التطور';

  @override
  String get bandNeedsSupport => 'بحاجة إلى دعم';

  @override
  String get progressImproved => 'تحسّن';

  @override
  String get progressStable => 'مستقر';

  @override
  String get progressDeclined => 'تراجع';

  @override
  String get noAssessments => 'لا تتوفر تقييمات تعلم لعوامل التصفية المختارة.';

  @override
  String get registrationsAndBeneficiaries => 'التسجيلات والمستفيدون';

  @override
  String get householdInclusionTransition => 'الأسرة والدمج والانتقال';

  @override
  String get genderAgeGroupDistribution => 'التوزيع حسب الجنس والفئة العمرية';

  @override
  String get nationalityBreakdown => 'التوزيع حسب الجنسية';

  @override
  String get sourceOfIdentification => 'مصدر التعريف';

  @override
  String get registrationsPerRound => 'التسجيلات لكل جولة';

  @override
  String get familyStatus => 'الحالة الأسرية';

  @override
  String get disabilityType => 'نوع الإعاقة';

  @override
  String get cashSupport => 'الدعم النقدي';

  @override
  String get referredToFormalEducation => 'المحالون إلى التعليم النظامي';

  @override
  String get noReferralRecords =>
      'لا توجد سجلات إحالة مخزّنة على هذا الجهاز لهؤلاء الأطفال.';

  @override
  String get childrenMovedBetweenRounds => 'الأطفال المنتقلون بين الجولات';

  @override
  String get movedFromEarlierRound => 'منتقلون من جولة سابقة';

  @override
  String get newInRound => 'جدد في هذه الجولة';

  @override
  String get male => 'ذكر';

  @override
  String get female => 'أنثى';

  @override
  String get teacherWorkforceInsights => 'مؤشرات الكادر التعليمي';

  @override
  String get totalTeachers => 'إجمالي المعلمين';

  @override
  String get teachersTrained => 'المعلمون المدرَّبون';

  @override
  String get averageExperience => 'متوسط الخبرة';

  @override
  String get yearsUnit => 'سنوات';

  @override
  String get averageTraining => 'متوسط التدريب';

  @override
  String get sessionsUnit => 'جلسات';

  @override
  String get contactCoverage => 'تغطية بيانات الاتصال';

  @override
  String get coverageAndDemographics => 'التغطية والخصائص الديموغرافية';

  @override
  String get teachingCapacityDevelopment => 'القدرة التدريسية والتطوير';

  @override
  String get assignment => 'التكليف';

  @override
  String get teachersBySchool => 'المعلمون حسب المدرسة';

  @override
  String get teachersByRound => 'المعلمون حسب الجولة';

  @override
  String get subjectsProvided => 'المواد المقدَّمة';

  @override
  String get gradeLevelsSupported => 'المستويات الدراسية المدعومة';

  @override
  String get trainingTopics => 'مواضيع التدريب';

  @override
  String get teachingHours => 'ساعات التدريس';

  @override
  String get extraCoaching => 'تدريب إضافي';

  @override
  String get alpHours => 'التعلم المسرّع';

  @override
  String get privateSchoolHours => 'مدرسة خاصة';

  @override
  String get hoursUnit => 'ساعات';

  @override
  String teachersTrainedShare(String percent) {
    return '$percent٪ من المعلمين';
  }

  @override
  String get noTeachersForFilters =>
      'لا يوجد معلمون يطابقون عوامل التصفية المختارة.';

  @override
  String get overallAttendance => 'الحضور الإجمالي';

  @override
  String get attendanceHeatmapHint =>
      'نسبة الحضور لكل يوم من كل شهر؛ الخلايا الأغمق أعلى. اضغط على خلية لعرض الأرقام.';

  @override
  String get attendanceByProgramme => 'الحضور حسب البرنامج';

  @override
  String get attendanceRateLabel => 'نسبة الحضور';

  @override
  String get noAttendanceForYear => 'لم يُسجَّل حضور لهذه السنة.';

  @override
  String heatmapCellDetail(
    String date,
    int present,
    int total,
    String percent,
  ) {
    return '$date: $present حاضر من $total ($percent٪)';
  }

  @override
  String get accessibleSchools => 'المدارس المتاحة';

  @override
  String get inReportingScope => 'ضمن نطاق تقاريرك';

  @override
  String get mappedSchools => 'المدارس على الخريطة';

  @override
  String get withGpsCoordinates => 'ذات إحداثيات GPS';

  @override
  String get alpStudents => 'طلاب التعلم المسرّع';

  @override
  String get activeRegistrations => 'التسجيلات النشطة';

  @override
  String get alpTeachers => 'معلمو التعلم المسرّع';

  @override
  String get acrossMappedSchools => 'في المدارس الموجودة على الخريطة';

  @override
  String get schoolLocations => 'مواقع مدارس التعلم المسرّع';

  @override
  String schoolsMapped(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count مدرسة على الخريطة',
      one: 'مدرسة واحدة على الخريطة',
    );
    return '$_temp0';
  }

  @override
  String get noMappedSchools => 'لا توجد مدارس ذات إحداثيات GPS لهذا الاختيار.';

  @override
  String get mapTilesOffline =>
      'تحتاج خلفية الخريطة إلى اتصال بالإنترنت؛ تبقى علامات المدارس في مواقعها حسب إحداثياتها.';

  @override
  String get mapAttribution => '© مساهمو OpenStreetMap';

  @override
  String get cerdNumber => 'رقم المركز التربوي';

  @override
  String get students => 'الطلاب';

  @override
  String get schoolStatus => 'الحالة';

  @override
  String get schoolClosed => 'مغلقة';

  @override
  String get schoolOpen => 'مفتوحة';

  @override
  String get operatingShift => 'الدوام';

  @override
  String get directorName => 'المدير';

  @override
  String get phoneLabel => 'الهاتف';

  @override
  String get digitalHub => 'مركز رقمي';

  @override
  String get adminStaff => 'الموظفون الإداريون';

  @override
  String get showOnMap => 'عرض على الخريطة';
}
