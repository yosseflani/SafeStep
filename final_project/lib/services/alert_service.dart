import 'package:flutter/foundation.dart';
import 'package:flutter_tts/flutter_tts.dart';
import '../models/detection.dart';

class AlertService {
  final FlutterTts _tts = FlutterTts();

  String _language = 'he-IL';
  double _speechRate = 0.5;
  bool _voiceAlertsEnabled = true;

  // מעקב סטטוס דיבור
  bool _isSpeaking = false;
  bool get isSpeaking => _isSpeaking;

  DateTime? _speakingStartTime;
  static const Duration _maxSpeakingDuration = Duration(seconds: 5);

  // תור התראות דחופות
  Detection? _pendingHighPriorityAlert;

  Future<void> initialize({
    required String language,
    required double speechRate,
    required bool voiceAlertsEnabled,
  }) async {
    _language = language;
    _speechRate = speechRate.clamp(0.1, 2.0);
    _voiceAlertsEnabled = voiceAlertsEnabled;

    await _safeSetLanguage(_language);
    await _tts.setSpeechRate(_speechRate);

    // ✅ שומר על שניהם: awaitSpeakCompletion + Handlers לאמינות מקסימלית
    await _tts.awaitSpeakCompletion(true);
    _registerHandlers();

    if (kDebugMode) debugPrint('✅ ALERT: initialized');
  }

  // ✅ שומר על רישום Handlers – קריטי לאיפוס מצב בשגיאות/ביטולים
  void _registerHandlers() {
    _tts.setCompletionHandler(() {
      if (kDebugMode) debugPrint('✅ ALERT: speech completed');
      _resetSpeakingState();
      _processPendingAlert();
    });

    _tts.setErrorHandler((message) {
      if (kDebugMode) debugPrint('❌ ALERT ERROR: $message');
      _resetSpeakingState();
      _processPendingAlert(); // מנסה להמשיך עם התראה דחופה גם אחרי שגיאה
    });

    _tts.setCancelHandler(() {
      if (kDebugMode) debugPrint('⚠️ ALERT: speech cancelled');
      _resetSpeakingState();
    });
  }

  // ✅ בדיקת חירום לתקיעות – מונעת אובדן התראות
  bool _isSpeakingStuck() {
    if (!_isSpeaking) return false;
    if (_speakingStartTime == null) return true;
    final elapsed = DateTime.now().difference(_speakingStartTime!);
    return elapsed > _maxSpeakingDuration;
  }

  void _resetSpeakingState() {
    _isSpeaking = false;
    _speakingStartTime = null;
  }

  // ✅ מעבד התראה ממתינה עם השהיה קצרה למניעת חפיפה
  void _processPendingAlert() {
    if (_pendingHighPriorityAlert != null) {
      final pending = _pendingHighPriorityAlert!;
      _pendingHighPriorityAlert = null;

      Future.delayed(const Duration(milliseconds: 150), () {
        if (_voiceAlertsEnabled) {
          trySpeakDetection(pending);
        }
      });
    }
  }

  Future<void> updateSettings({
    required String language,
    required double speechRate,
    required bool voiceAlertsEnabled,
  }) async {
    _language = language;
    _speechRate = speechRate.clamp(0.1, 2.0);
    _voiceAlertsEnabled = voiceAlertsEnabled;

    await _safeSetLanguage(_language);
    await _tts.setSpeechRate(_speechRate);
    _registerHandlers(); // ✅ מחדש Handlers אחרי עדכון
  }

  Future<void> _safeSetLanguage(String language) async {
    try {
      final result = await _tts.setLanguage(language);
      if (result != 1 && kDebugMode) {
        debugPrint('⚠️ ALERT: language $language may not be fully supported');
      }
    } catch (e) {
      if (kDebugMode) debugPrint('❌ ALERT: language fallback to en-US: $e');
      await _tts.setLanguage('en-US');
    }
  }

  Future<void> speakSystemStarted() async {
    if (!_voiceAlertsEnabled) return;
    final msg = _language.startsWith('he') ? 'המערכת הופעלה' : 'System started';
    await _speakSystemMessage(msg);
  }

  Future<void> speakSystemStopped() async {
    if (!_voiceAlertsEnabled) return;
    final msg = _language.startsWith('he') ? 'המערכת הופסקה' : 'System stopped';
    await _speakSystemMessage(msg);
  }

  Future<void> speakVoiceTest() async {
    final msg = _language.startsWith('he') ? 'זוהי בדיקת קול' : 'This is a voice test';
    await _speakSystemMessage(msg);
  }

  // ✅ הודעות מערכת עם בדיקת תקיעות ואיפוס נקי
  Future<void> _speakSystemMessage(String message) async {
    if (_isSpeakingStuck()) {
      await _tts.stop();
      _resetSpeakingState();
    }
    if (_isSpeaking) await _tts.stop();

    _isSpeaking = true;
    _speakingStartTime = DateTime.now();

    try {
      await _tts.speak(message);
    } catch (e) {
      if (kDebugMode) debugPrint('❌ ALERT: system message failed: $e');
      _resetSpeakingState();
    }
  }

