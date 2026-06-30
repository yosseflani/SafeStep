import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';

import 'screens/main_screen.dart';

/// נקודת הכניסה של האפליקציה.
void main() async {
  // אתחול Flutter לפני שימוש בשירותי המערכת.
  WidgetsFlutterBinding.ensureInitialized();

  runApp(const SafeStep());
}

/// ה־Widget הראשי של האפליקציה.
class SafeStep extends StatelessWidget {
  const SafeStep({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      // הסתרת חיווי DEBUG.
      debugShowCheckedModeBanner: false,

      title: 'Safe Step',

      // שפת ברירת המחדל של האפליקציה.
      locale: const Locale('he', 'IL'),

      // השפות הנתמכות.
      supportedLocales: const [
        Locale('he', 'IL'),
        Locale('en', 'US'),
      ],

      // תמיכה בלוקליזציה של Flutter.
      localizationsDelegates: const [
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],

      // שימוש קבוע בערכת נושא כהה.
      themeMode: ThemeMode.dark,

      theme: ThemeData(
        useMaterial3: true,

        brightness: Brightness.dark,

        scaffoldBackgroundColor: const Color(0xFF0F1115),

        // יצירת סכמת צבעים המבוססת על צבע ראשי.
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFFFF7A00),
          brightness: Brightness.dark,
        ),
      ),

      // מסך הפתיחה של האפליקציה.
      home: const MainScreen(),
    );
  }
}