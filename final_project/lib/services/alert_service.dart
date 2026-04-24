import 'package:flutter/foundation.dart';
// ייבוא כלים כמו debugPrint ו-kDebugMode

import 'package:flutter_tts/flutter_tts.dart';
// ספרייה להמרת טקסט לדיבור (Text To Speech)

import '../models/detection.dart';
// ייבוא מודל Detection (האובייקט שזוהה)

class AlertService {
  // מחלקה שאחראית על כל ההתראות הקוליות

  final FlutterTts _tts = FlutterTts();
  // אובייקט של מנוע דיבור

  String _language = 'he-IL';
  // שפה נוכחית

  double _speechRate = 0.5;
  // מהירות דיבור

  bool _voiceAlertsEnabled = true;
  // האם התראות קוליות מופעלות

  // מעקב אחר סטטוס דיבור
  bool _isSpeaking = false;
  // האם כרגע יש דיבור פעיל

  bool get isSpeaking => _isSpeaking;
  // מאפשר לבדוק מבחוץ אם מדברים

  Detection? _pendingHighPriorityAlert;
  // התראה חשובה שממתינה (אם צריך לדבר עליה אחרי הנוכחית)

  Future<void> initialize({
    required String language,
    required double speechRate,
    required bool voiceAlertsEnabled,
  }) async {
    // אתחול ראשוני של השירות

    _language = language;
    _speechRate = speechRate.clamp(0.1, 2.0);
    // מגביל את מהירות הדיבור לטווח תקין

    _voiceAlertsEnabled = voiceAlertsEnabled;

    await _safeSetLanguage(_language);
    // מגדיר שפה בצורה בטוחה

    await _tts.setSpeechRate(_speechRate);
    // מגדיר מהירות דיבור

    await _tts.awaitSpeakCompletion(true);
    // מחכה שהדיבור יסתיים לפני המשך
  }

  Future<void> updateSettings({
    required String language,
    required double speechRate,
    required bool voiceAlertsEnabled,
  }) async {
    // עדכון הגדרות בזמן ריצה

    _language = language;
    _speechRate = speechRate.clamp(0.1, 2.0);
    _voiceAlertsEnabled = voiceAlertsEnabled;

    await _safeSetLanguage(_language);
    await _tts.setSpeechRate(_speechRate);
  }

  // מגדיר שפה בצורה בטוחה עם fallback לאנגלית
  Future<void> _safeSetLanguage(String language) async {
    try {
      final result = await _tts.setLanguage(language);
      // מנסה להגדיר שפה

      if (result != 1 && kDebugMode) {
        debugPrint('Warning: Language $language not fully supported');
      }
    } catch (e) {
      if (kDebugMode) debugPrint('TTS language error: $e');
      await _tts.setLanguage('en-US');
      // fallback לאנגלית אם יש שגיאה
    }
  }

  Future<void> speakSystemStarted() async {
    // משמיע הודעה כשהמערכת מתחילה

    if (!_voiceAlertsEnabled) return;

    await _tts.speak(
      _language.startsWith('he') ? 'המערכת הופעלה' : 'System started',
    );
  }

  Future<void> speakSystemStopped() async {
    // משמיע הודעה כשהמערכת נעצרת

    if (!_voiceAlertsEnabled) return;

    await _tts.speak(
      _language.startsWith('he') ? 'המערכת הופסקה' : 'System stopped',
    );
  }

  // בדיקת קול - עובדת תמיד גם אם התראות כבויות
  Future<void> speakVoiceTest() async {
    await _tts.speak(
      _language.startsWith('he') ? 'זוהי בדיקת קול' : 'This is a voice test',
    );
  }

