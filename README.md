# RoutePass 路由通

Network engineering quiz app (Android, Flutter + Dart).

M0 status: empty shell only. The app opens, shows a splash page, a login
page skeleton (mock login, no backend yet), and a home page with a bottom
navigation bar (Home / Question Bank / Knowledge Base / Toolbox). The
question bank, knowledge base, and toolbox pages are "coming soon"
placeholders for V2 / V3 / V4.

- Package: `com.netstudy.routepass` (debug builds use `.demo` suffix:
  `com.netstudy.routepass.demo`)
- Version: 0.1.0+1
- Flutter: 3.47.9 (stable)

## Build

Pushing to `main` or `dev` triggers GitHub Actions
(`.github/workflows/build-apk.yml`): `flutter analyze`, `flutter test`,
then `flutter build apk --debug`. The APK is uploaded as the
`routepass-apk-debug` artifact.

Local development needs only the Flutter SDK (no Android SDK, no local
build): `flutter pub get`, `flutter analyze`, `flutter test`.

See the v3.0 unified plan for the full V1-V4 design.
