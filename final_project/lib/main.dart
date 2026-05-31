import 'package:flutter/material.dart';
// ייבוא ספריית UI של Flutter

import 'package:flutter_localizations/flutter_localizations.dart';
// ייבוא תמיכה בשפות שונות (כולל RTL)

import 'screens/main_screen.dart';
// ייבוא המסך הראשי של האפליקציה


void main() async {
  // פונקציית התחלה של האפליקציה

  WidgetsFlutterBinding.ensureInitialized();
  // מאתחל את Flutter (חובה לפני פעולות async או plugins)


  runApp(const SafeStep());
  // מפעיל את האפליקציה עם ה-Widget הראשי SafeStep
}

class SafeStep extends StatelessWidget {
  // מחלקת האפליקציה הראשית (ללא state)

  const SafeStep({super.key});
  // constructor

  @override
  Widget build(BuildContext context) {
    // בונה את האפליקציה

    return MaterialApp(
      // ה-Widget הראשי שמגדיר את כל האפליקציה

      debugShowCheckedModeBanner: false,
      // מסתיר את ה-DEBUG banner

      title: 'Safe Step',
      // שם האפליקציה

      // תמיכה רב-לשונית - עברית ואנגלית כולל כיוון RTL
      locale: const Locale('he', 'IL'),
      // שפה ברירת מחדל: עברית

      supportedLocales: const [
        Locale('he', 'IL'),
        Locale('en', 'US'),
      ],
      // שפות נתמכות

      localizationsDelegates: const [
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      // מאפשר ל-Flutter לתמוך בתרגום ורכיבים לפי שפה

      // ערכת נושא כהה עקבית עם שאר האפליקציה
      themeMode: ThemeMode.dark,
      // תמיד מצב כהה

      theme: ThemeData(
        useMaterial3: true,
        // שימוש בעיצוב Material 3

        brightness: Brightness.dark,
        // מצב כהה

        scaffoldBackgroundColor: const Color(0xFF0F1115),
        // צבע רקע כללי

        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFFFF7A00),
          // צבע ראשי (כתום)

          brightness: Brightness.dark,
          // מתאים למצב כהה
        ),
      ),

      home: const MainScreen(),
      // המסך הראשון שמוצג למשתמש
    );
  }
}