import 'package:flutter_tts/flutter_tts.dart';

import '../models/detection.dart';
import '../utils/logger.dart';

/// שירות לניהול התרעות קוליות באפליקציה.
class AlertService {
  // מנוע הדיבור של המכשיר.
  final FlutterTts _tts = FlutterTts();
  final _log = const AppLogger('AlertService');

  // הגדרות דיבור והתראות.
  String _language = 'he-IL';
  double _speechRate = 0.5;
  bool _voiceAlertsEnabled = true;

  // מצב הדיבור הנוכחי.
  bool _isSpeaking = false;

  /// מציין האם מתבצע דיבור כרגע.
  bool get isSpeaking => _isSpeaking;

  // זמן תחילת הדיבור הנוכחי.
  DateTime? _speakingStartTime;

  /// משך דיבור מקסימלי לפני איפוס מצב תקוע.
  static const Duration _maxSpeakingDuration = Duration(seconds: 5);

  // התרעה חשובה שממתינה לסיום הדיבור הנוכחי.
  Detection? _pendingHighPriorityAlert;

  /// מאתחל את שירות ההתרעות הקוליות.
  Future<void> initialize({
    required String language,
    required double speechRate,
    required bool voiceAlertsEnabled,
  }) async {
    _language = language;

    _speechRate = speechRate.clamp(0.1, 2.0);

    _voiceAlertsEnabled = voiceAlertsEnabled;

    _registerHandlers();

    await _safeSetLanguage(_language);

    await _tts.setSpeechRate(_speechRate);

    // ממתין לסיום ההקראה לפני המשך הריצה.
    await _tts.awaitSpeakCompletion(true);

    _log.debug('initialized: lang=$_language, rate=$_speechRate');
  }

  /// מעדכן את הגדרות הדיבור בזמן ריצה.
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

