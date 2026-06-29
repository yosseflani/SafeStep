import 'dart:typed_data'; // ייבוא ספריית typed_data של Dart - מספקת טיפוסים כמו Uint8List לטיפול בנתונים בינאריים

import 'package:flutter/foundation.dart'; // ייבוא ספריית foundation של Flutter - כולל כלים כמו kDebugMode, debugPrint וכו'

import 'package:flutter_vision/flutter_vision.dart'; // ייבוא ספריית FlutterVision - ספרייה להרצת מודלי YOLO לזיהוי אובייקטים

import '../models/detection.dart'; // ייבוא המחלקה Detection שמייצגת אובייקט מזוהה

/// שירות להרצת מודל YOLO וזיהוי אובייקטים מתוך פריימים מהמצלמה.
/// מחלקה שמנהלת את כל הלוגיקה של זיהוי אובייקטים בזמן אמת
class YoloService {
  /// מופע הספרייה האחראית על טעינת והרצת מודל הזיהוי.
  final FlutterVision _vision = FlutterVision(); // יוצר מופע של FlutterVision - הספרייה שמריצה את מודל YOLO

  /// מציין האם מודל הזיהוי נטען בהצלחה.
  bool isLoaded = false; // דגל שמציין אם המודל מוכן לשימוש - מתחיל כ-false

  /// סף חפיפה לסינון תיבות זיהוי כפולות.
  static const double _iouThreshold = 0.4; // IoU = Intersection over Union - סף לחפיפה בין תיבות זיהוי
  // אם שתי תיבות חופפות ביותר מ-40%, רק אחת תישמר (מונע זיהוי כפול)

  /// סף ביטחון מינימלי לקבלת זיהוי.
  static const double _confThreshold = 0.35; // ביטחון מינימלי של 35% כדי לקבל זיהוי - מונע זיהויים לא בטוחים

  /// סף ביטחון מינימלי לסיווג האובייקט.
  static const double _classThreshold = 0.35; // סף דומה ל-confThreshold - משמש לסיווג סוג האובייקט

  /// תגיות האובייקטים הרלוונטיות למערכת ההתראות.
  static const Set<String> allowedTags = { // Set - אוסף של ערכים ייחודיים (ללא כפילויות)
    'crosswalk', // מעבר חצייה
    'person', // אדם
    'car', // מכונית
    'motorcycle', // אופנוע
    'pole', // עמוד
    'couch', // ספה
    'bench', // ספסל
  };

  /// טעינת מודל YOLO וקובץ התוויות מתוך assets.
  /// פונקציה אסינכרונית שטוענת את המודל רק פעם אחת
  Future<void> initModel() async { // async - פונקציה אסינכרונית שיכולה להשתמש ב-await
    _debug('initModel()'); // קריאה לפונקציית debug מותאמת

    if (isLoaded) { // בדיקה אם המודל כבר נטען
      _debug('Model already loaded'); // הדפסת הודעה שהמודל כבר קיים
      return; // יציאה מהפונקציה - אין צורך לטעון שוב
    }

    try { // בלוק try-catch לטיפול בשגיאות
      await _vision.loadYoloModel( // await - ממתין שהטעינה תסתיים לפני המשך
        labels: 'assets/safestep_labels.txt', // קובץ תוויות - רשימת שמות האובייקטים שהמודל מזהה
        modelPath: 'assets/safestep_yolo.tflite', // קובץ המודל עצמו בפורמט TensorFlow Lite
        modelVersion: 'yolov8', // גרסת המודל - YOLOv8
        numThreads: 2, // מספר תהליכונים מקבילים להרצה (2 = מהיר יותר)
        useGpu: false, // לא משתמש ב-GPU (רק CPU) - מתאים למכשירים ניידים
      );

      isLoaded = true; // עדכון הדגל שהמודל נטען בהצלחה

      _debug('Model loaded successfully'); // הדפסת הודעת הצלחה
    } catch (e, stack) { // תפיסת שגיאות - e = השגיאה, stack = מחסנית הקריאות
      isLoaded = false; // עדכון הדגל שהטעינה נכשלה

      _debug('Model load failed: $e\n$stack'); // הדפסת פרטי השגיאה
      rethrow; // זריקת השגיאה הלאה - מי שקרא לפונקציה יצטרך לטפל בה
    }
  }

