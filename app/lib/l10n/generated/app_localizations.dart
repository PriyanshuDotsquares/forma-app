import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:intl/intl.dart' as intl;

import 'app_localizations_en.dart';
import 'app_localizations_hi.dart';

// ignore_for_file: type=lint

/// Callers can lookup localized strings with an instance of AppLocalizations
/// returned by `AppLocalizations.of(context)`.
///
/// Applications need to include `AppLocalizations.delegate()` in their app's
/// `localizationDelegates` list, and the locales they support in the app's
/// `supportedLocales` list. For example:
///
/// ```dart
/// import 'generated/app_localizations.dart';
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

  static AppLocalizations? of(BuildContext context) {
    return Localizations.of<AppLocalizations>(context, AppLocalizations);
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
    Locale('en'),
    Locale('hi'),
  ];

  /// No description provided for @introTitle1.
  ///
  /// In en, this message translates to:
  /// **'It watches every rep.'**
  String get introTitle1;

  /// No description provided for @introBody1.
  ///
  /// In en, this message translates to:
  /// **'Prop your phone. FORMA counts your reps, measures your depth, and tells you what to fix — out loud, while you lift.'**
  String get introBody1;

  /// No description provided for @introTitle2.
  ///
  /// In en, this message translates to:
  /// **'Coaching that speaks up.'**
  String get introTitle2;

  /// No description provided for @introBody2.
  ///
  /// In en, this message translates to:
  /// **'A voice coach calls out corrections in real time, so you fix your form on the next rep, not after the fact.'**
  String get introBody2;

  /// No description provided for @introTitle3.
  ///
  /// In en, this message translates to:
  /// **'Progress you can see.'**
  String get introTitle3;

  /// No description provided for @introBody3.
  ///
  /// In en, this message translates to:
  /// **'Volume, recovery, strength, and form quality — tracked automatically from every set you log.'**
  String get introBody3;

  /// No description provided for @skip.
  ///
  /// In en, this message translates to:
  /// **'SKIP'**
  String get skip;

  /// No description provided for @getStarted.
  ///
  /// In en, this message translates to:
  /// **'Get started'**
  String get getStarted;

  /// No description provided for @alreadyHaveAccount.
  ///
  /// In en, this message translates to:
  /// **'I already have an account'**
  String get alreadyHaveAccount;

  /// No description provided for @createAccountTitle.
  ///
  /// In en, this message translates to:
  /// **'CREATE ACCOUNT'**
  String get createAccountTitle;

  /// No description provided for @signUpTab.
  ///
  /// In en, this message translates to:
  /// **'SIGN UP'**
  String get signUpTab;

  /// No description provided for @signInTab.
  ///
  /// In en, this message translates to:
  /// **'SIGN IN'**
  String get signInTab;

  /// No description provided for @emailLabel.
  ///
  /// In en, this message translates to:
  /// **'EMAIL'**
  String get emailLabel;

  /// No description provided for @passwordLabel.
  ///
  /// In en, this message translates to:
  /// **'PASSWORD'**
  String get passwordLabel;

  /// No description provided for @passwordStrong.
  ///
  /// In en, this message translates to:
  /// **'Strong'**
  String get passwordStrong;

  /// No description provided for @passwordGood.
  ///
  /// In en, this message translates to:
  /// **'Good'**
  String get passwordGood;

  /// No description provided for @passwordWeak.
  ///
  /// In en, this message translates to:
  /// **'Weak'**
  String get passwordWeak;

  /// No description provided for @passwordReq8Chars.
  ///
  /// In en, this message translates to:
  /// **'At least 8 characters'**
  String get passwordReq8Chars;

  /// No description provided for @passwordReqNumber.
  ///
  /// In en, this message translates to:
  /// **'One number'**
  String get passwordReqNumber;

  /// No description provided for @createAccountButton.
  ///
  /// In en, this message translates to:
  /// **'CREATE ACCOUNT'**
  String get createAccountButton;

  /// No description provided for @signInButton.
  ///
  /// In en, this message translates to:
  /// **'SIGN IN'**
  String get signInButton;

  /// No description provided for @verificationNotice.
  ///
  /// In en, this message translates to:
  /// **'We\'ll send a verification link to your inbox.'**
  String get verificationNotice;

  /// No description provided for @forgotPassword.
  ///
  /// In en, this message translates to:
  /// **'Forgot password?'**
  String get forgotPassword;

  /// No description provided for @tabToday.
  ///
  /// In en, this message translates to:
  /// **'TODAY'**
  String get tabToday;

  /// No description provided for @tabPlan.
  ///
  /// In en, this message translates to:
  /// **'PROGRAMS'**
  String get tabPlan;

  /// No description provided for @tabCoach.
  ///
  /// In en, this message translates to:
  /// **'COACHING'**
  String get tabCoach;

  /// No description provided for @tabProgress.
  ///
  /// In en, this message translates to:
  /// **'PROGRESS'**
  String get tabProgress;

  /// No description provided for @tabProfile.
  ///
  /// In en, this message translates to:
  /// **'PROFILE'**
  String get tabProfile;

  /// No description provided for @settingsTitle.
  ///
  /// In en, this message translates to:
  /// **'Settings'**
  String get settingsTitle;

  /// No description provided for @sectionTraining.
  ///
  /// In en, this message translates to:
  /// **'Training'**
  String get sectionTraining;

  /// No description provided for @sectionCoachCamera.
  ///
  /// In en, this message translates to:
  /// **'Coach & Camera'**
  String get sectionCoachCamera;

  /// No description provided for @sectionApp.
  ///
  /// In en, this message translates to:
  /// **'App'**
  String get sectionApp;

  /// No description provided for @sectionAccount.
  ///
  /// In en, this message translates to:
  /// **'Account'**
  String get sectionAccount;

  /// No description provided for @rowGoalsExperience.
  ///
  /// In en, this message translates to:
  /// **'Goals & experience'**
  String get rowGoalsExperience;

  /// No description provided for @rowSchedule.
  ///
  /// In en, this message translates to:
  /// **'Schedule'**
  String get rowSchedule;

  /// No description provided for @rowEquipment.
  ///
  /// In en, this message translates to:
  /// **'Equipment'**
  String get rowEquipment;

  /// No description provided for @rowInjuries.
  ///
  /// In en, this message translates to:
  /// **'Injuries & limits'**
  String get rowInjuries;

  /// No description provided for @rowVoiceCoach.
  ///
  /// In en, this message translates to:
  /// **'Voice coach'**
  String get rowVoiceCoach;

  /// No description provided for @rowCameraPrivacy.
  ///
  /// In en, this message translates to:
  /// **'Camera & privacy'**
  String get rowCameraPrivacy;

  /// No description provided for @rowRestTimer.
  ///
  /// In en, this message translates to:
  /// **'Rest timer'**
  String get rowRestTimer;

  /// No description provided for @rowAppearance.
  ///
  /// In en, this message translates to:
  /// **'Appearance'**
  String get rowAppearance;

  /// No description provided for @rowUnits.
  ///
  /// In en, this message translates to:
  /// **'Units'**
  String get rowUnits;

  /// No description provided for @rowNotifications.
  ///
  /// In en, this message translates to:
  /// **'Notifications'**
  String get rowNotifications;

  /// No description provided for @rowLanguage.
  ///
  /// In en, this message translates to:
  /// **'Language'**
  String get rowLanguage;

  /// No description provided for @rowEmail.
  ///
  /// In en, this message translates to:
  /// **'Email'**
  String get rowEmail;

  /// No description provided for @rowPassword.
  ///
  /// In en, this message translates to:
  /// **'Password'**
  String get rowPassword;

  /// No description provided for @rowSignOut.
  ///
  /// In en, this message translates to:
  /// **'Sign out'**
  String get rowSignOut;

  /// No description provided for @rowDeleteAccount.
  ///
  /// In en, this message translates to:
  /// **'Delete account'**
  String get rowDeleteAccount;

  /// No description provided for @onboardingContinue.
  ///
  /// In en, this message translates to:
  /// **'Continue'**
  String get onboardingContinue;

  /// No description provided for @onboardingSkipStep.
  ///
  /// In en, this message translates to:
  /// **'Skip this step'**
  String get onboardingSkipStep;

  /// No description provided for @onboardingNothingToReport.
  ///
  /// In en, this message translates to:
  /// **'NOTHING TO REPORT'**
  String get onboardingNothingToReport;

  /// No description provided for @onboardingBuildMyPlan.
  ///
  /// In en, this message translates to:
  /// **'Build my plan'**
  String get onboardingBuildMyPlan;

  /// No description provided for @step1Title.
  ///
  /// In en, this message translates to:
  /// **'What are you training for?'**
  String get step1Title;

  /// No description provided for @step2Title.
  ///
  /// In en, this message translates to:
  /// **'How much lifting have you done?'**
  String get step2Title;

  /// No description provided for @step3Title.
  ///
  /// In en, this message translates to:
  /// **'A few numbers.'**
  String get step3Title;

  /// No description provided for @step4LocationTitle.
  ///
  /// In en, this message translates to:
  /// **'Where do you train?'**
  String get step4LocationTitle;

  /// No description provided for @step4EquipmentTitle.
  ///
  /// In en, this message translates to:
  /// **'What can you train with?'**
  String get step4EquipmentTitle;

  /// No description provided for @step5Title.
  ///
  /// In en, this message translates to:
  /// **'How often can you train?'**
  String get step5Title;

  /// No description provided for @step6Title.
  ///
  /// In en, this message translates to:
  /// **'How should we split your week?'**
  String get step6Title;

  /// No description provided for @step7Title.
  ///
  /// In en, this message translates to:
  /// **'Anything we should work around?'**
  String get step7Title;

  /// No description provided for @step8Title.
  ///
  /// In en, this message translates to:
  /// **'Here\'s what we heard.'**
  String get step8Title;

  /// No description provided for @step9Title.
  ///
  /// In en, this message translates to:
  /// **'BUILDING YOUR PLAN.'**
  String get step9Title;
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
      <String>['en', 'hi'].contains(locale.languageCode);

  @override
  bool shouldReload(_AppLocalizationsDelegate old) => false;
}

AppLocalizations lookupAppLocalizations(Locale locale) {
  // Lookup logic when only language code is specified.
  switch (locale.languageCode) {
    case 'en':
      return AppLocalizationsEn();
    case 'hi':
      return AppLocalizationsHi();
  }

  throw FlutterError(
    'AppLocalizations.delegate failed to load unsupported locale "$locale". This is likely '
    'an issue with the localizations generation tool. Please file an issue '
    'on GitHub with a reproducible sample app and the gen-l10n configuration '
    'that was used.',
  );
}
