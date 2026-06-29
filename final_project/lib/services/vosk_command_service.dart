import 'dart:async'; // ייבוא ספריית async של Dart - מספקת Stream, StreamSubscription, Future וכו'

import 'dart:convert'; // ייבוא ספריית json של Dart - מספקת jsonDecode, jsonEncode וכו'

import 'package:flutter/foundation.dart'; // ייבוא ספריית foundation של Flutter - כולל kDebugMode, debugPrint

import 'package:vosk_flutter/vosk_flutter.dart'; // ייבוא ספריית Vosk - ספרייה לזיהוי דיבור offline (ללא אינטרנט)

/// שירות לזיהוי פקודות קוליות באמצעות Vosk.
/// מחלקה שמנהלת את כל הלוגיקה של זיהוי דיבור והמרה לפקודות
class VoskCommandService {
  /// קצב דגימת האודיו הנדרש למודל.
  static const int _sampleRate = 16000; // קצב דגימה של 16kHz - סטנדרטי לזיהוי דיבור

  /// נתיב מודל הזיהוי מתוך תיקיית assets.
  static const String _modelAssetPath = // נתיב לקובץ המודל הדחוס
      'assets/models/vosk-model-small-en-us-0.15.zip'; // מודל אנגלית קטן (15MB) - מתאים למכשירים ניידים

  /// מופע הפלאגין הראשי של Vosk.
  final VoskFlutterPlugin _vosk = VoskFlutterPlugin.instance(); // singleton - מופע יחיד של הפלאגין

  /// אחראי על טעינת המודל מתוך assets.
  final ModelLoader _modelLoader = ModelLoader(); // מחלקה שטוענת קבצים מ-assets לנתיב זמין במכשיר

  Model? _model; // מודל Vosk שנטען - nullable כי מתחיל כ-null
  Recognizer? _recognizer; // מזהה דיבור שמשתמש במודל - nullable
  SpeechService? _speechService; // שירות שמקליט מהמיקרופון ומזהה דיבור - nullable

  /// מנוי לתוצאות הזיהוי מהשירות.
  StreamSubscription<String>? _resultSubscription; // מנוי ל-stream של תוצאות זיהוי - מאפשר לבטל האזנה

  bool _isInitialized = false; // דגל שמציין אם השירות אותחל בהצלחה
  bool _isListening = false; // דגל שמציין אם מתבצעת האזנה כעת

  /// מציין האם השירות אותחל בהצלחה.
  bool get isInitialized => _isInitialized; // getter - מאפשר לקרוא את המשתנה הפרטי מחוץ למחלקה

  /// מציין האם מתבצעת האזנה כעת.
  bool get isListening => _isListening; // getter - מאפשר לבדוק אם המיקרופון פעיל

  /// טוען את מודל Vosk ומכין את שירות הזיהוי הקולי.
  /// פונקציה אסינכרונית שטוענת את המודל, יוצרת recognizer ומכינה את שירות הדיבור
  Future<bool> initialize() async { // מחזיר true אם הצליח, false אם נכשל
    _debug('initialize()'); // הדפסת הודעת debug

    try { // בלוק try-catch לטיפול בשגיאות
      final modelPath = await _modelLoader.loadFromAssets(_modelAssetPath); // טעינת המודל מ-assets לנתיב זמני
      // await - ממתין שהטעינה תסתיים (יכול לקחת כמה שניות)

      _model = await _vosk.createModel(modelPath); // יצירת מודל Vosk מהקובץ שנטען
      // המודל מכיל את רשת הניירונים לזיהוי דיבור

      _recognizer = await _vosk.createRecognizer( // יצירת recognizer שמשתמש במודל
        model: _model!, // העברת המודל שנוצר (! = force unwrap - אנחנו בטוחים שהוא לא null)
        sampleRate: _sampleRate, // העברת קצב דגימה

        /// הגבלת הזיהוי לפקודות הרלוונטיות לאפליקציה.
        grammar: [ // רשימת מילים/פקודות שהמודל יזהה - משפר דיוק ומהירות
          'start', // התחל
          'stop', // עצור
          'help', // עזרה
          'repeat', // חזור
          'home', // בית
          'emergency', // חירום
          'settings', // הגדרות
          'yes', // כן
          'no', // לא
          'vibration on', // הפעל רטט
          'vibration off', // כבה רטט
        ],
      );

      _speechService = await _vosk.initSpeechService(_recognizer!); // יצירת שירות דיבור שמקליט מהמיקרופון
      // השירות לוקח את האודיו מהמיקרופון ומעביר אותו ל-recognizer

      _isInitialized = true; // עדכון הדגל שהאתחול הצליח

      _debug('Vosk initialized successfully'); // הדפסת הודעת הצלחה
      return true; // החזרת true - אתחול הצליח
    } catch (e) { // תפיסת שגיאות - e = השגיאה
      _debug('initialize error: $e'); // הדפסת פרטי השגיאה
      return false; // החזרת false - אתחול נכשל
    }
  }

