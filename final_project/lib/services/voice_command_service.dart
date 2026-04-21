import 'package:flutter/foundation.dart';
// ייבוא כלים בסיסיים של Flutter (למשל kDebugMode ו-debugPrint)

import 'package:speech_to_text/speech_to_text.dart';
// ייבוא ספרייה לזיהוי דיבור

class VoiceCommandService {
  // מחלקה שמנהלת פקודות קוליות (Service, לא UI)

  final SpeechToText _speech = SpeechToText();
  // אובייקט של מנוע זיהוי דיבור

  bool _isListening = false;
  // מצב פנימי: האם כרגע מאזינים

  bool get isListening => _isListening;
  // getter שמאפשר לקרוא את המצב מבחוץ (בלי לשנות)

  Future<bool> initialize() async {
    // אתחול מנוע הדיבור (אסינכרוני)

    final available = await _speech.initialize(
      // מפעיל את המנוע ומחזיר אם הוא זמין

      onStatus: (status) {
        // מתעדכן בכל שינוי מצב של המנוע

        if (kDebugMode) debugPrint('Speech status: $status');
        // מדפיס לוג רק במצב פיתוח

        if (status == 'notListening' || status == 'done') {
          _isListening = false;
          // אם הפסיק להאזין → מעדכן ל-false
        } else if (status == 'listening') {
          _isListening = true;
          // אם התחיל להאזין → true
        }
      },

      onError: (error) {
        // אם יש שגיאה בזיהוי

        if (kDebugMode) debugPrint('Speech error: $error');
        // מדפיס שגיאה

        _isListening = false;
        // מבטל מצב האזנה
      },
    );

    return available;
    // מחזיר אם השירות זמין או לא
  }

  Future<void> startListening(
      Function(String) onCommand, {
        required String localeId,
      }) async {
    // פונקציה שמתחילה האזנה לדיבור
    // onCommand = פונקציה שתטפל בטקסט שזוהה
    // localeId = שפה (למשל he-IL)

    if (!_speech.isAvailable) return;
    // אם השירות לא זמין → יוצא

    if (_isListening) return;
    // אם כבר מאזין → לא מתחיל שוב

    _isListening = true;
    // מסמן שהתחילה האזנה

    await _speech.listen(
      // מתחיל להאזין בפועל

      onResult: (result) {
        // נקרא כל פעם שיש תוצאה מהדיבור

        if (kDebugMode) {
          debugPrint(
            'recognizedWords: ${result.recognizedWords}, finalResult: ${result.finalResult}',
          );
          // מדפיס את הטקסט והאם זו תוצאה סופית
        }

        if (result.finalResult && result.recognizedWords.isNotEmpty) {
          // אם זו תוצאה סופית ויש טקסט

          onCommand(result.recognizedWords);
          // מפעיל את הפונקציה עם הטקסט שנאמר
        }
      },

      listenMode: ListenMode.dictation,
      // מצב האזנה חופשי (משפטים, לא רק פקודות קצרות)

      localeId: localeId,
      // שפת ההאזנה

      pauseFor: const Duration(seconds: 4),
      // מפסיק אם יש שקט של 4 שניות

      listenFor: const Duration(seconds: 20),
      // זמן מקסימלי להאזנה

      cancelOnError: true,
      // אם יש שגיאה → מפסיק

      partialResults: true,
      // מאפשר לקבל תוצאות חלקיות תוך כדי דיבור
    );
  }

  Future<void> stopListening() async {
    // פונקציה לעצירת האזנה

    if (!_isListening) return;
    // אם לא מאזין → לא עושה כלום

    await _speech.stop();
    // עוצר את המנוע

    _isListening = false;
    // מעדכן מצב
  }
}