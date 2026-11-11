import 'package:flutter_test/flutter_test.dart';

import 'package:routepass/app.dart';

void main() {
  testWidgets('smoke test: splash navigates to login page', (tester) async {
    await tester.pumpWidget(const RoutePassApp());

    await tester.pump(const Duration(milliseconds: 1000));
    await tester.pumpAndSettle();

    expect(find.text('登录'), findsWidgets);
  });
}
