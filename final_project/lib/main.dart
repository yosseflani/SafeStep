import 'package:flutter/material.dart'; // ייבוא ספריית Material של Flutter - כוללת את כל רכיבי ה-UI הבסיסיים

import 'package:flutter_localizations/flutter_localizations.dart'; // ייבוא ספריית לוקליזציה - תמיכה בריבוי שפות וכיווניות

import 'screens/main_screen.dart'; // ייבוא המסך הראשי של האפליקציה

/// נקודת הכניסה של האפליקציה
/// הפונקציה הראשונה שרצה כשהאפליקציה מופעלת
void main() async { // async - הפונקציה יכולה להכיל פעולות אסינכרוניות (ממתינות)

  WidgetsFlutterBinding.ensureInitialized(); // אתחול Flutter לפני שימוש בשירותים - חובה לפני MethodChannel, SharedPreferences וכו'

  runApp(const SafeStep()); // מפעיל את האפליקציה עם ה-widget הראשי SafeStep
}

/// מחלקת האפליקציה הראשית
/// StatelessWidget - widget שלא משתנה בזמן ריצה (ללא state דינמי)
class SafeStep extends StatelessWidget {
  const SafeStep({super.key}); // קונסטרקטור עם key לניהול זיהוי ה-widget בעץ

  @override
  Widget build(BuildContext context) { // הפונקציה שבונה את ה-UI של האפליקציה
    // context - מספק מידע על מיקום ה-widget בעץ

    return MaterialApp( // MaterialApp הוא ה-widget הראשי - מספק ניווט, עיצוב, לוקליזציה וכו'

      debugShowCheckedModeBanner: false, // מסיר את הסרט "DEBUG" בפינה העליונה ימנית

      title: 'Safe Step', // שם האפליקציה שמופיע ב-Recent Apps ובמנהל המשימות

      locale: const Locale('he', 'IL'), // מגדיר את השפה הנוכחית לעברית (ישראל)
      // Locale מקבל קוד שפה (he) וקוד מדינה (IL)

      supportedLocales: const [ // רשימה של כל השפות שהאפליקציה תומכת בהן
        Locale('he', 'IL'), // עברית (ישראל)
        Locale('en', 'US'), // אנגלית (ארה"ב)
      ],

      localizationsDelegates: const [ // delegates - מחלקות שמספקות תרגומים ועיצובים לפי שפה
        GlobalMaterialLocalizations.delegate, // תרגומים לרכיבי Material Design (כפתורים, טקסטים וכו')
        GlobalWidgetsLocalizations.delegate, // תרגומים ל-widgets בסיסיים של Flutter
        GlobalCupertinoLocalizations.delegate, // תרגומים לרכיבי iOS (Cupertino)
      ],

      themeMode: ThemeMode.dark, // מגדיר שהאפליקציה תמיד תהיה במצב כהה (לא משתנה לפי הגדרות המכשיר)

      theme: ThemeData( // ThemeData - מגדיר את כל ערכת הנושא של האפליקציה

        useMaterial3: true, // מפעיל את הגרסה העדכנית של Material Design (עיצוב מודרני)

        brightness: Brightness.dark, // מגדיר שהעיצוב יהיה כהה (רקע כהה, טקסט בהיר)

        scaffoldBackgroundColor: const Color(0xFF0F1115), // צבע הרקע של Scaffold
        // 0xFF = שקיפות מלאה, 0F1115 = צבע כהה כחלחל

        colorScheme: ColorScheme.fromSeed( // יוצר סכמת צבעים אוטומטית מצבע בסיס (seed)
          seedColor: const Color(0xFFFF7A00), // צבע בסיס: כתום - Flutter ייצור אוטומטית גוונים שונים
          brightness: Brightness.dark, // מתאים את סכמת הצבעים למצב כהה
        ),
      ),

      home: const MainScreen(), // המסך הראשון שמופיע כשהאפליקציה נפתחת
    );
  }
}