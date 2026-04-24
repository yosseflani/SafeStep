import 'package:flutter/foundation.dart';
// ייבוא כלים בסיסיים של Flutter
// kDebugMode = האם האפליקציה רצה במצב debug
// debugPrint = הדפסה נוחה ללוגים

import 'package:speech_to_text/speech_to_text.dart';
// ייבוא הספרייה לזיהוי דיבור

class VoiceCommandService {
  // מחלקה שאחראית על כל הלוגיקה של זיהוי הפקודות הקוליות
  // בלי קשר ישיר ל-UI

  final SpeechToText _speech = SpeechToText();
  // מנוע זיהוי הדיבור

  bool _isListening = false;
  // משתנה פנימי ששומר האם כרגע אנחנו במצב האזנה

  Function()? _onErrorCallback;
  // callback חיצוני שמסך אחר יכול להעביר
  // למשל כדי להפעיל מחדש את ההאזנה אוטומטית אם קרתה שגיאה

  bool get isListening => _isListening;
  // getter לקריאה בלבד - מאפשר למחלקות אחרות לדעת
  // אם כרגע המנוע מאזין

  Future<bool> initialize() async {
    // פונקציה שמאתחלת את מנוע זיהוי הדיבור
    // מחזירה true אם השירות זמין, אחרת false

    final available = await _speech.initialize(
      debugLogging: true,
      // מפעיל לוגים פנימיים של הספרייה
      // מאוד עוזר בזמן בדיקות ותקלות

      onStatus: (status) {
        // callback שנקרא בכל שינוי מצב של מנוע הדיבור

        if (kDebugMode) debugPrint('Speech status: $status');

        if (status == 'notListening' || status == 'done') {
          // אם המנוע סיים או כבר לא מאזין
          _isListening = false;
        } else if (status == 'listening') {
          // אם התחיל להאזין
          _isListening = true;
        }
      },

      onError: (error) {
        // callback שנקרא אם יש שגיאה בזיהוי דיבור

        if (kDebugMode) {
          debugPrint('Speech error msg: ${error.errorMsg}');
          debugPrint('Speech error permanent: ${error.permanent}');
        }

        _isListening = false;
        // אם קרתה שגיאה - מעדכנים שכבר לא מאזינים

        // אם מדובר בשגיאת רשת - מחכים קצת לפני ניסיון restart
        if (error.errorMsg.contains('network')) {
          Future.delayed(const Duration(seconds: 3), () {
            _onErrorCallback?.call();
          });
        } else {
          // בכל שגיאה אחרת - מפעילים מיד את ה-callback אם קיים
          _onErrorCallback?.call();
        }
      },
    );

    if (kDebugMode) {
      debugPrint('Speech initialize available: $available');
      debugPrint('Speech isAvailable: ${_speech.isAvailable}');
      debugPrint('Speech isListening: ${_speech.isListening}');
    }

    // אם השירות זמין - נביא גם מידע על השפות הנתמכות
    if (available) {
      final locales = await _speech.locales();
      final systemLocale = await _speech.systemLocale();

      if (kDebugMode) {
        debugPrint('System locale: ${systemLocale?.localeId}');
        debugPrint('Supported locales:');

        for (final locale in locales) {
          debugPrint(' - ${locale.localeId} / ${locale.name}');
        }
      }
    } else {
      if (kDebugMode) {
        debugPrint('Speech recognition is NOT available on this device');
      }
    }

    return available;
  }

  Future<void> startListening(
      Function(String) onCommand, {
        required String localeId,
        Function()? onError,
      }) async {
    // פונקציה שמתחילה האזנה לדיבור
    //
    // onCommand = פונקציה חיצונית שמקבלת את הטקסט שזוהה
    // localeId = השפה בה מאזינים, למשל:
    // he-IL לעברית
    // en-US לאנגלית
    // onError = callback אופציונלי לשגיאות

    if (!_speech.isAvailable) {
      // אם השירות לא זמין - לא ננסה בכלל להתחיל האזנה
      if (kDebugMode) debugPrint('Speech is not available');
      return;
    }

    if (_isListening) {
      // אם כבר מאזינים - לא מפעילים האזנה נוספת
      if (kDebugMode) debugPrint('Speech already listening');
      return;
    }

    _onErrorCallback = onError;
    // שומרים את ה-callback כדי ש-onError של initialize יוכל להשתמש בו

    _isListening = true;
    // מעדכנים ידנית שהתחילה האזנה

    if (kDebugMode) {
      debugPrint('Starting speech listening with locale: $localeId');
    }

    await _speech.listen(
      onResult: (result) {
        // callback שנקרא בכל פעם שיש תוצאה מהדיבור
        // זה יכול להיות גם partial וגם final

        if (kDebugMode) {
          debugPrint(
            'recognizedWords: ${result.recognizedWords}, finalResult: ${result.finalResult}',
          );
        }

        // אם התקבלה תוצאה סופית ויש טקסט לא ריק
        if (result.finalResult && result.recognizedWords.isNotEmpty) {
          onCommand(result.recognizedWords);
          // שולחים את הטקסט החוצה לטיפול במסך הראשי
        }
      },

      listenMode: ListenMode.dictation,
      // מצב dictation מתאים למשפטים חופשיים יותר
      // אם בעתיד תרצה רק פקודות קצרות, אפשר לבדוק גם מצבים אחרים

      localeId: localeId,
      // שפת ההאזנה
      // חשוב מאוד לשלוח ערך תקין כמו he-IL ולא he_IL

      pauseFor: const Duration(seconds: 5),
      // אם יש שקט של 5 שניות - המנוע יפסיק להאזין

      listenFor: const Duration(seconds: 30),
      // זמן מקסימלי של סשן האזנה אחד

      cancelOnError: false,
      // אם יש שגיאה, לא מבטלים את כל המנוע אוטומטית
      // אנחנו מטפלים בזה דרך onError

      partialResults: true,
      // מאפשר לקבל תוצאות חלקיות תוך כדי דיבור

      onDevice: true,
      // מבקש לעבוד על המכשיר עצמו בלי אינטרנט
      // שים לב: זה תלוי אם המכשיר באמת תומך בזה
    );
  }

  Future<void> stopListening() async {
    // פונקציה שעוצרת את ההאזנה הנוכחית

    if (!_isListening) {
      // אם המנוע לא מאזין כרגע - לא עושים כלום
      return;
    }

    _onErrorCallback = null;
    // מנקים callback כדי שלא תקרה הפעלה חוזרת בטעות
    // אחרי עצירה מכוונת

    await _speech.stop();
    // עוצר את זיהוי הדיבור

    _isListening = false;
    // מעדכן את המצב הפנימי
  }
}