  /// השמעת התראה עם לוגיקה חכמה
  Future<bool> trySpeakDetection(Detection detection, {double? currentRisk}) async {
    if (!_voiceAlertsEnabled) return false;
    // אם התראות כבויות → לא מדבר

    if (_isSpeaking) {
      final newRisk = detection.riskScore;

      if (kDebugMode) {
        debugPrint('🔊 Speak attempt: ${detection.tag} '
            '(risk: ${newRisk.toStringAsFixed(1)}), '
            'currentRisk: ${currentRisk?.toStringAsFixed(1)}');
      }

      // אם הסיכון לא גבוה משמעותית → לא קוטע
      if (currentRisk != null && newRisk < currentRisk + 30) {

        // שומר כהתראה ממתינה אם היא הכי מסוכנת
        if (_pendingHighPriorityAlert == null ||
            newRisk > _pendingHighPriorityAlert!.riskScore) {
          _pendingHighPriorityAlert = detection;
        }

        return false;
      }

      // אם כן מסוכן → קוטע את הדיבור הנוכחי
      await _tts.stop();
    }

    _isSpeaking = true;

    try {
      await _tts.speak(_buildMessage(detection));
      // מדבר את ההודעה

      if (kDebugMode) {
        debugPrint('🔊 Speaking: ${detection.tag} '
            '(risk: ${detection.riskScore.toStringAsFixed(1)})');
      }

      return true;
    } catch (e) {
      if (kDebugMode) debugPrint('TTS speak error: $e');
      return false;
    } finally {
      _isSpeaking = false;

      // אם יש התראה ממתינה → מדבר אותה עכשיו
      if (_pendingHighPriorityAlert != null) {
        final pending = _pendingHighPriorityAlert!;
        _pendingHighPriorityAlert = null;

        await Future.delayed(const Duration(milliseconds: 200));
        // המתנה קטנה בין דיבורים

        await trySpeakDetection(pending, currentRisk: 0);
      }
    }
  }

  // איפוס סטטוס דיבור
  void resetSpeakingState() {
    _isSpeaking = false;
    _pendingHighPriorityAlert = null;
  }

  // בונה את המשפט שמדברים
  String _buildMessage(Detection detection) {
    final localizedObject = _localizedLabel(detection.tag);
    final severity = _severityText(detection.riskScore);
    return '$localizedObject $severity';
  }

  // פונקציות ציבוריות לשימוש חיצוני
  String localizedLabel(String tag) => _localizedLabel(tag);
  String severityText(double riskScore) => _severityText(riskScore);

  // תרגום שם האובייקט
  String _localizedLabel(String tag) {
    if (_language.startsWith('he')) {
      switch (tag) {
      // רכבים
        case 'car': return 'מכונית';
        case 'bus': return 'אוטובוס';
        case 'truck': return 'משאית';
        case 'train': return 'רכבת';
        case 'motorcycle': return 'אופנוע';

      // אנשים ותחבורה קלה
        case 'person': return 'אדם';
        case 'bicycle': return 'אופניים';
        case 'skateboard': return 'סקייטבורד';

      // תמרורים ותשתית
        case 'traffic light': return 'רמזור';
        case 'stop sign': return 'תמרור עצור';
        case 'fire hydrant': return 'ברז כיבוי אש';

      // בעלי חיים
        case 'dog': return 'כלב';
        case 'cat': return 'חתול';
        case 'horse': return 'סוס';
        case 'sheep': return 'כבשה';
        case 'cow': return 'פרה';
        case 'elephant': return 'פיל';
        case 'bear': return 'דוב';
        case 'zebra': return 'זברה';
        case 'giraffe': return 'ג\'ירפה';
        case 'bird': return 'ציפור';

      // ריהוט
        case 'bench': return 'ספסל';
        case 'chair': return 'כיסא';
        case 'couch': return 'ספה';
        case 'bed': return 'מיטה';
        case 'dining table': return 'שולחן אוכל';
        case 'potted plant': return 'עציץ';

      // אביזרים
        case 'backpack': return 'תיק גב';
        case 'handbag': return 'תיק יד';
        case 'suitcase': return 'מזוודה';
        case 'umbrella': return 'מטרייה';

      // ציוד ספורט
        case 'skis': return 'מגלשיים';
        case 'sports ball': return 'כדור';
        case 'surfboard': return 'גלשן';
        case 'tennis racket': return 'מחבט טניס';

        default: return tag;
      }
    }
    return tag;
  }

  // תרגום רמת סיכון
  String _severityText(double riskScore) {
    if (_language.startsWith('he')) {
      if (riskScore >= 75) return 'קרוב מאוד';
      if (riskScore >= 50) return 'לפניך';
      return 'בסביבה';
    }

    if (riskScore >= 75) return 'very close';
    if (riskScore >= 50) return 'ahead';
    return 'around';
  }

  Future<void> stop() async {
    await _tts.stop();
    // עוצר דיבור
  }
}