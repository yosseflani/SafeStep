import 'package:flutter/material.dart';
// ייבוא רכיבי UI של Flutter

import 'package:flutter_test/flutter_test.dart';
// ספרייה לבדיקות (Widget Testing)

import 'package:final_project/main.dart';
// מייבא את האפליקציה הראשית (שם מוגדר SafeStep)

void main() {
  testWidgets('SafeStep loading smoke test', (WidgetTester tester) async {
    // בדיקת smoke test - בודקת שהאפליקציה עולה בלי לקרוס

    // בניית האפליקציה והזרקת פריים ראשון
    // הערה: בגלל שהמצלמה והמודל דורשים חומרה,
    // הבדיקה תעצור במסך הטעינה

    await tester.pumpWidget(const MaterialApp(home: SafeStep()));
    // מריץ את האפליקציה בתוך סביבת בדיקה

    // בדיקה אם מופיע טקסט של טעינה
    // זה אומר שהאפליקציה נבנתה בהצלחה

    expect(find.textContaining('מכין'), findsOneWidget);
    // מחפש טקסט שמכיל "מכין" (למשל "מכין מערכת...")

    // בדיקה שקיים Spinner (עיגול טעינה)
    expect(find.byType(CircularProgressIndicator), findsOneWidget);
    // מוודא שיש אינדיקציה ויזואלית לטעינה
  });
}