  /// ✅ הלוגיקה המרכזית: משלבת עדיפות סיכון + מניעת תקיעות
  Future<bool> trySpeakDetection(Detection detection, {double? currentRisk}) async {
    if (!_voiceAlertsEnabled) return false;

    // ✅ בדיקת חירום: אם הדיבור "נתקע" – משחררים נעילה
    if (_isSpeakingStuck()) {
      if (kDebugMode) debugPrint('⚠️ ALERT: speech stuck, resetting');
      await _tts.stop();
      _resetSpeakingState();
    }

    if (_isSpeaking) {
      final newRisk = detection.riskScore;

      // ✅ גרסה משודרגת: שומרים את ההתראה עם הסיכון הגבוה ביותר
      if (_pendingHighPriorityAlert == null || newRisk > _pendingHighPriorityAlert!.riskScore) {
        _pendingHighPriorityAlert = detection;
        if (kDebugMode) {
          debugPrint('⏳ ALERT: queued high-priority: ${detection.tag} (risk: ${newRisk.toStringAsFixed(1)})');
        }
      } else {
        if (kDebugMode) {
          debugPrint('⏭️ ALERT: ignored lower priority: ${detection.tag} (risk: ${newRisk.toStringAsFixed(1)})');
        }
      }
      return false;
    }

    // ✅ מתחילים דיבור חדש
    final message = _buildMessage(detection);
    _isSpeaking = true;
    _speakingStartTime = DateTime.now();

    try {
      if (kDebugMode) {
        debugPrint('🔊 ALERT: speaking "${message}" (risk: ${detection.riskScore.toStringAsFixed(1)})');
      }
      await _tts.speak(message);
      return true;
    } catch (e) {
      if (kDebugMode) debugPrint('❌ ALERT: speak failed: $e');
      _resetSpeakingState();
      return false;
    }
  }

  String _buildMessage(Detection detection) {
    final objectName = _localizedLabel(detection.tag);
    final severity = _severityText(detection.riskScore);
    return '$objectName $severity';
  }

  String localizedLabel(String tag) => _localizedLabel(tag);
  String severityText(double riskScore) => _severityText(riskScore);

  // ✅ תרגום מלא לעברית (כמו בגרסה הישנה)
  String _localizedLabel(String tag) {
    if (_language.startsWith('he')) {
      switch (tag) {
        case 'car': return 'מכונית';
        case 'bus': return 'אוטובוס';
        case 'truck': return 'משאית';
        case 'train': return 'רכבת';
        case 'motorcycle': return 'אופנוע';
        case 'person': return 'אדם';
        case 'bicycle': return 'אופניים';
        case 'skateboard': return 'סקייטבורד';
        case 'scooter': return 'קורקינט';
        case 'crosswalk': return 'מעבר חציה';
        case 'traffic light': return 'רמזור';
        case 'stop sign': return 'תמרור עצור';
        case 'fire hydrant': return 'ברז כיבוי אש';
        case 'dog': return 'כלב';
        case 'cat': return 'חתול';
        case 'horse': return 'סוס';
        case 'sheep': return 'כבשה';
        case 'cow': return 'פרה';
        case 'elephant': return 'פיל';
        case 'bear': return 'דוב';
        case 'zebra': return 'זברה';
        case 'giraffe': return 'ג׳ירפה';
        case 'bird': return 'ציפור';
        case 'bench': return 'ספסל';
        case 'chair': return 'כיסא';
        case 'couch': return 'ספה';
        case 'bed': return 'מיטה';
        case 'dining table': return 'שולחן אוכל';
        case 'potted plant': return 'עציץ';
        case 'backpack': return 'תיק גב';
        case 'handbag': return 'תיק יד';
        case 'suitcase': return 'מזוודה';
        case 'umbrella': return 'מטרייה';
        case 'skis': return 'מגלשיים';
        case 'sports ball': return 'כדור';
        case 'surfboard': return 'גלשן';
        case 'tennis racket': return 'מחבט טניס';
        case 'vase': return 'אגרטל';
        case 'bottle': return 'בקבוק';
        case 'cup': return 'כוס';
        case 'book': return 'ספר';
        case 'cell phone': return 'טלפון';
        case 'tv': return 'טלוויזיה';
        case 'laptop': return 'מחשב נייד';
        default: return tag;
      }
    }
    return tag;
  }

  // ✅ 3 רמות סיכון ברורות – כמו בגרסה הישנה
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
    _resetSpeakingState();
    _pendingHighPriorityAlert = null;
    if (kDebugMode) debugPrint('🛑 ALERT: stopped');
  }

  // ✅ ציבורי – לאיפוס ידני אם צריך
  void resetSpeakingState() {
    _resetSpeakingState();
    _pendingHighPriorityAlert = null;
  }
}