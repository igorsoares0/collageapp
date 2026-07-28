/// Where the legal pages live. Google Play requires a reachable privacy
/// policy URL on the store listing, and the same pages are linked from
/// Settings so a user can find them without leaving the app.
///
/// Same build-time knob as `kApiBase` (see `api/template_api.dart`): the pages
/// are served by the `collageweb` deployment, so pointing the app at a
/// different site is a `--dart-define-from-file` away.
///   flutter build --dart-define-from-file=env/prod.json
const String kSiteBase = String.fromEnvironment(
  'SITE_BASE',
  defaultValue: 'http://localhost:3000',
);

const String kPrivacyPolicyUrl = '$kSiteBase/privacy';
const String kTermsUrl = '$kSiteBase/terms';
