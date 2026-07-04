import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';

import 'screens/main_screen.dart';
import 'utils/app_colors.dart';

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



      theme: ThemeData(
        useMaterial3: true,

        scaffoldBackgroundColor: backgroundColor,

        // סכמת צבעים מותאמת לערכת הצבעים הראשית.
        colorScheme: ColorScheme.fromSeed(
          seedColor: primaryColor,
        ),
      ),

      // מסך הפתיחה של האפליקציה.
      home: const MainScreen(),
    );
  }
}