    _log.debug('settings updated: lang=$_language, rate=$_speechRate');
  }

  /// רושם מאזינים לאירועי מנוע הדיבור.
  void _registerHandlers() {
    _tts.setCompletionHandler(() {
      _log.debug('speech completed');
    });

    _tts.setErrorHandler((msg) {
      _log.debug('speech error: $msg');

      _resetSpeakingState();

      _processPendingAlert();
    });

    _tts.setCancelHandler(() {
      _log.debug('speech cancelled');

      _resetSpeakingState();
    });
  }

  /// מקריא הודעת הפעלת מערכת.
  Future<void> speakSystemStarted() async {
    if (!_voiceAlertsEnabled) return;

    await _speakSystemMessage(
      _isHebrew ? 'המערכת הופעלה' : 'System started',
    );
  }

  /// מקריא הודעת עצירת מערכת.
  Future<void> speakSystemStopped() async {
    if (!_voiceAlertsEnabled) return;

    await _speakSystemMessage(
      _isHebrew ? 'המערכת הופסקה' : 'System stopped',
    );
  }
  /// מקריא הודעת בדיקת קול.
  Future<void> speakVoiceTest() async {
    await _speakSystemMessage(
      _isHebrew ? 'זוהי בדיקת קול' : 'This is a voice test',
    );
  }

  /// מקריא טקסט חופשי.
  Future<void> speakFreeText(String text) async {
    await _speakSystemMessage(text);
  }

  /// מנסה להקריא התרעה עבור אובייקט שזוהה.
  Future<bool> trySpeakDetection(
      Detection detection,
      {
        double? currentRisk,
      }) async {
    if (!_voiceAlertsEnabled) return false;

    await _recoverIfSpeechIsStuck();

    final risk = currentRisk ?? detection.riskScore;

    // אם מתבצע דיבור, שומר רק את ההתרעה החשובה ביותר.
    if (_isSpeaking) {
      _queueIfHigherPriority(detection, risk);

      return false;
    }

    final message = _buildMessage(detection, riskScore: risk);

    return _speak(
      message,
      debugContext: 'detection=${detection.tag}, risk=${risk.toStringAsFixed(1)}',
      processPendingAfterSpeech: true,
    );
  }

  /// עוצר דיבור פעיל ומנקה התרעות ממתינות.
  Future<void> stop() async {
    await _tts.stop();

    _resetSpeakingState();

    _pendingHighPriorityAlert = null;

    _log.debug('stopped');
  }

  /// מאפס את מצב הדיבור והתור ללא עצירת TTS.
  void resetSpeakingState() {
    _resetSpeakingState();

    _pendingHighPriorityAlert = null;
  }

  /// משחרר משאבי דיבור פעילים.
  Future<void> dispose() async {
    await stop();
  }

  /// מקריא הודעת מערכת בעדיפות גבוהה.
  Future<void> _speakSystemMessage(String message) async {
    await _recoverIfSpeechIsStuck();

    if (_isSpeaking) {
      await _tts.stop();

      _resetSpeakingState();
    }

    await _speak(
      message,
      debugContext: 'system message',
      processPendingAfterSpeech: true,
    );
  }

  /// פונקציית הדיבור המרכזית של השירות.
  Future<bool> _speak(
      String message,
      {
        required String debugContext,
        required bool processPendingAfterSpeech,
      }) async {
    if (message.trim().isEmpty) return false;

    _isSpeaking = true;

    _speakingStartTime = DateTime.now();

    try {
      _log.debug('speaking "$message" ($debugContext)');

      await _tts.speak(message);

      return true;
    } catch (e) {
      _log.debug('speak failed: $e');

      return false;
    } finally {
      _resetSpeakingState();

      if (processPendingAfterSpeech) {
        _processPendingAlert();
      }
    }
  }

  /// מאפס מצב דיבור אם מנוע ה־TTS נתקע.
  Future<void> _recoverIfSpeechIsStuck() async {
    if (!_isSpeakingStuck()) return;

    _log.debug('speech stuck, resetting');

    await _tts.stop();

    _resetSpeakingState();
  }

  /// בודק האם מצב הדיבור נתקע.
  bool _isSpeakingStuck() {
    if (!_isSpeaking) return false;

    if (_speakingStartTime == null) return true;

    return DateTime.now().difference(_speakingStartTime!) >
        _maxSpeakingDuration;
  }

  /// מאפס את מצב הדיבור הפנימי.
  void _resetSpeakingState() {
    _isSpeaking = false;

    _speakingStartTime = null;
  }

  /// שומר בתור רק התרעה בעלת עדיפות גבוהה יותר.
  void _queueIfHigherPriority(Detection detection, double risk) {
    final currentPendingRisk = _pendingHighPriorityAlert?.riskScore ?? -1;

    if (risk > currentPendingRisk) {
      _pendingHighPriorityAlert = detection.copyWith(riskScore: risk);

      _log.debug(
        'queued high priority: ${detection.tag}, risk=${risk.toStringAsFixed(1)}',
      );
    } else {
      _log.debug(
        'ignored lower priority: ${detection.tag}, risk=${risk.toStringAsFixed(1)}',
      );
    }
  }

  /// מנסה להקריא התרעה ממתינה לאחר סיום דיבור קודם.
  void _processPendingAlert() {
    if (_pendingHighPriorityAlert == null) return;

    final pending = _pendingHighPriorityAlert!;

    _pendingHighPriorityAlert = null;

    Future.delayed(const Duration(milliseconds: 150), () {
      if (!_voiceAlertsEnabled || _isSpeaking) return;

      trySpeakDetection(pending);
    });
  }

  /// מגדיר שפה במנוע הדיבור עם fallback לאנגלית.
  Future<void> _safeSetLanguage(String language) async {
    try {
      final result = await _tts.setLanguage(language);

      if (result != 1) {
        _log.debug('language may not be fully supported: $language');
      }
    } catch (e) {
      _log.debug('language error, falling back to en-US: $e');

      _language = 'en-US';

      await _tts.setLanguage(_language);
    }
  }

  /// בונה את משפט ההתרעה שיוקרא למשתמש.
  String _buildMessage(
      Detection detection,
      {
        required double riskScore,
      }) {
    return '${_localizedLabel(detection.tag)} ${_severityText(riskScore)}';
  }



  /// מציין האם שפת המערכת היא עברית.
  bool get _isHebrew => _language.startsWith('he');

  /// מחזיר תרגום לתגית אובייקט לפי השפה הנוכחית.
  String _localizedLabel(String tag) {
    if (!_isHebrew) {
      return switch (tag) {
        'crosswalk' => 'crosswalk',
        'person' => 'person',
        'car' => 'car',
        'motorcycle' => 'motorcycle',
        'pole' => 'pole',
        'couch' => 'couch',
        'bench' => 'bench',

        _ => tag,
      };
    }

    return switch (tag) {
      'crosswalk' => 'מעבר חציה',
      'person' => 'אדם',
      'car' => 'מכונית',
      'motorcycle' => 'אופנוע',
      'pole' => 'עמוד',
      'couch' => 'ספה',
      'bench' => 'ספסל',

      _ => tag,
    };
  }

  /// מחזיר טקסט חומרה לפי רמת הסיכון.
  String _severityText(double riskScore) {
    if (_isHebrew) {
      if (riskScore >= 75) return 'קרוב מאוד';

      if (riskScore >= 50) return 'לפניך';

      return 'בסביבה';
    }

    if (riskScore >= 75) return 'very close';
    if (riskScore >= 50) return 'ahead';
    return 'around';
  }

}