  /// מתחיל האזנה לפקודות קוליות ומחזיר כל פקודה מזוהה דרך callback.
  /// מקבל פונקציה שתקרא בכל פעם שזוהית פקודה
  Future<void> startListening(Function(String command) onCommand) async { // onCommand - callback שנקרא עם הפקודה שזוהתה
    if (!_isInitialized || _speechService == null) { // בדיקה שהשירות אותחל
      _debug('Vosk is not initialized'); // הדפסת הודעת שגיאה
      return; // יציאה מהפונקציה
    }

    if (_isListening) { // בדיקה שכבר לא מקשיבים (למנוע האזנה כפולה)
      _debug('already listening'); // הדפסת הודעה
      return; // יציאה
    }

    await _resultSubscription?.cancel(); // ביטול מנוי קיים אם יש (? = null-aware operator)
    // מונע דליפת זיכרון ממנויים ישנים

    _resultSubscription = _speechService!.onResult().listen((result) { // האזנה ל-stream של תוצאות
      // onResult() מחזיר Stream שפולט תוצאת זיהוי בכל פעם שיש זיהוי חדש
      // .listen() - נרשם לקבלת התוצאות

      final command = _extractCommand(result); // חילוץ הטקסט מהתוצאה (JSON)

      if (command.isNotEmpty) { // בדיקה שזוהית פקודה (לא ריקה)
        onCommand(command); // קריאה ל-callback עם הפקודה שזוהתה
      }
    });

    await _speechService!.start(); // התחלת הקלטה מהמיקרופון
    // await - ממתין שההפעלה תסתיים

    _isListening = true; // עדכון הדגל שמקשיבים

    _debug('listening started'); // הדפסת הודעה
  }

  /// עוצר את ההאזנה ומשחרר את מנוי התוצאות.
  /// חובה לקרוא כשרוצים להפסיק להקשיב לפקודות
  Future<void> stopListening() async {
    if (!_isListening || _speechService == null) return; // בדיקה שמקשיבים ויש שירות

    await _speechService!.stop(); // עצירת ההקלטה מהמיקרופון

    await _resultSubscription?.cancel(); // ביטול המנוי ל-stream - מפסיק לקבל תוצאות
    _resultSubscription = null; // איפוס המנוי (מונע דליפת זיכרון)

    _isListening = false; // עדכון הדגל שלא מקשיבים יותר

    _debug('listening stopped'); // הדפסת הודעה
  }

  /// ניקוי משאבים בעת סגירת השירות.
  /// חובה לקרוא כשמסיימים להשתמש בשירות - מונע דליפת זיכרון
  Future<void> dispose() async {
    await stopListening(); // עצירת האזנה ושחרור מנויים
  }

  /// חילוץ טקסט הפקודה מתוך תוצאת JSON של Vosk.
  /// מקבל מחרוזת JSON ומחזיר את הטקסט שזוהה
  String _extractCommand(String result) { // פונקציה פרטית (מתחיל ב-_)
    try { // בלוק try-catch לטיפול בשגיאות JSON
      final json = jsonDecode(result); // המרה ממחרוזת JSON ל-Map/List
      // jsonDecode - פונקציה מ-dart:convert

      final text = json['text']; // חילוץ שדה 'text' מה-JSON
      // Vosk מחזיר JSON כמו: {"text": "start", "confidence": 0.95}

      if (text is String) { // בדיקה ש-text הוא אכן מחרוזת
        return text.trim().toLowerCase(); // החזרת הטקסט נקי: ללא רווחים מיותרים ובאותיות קטנות
        // trim() - מסיר רווחים בהתחלה ובסוף
        // toLowerCase() - ממיר לאותיות קטנות (למשל "START" → "start")
      }

      return ''; // אם text לא String - החזרת מחרוזת ריקה
    } catch (_) { // תפיסת שגיאות - _ = מתעלמים מהשגיאה
      return ''; // אם יש שגיאה ב-JSON - החזרת מחרוזת ריקה
    }
  }

  /// הדפסת הודעות פיתוח בלבד.
  /// פונקציה פנימית שמדפיסה רק במצב debug
  void _debug(String msg) { // פרמטר: הודעה להדפסה
    if (!kDebugMode) return; // אם לא במצב debug - יציאה מהפונקציה
    // kDebugMode - משתנה גלובלי מ-Flutter שמציין אם רצים במצב פיתוח

    debugPrint('[VoskCommandService] $msg'); // הדפסה בפורמט: [שם השירות] הודעה
    // debugPrint - פונקציה מ-Flutter שמדפיסה לקונסול (בטוחה יותר מ-print)
  }
}