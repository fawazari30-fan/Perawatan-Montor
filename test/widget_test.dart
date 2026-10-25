import 'package:flutter_test/flutter_test.dart';
import 'package:projfawaz/app.dart';

void main() {
  testWidgets('shows the setup guidance before backend configuration', (
    tester,
  ) async {
    await tester.pumpWidget(const MotorCareApp(supabaseConfigured: false));
    expect(find.text('Rawat Motor'), findsOneWidget);
    expect(find.textContaining('Supabase belum dikonfigurasi'), findsOneWidget);
  });
}