  /// מריץ זיהוי על פריים ומחזיר רשימת אובייקטים מזוהים.
  /// מקבל פריים מהמצלמה ומחזיר רשימה של Detection
  Future<List<Detection>> detectObjects( // מחזיר Future של רשימת Detection
      List<Uint8List> bytesList, // רשימת פריימים בפורמט בינארי (Uint8List)
      int imageHeight, // גובה התמונה בפיקסלים
      int imageWidth, // רוחב התמונה בפיקסלים
          {
        double? confThreshold, // פרמטר אופציונלי - סף ביטחון מותאם (אם null - משתמש בברירת המחדל)
      }) async {
    if (!isLoaded || bytesList.isEmpty || imageHeight <= 0 || imageWidth <= 0) { // בדיקת תקינות קלט
      _debug('Invalid input or model not loaded'); // הדפסת הודעת שגיאה
      return const []; // החזרת רשימה ריקה (const - אופטימיזציה)
    }

    /// שימוש בסף ביטחון מותאם, או בברירת המחדל.
    final activeConf = confThreshold ?? _confThreshold; // ?? - אם confThreshold null, משתמש ב-_confThreshold

    try { // בלוק try-catch לטיפול בשגיאות
      final results = await _vision.yoloOnFrame( // הרצת זיהוי על הפריים - ממתין לתוצאה
        bytesList: bytesList, // העברת הפריימים
        imageHeight: imageHeight, // העברת גובה
        imageWidth: imageWidth, // העברת רוחב
        iouThreshold: _iouThreshold, // העברת סף חפיפה
        confThreshold: activeConf, // העברת סף ביטחון
        classThreshold: _classThreshold, // העברת סף סיווג
      );

      final detections = <Detection>[]; // יצירת רשימה ריקה של Detection - תכיל את התוצאות המסוננות

      int filteredByTag = 0; // מונה - כמה אובייקטים נפסלו בגלל תגית לא מורשית
      int filteredByBox = 0; // מונה - כמה אובייקטים נפסלו בגלל תיבה לא תקינה
      int filteredByConf = 0; // מונה - כמה אובייקטים נפסלו בגלל ביטחון נמוך

      for (final raw in results) { // לולאה על כל תוצאה גולמית מהמודל
        /// חילוץ וניקוי שם האובייקט שזוהה.
        final tag = (raw['tag'] ?? '').toString().trim().toLowerCase(); // חילוץ tag, המרה ל-string, הסרת רווחים, המרה לאותיות קטנות

        /// חילוץ תיבת הזיהוי: [left, top, right, bottom, confidence].
        final rawBox = (raw['box'] as List?) ?? const []; // חילוץ box - אם null, רשימה ריקה

        if (tag.isEmpty) continue; // אם tag ריק - דילוג על האיבר הזה

        if (rawBox.length < 5) { // בדיקה שיש לפחות 5 ערכים (4 קואורדינטות + ביטחון)
          filteredByBox++; // הגדלת מונה הסינון
          continue; // דילוג
        }

        final confidence = (rawBox[4] as num).toDouble(); // חילוץ הביטחון (אינדקס 4) והמרה ל-double

        if (confidence < activeConf) { // בדיקה אם הביטחון נמוך מהסף
          filteredByConf++; // הגדלת מונה הסינון
          continue; // דילוג
        }

        if (!allowedTags.contains(tag)) { // בדיקה אם התגית לא ברשימת התגיות המורשות
          filteredByTag++; // הגדלת מונה הסינון
          continue; // דילוג
        }

        /// המרת הזיהוי הגולמי לאובייקט Detection פנימי של האפליקציה.
        detections.add( // הוספת אובייקט Detection לרשימה
          Detection( // יצירת אובייקט Detection חדש
            tag: tag, // העברת התגית
            confidence: confidence, // העברת הביטחון
            box: [ // יצירת רשימת קואורדינטות
              (rawBox[0] as num).toDouble(), // left - המרה ל-double
              (rawBox[1] as num).toDouble(), // top - המרה ל-double
              (rawBox[2] as num).toDouble(), // right - המרה ל-double
              (rawBox[3] as num).toDouble(), // bottom - המרה ל-double
            ],
          ),
        );
      }

      if (kDebugMode && results.isNotEmpty) { // בדיקה אם רצים במצב debug ויש תוצאות
        _debug( // הדפסת סטטיסטיקות סינון
          'raw=${results.length} accepted=${detections.length} ' // כמה תוצאות גולמיות וכמה התקבלו
              '(filtered: tag=$filteredByTag ' // כמה נפסלו בגלל תגית
              'conf=$filteredByConf box=$filteredByBox)', // כמה נפסלו בגלל ביטחון ותיבה
        );
      }

      return detections; // החזרת הרשימה המסוננת
    } catch (e, stack) { // תפיסת שגיאות
      _debug('Detection error: $e\n$stack'); // הדפסת פרטי השגיאה
      return const []; // החזרת רשימה ריקה במקרה של שגיאה
    }
  }

  /// סגירת מודל הזיהוי ושחרור משאבים.
  /// חובה לקרוא כשמסיימים להשתמש במודל - מונע דליפת זיכרון
  Future<void> dispose() async {
    if (!isLoaded) return; // אם המודל לא נטען - אין צורך לסגור

    try { // בלוק try-catch
      await _vision.closeYoloModel(); // סגירת המודל - משחרר זיכרון
      isLoaded = false; // עדכון הדגל שהמודל לא נטען יותר

      _debug('Model closed'); // הדפסת הודעת סגירה
    } catch (e, stack) { // תפיסת שגיאות
      _debug('Dispose error: $e\n$stack'); // הדפסת פרטי השגיאה
    }
  }

  /// מחזיר מידע בסיסי לצורכי בדיקה ופיתוח.
  /// שימושי ל-debug ובדיקת מצב השירות
  Map<String, dynamic> getDebugInfo() => { // מחזיר Map עם מידע דינמי
    'isLoaded': isLoaded, // מצב הטעינה
    'iouThreshold': _iouThreshold, // סף חפיפה
    'confThreshold': _confThreshold, // סף ביטחון
    'classThreshold': _classThreshold, // סף סיווג
    'allowedTagsCount': allowedTags.length, // מספר התגיות המורשות
  };

  /// הדפסת הודעות פיתוח בלבד.
  /// פונקציה פנימית שמדפיסה רק במצב debug
  void _debug(String msg) { // פרמטר: הודעה להדפסה
    if (!kDebugMode) return; // אם לא במצב debug - יציאה מהפונקציה

    final time = DateTime.now() // קבלת הזמן הנוכחי
        .toIso8601String() // המרה לפורמט ISO 8601 (למשל: 2024-01-15T14:30:45.123)
        .split('T') // פיצול לפי T - מפריד בין תאריך לשעה
        .last // לקיחת החלק האחרון (השעה)
        .split('.') // פיצול לפי נקודה - מפריד בין שעה למילישניות
        .first; // לקיחת החלק הראשון (שעה ללא מילישניות)

    debugPrint('[YoloService][$time] $msg'); // הדפסה בפורמט: [שם השירות][שעה] הודעה
  }
}