import 'package:flutter_tts/flutter_tts.dart';
import '../models/detection.dart';

class AlertService {
  final FlutterTts _tts = FlutterTts(); // האובייקט שמבצע דיבור

  String _language = 'he-IL';
  double _speechRate = 0.5;
  bool _voiceAlertsEnabled = true;

  Future<void> initialize({
    required String language,
    required double speechRate,
    required bool voiceAlertsEnabled,
  }) async {
    _language = language;
    _speechRate = speechRate;
    _voiceAlertsEnabled = voiceAlertsEnabled;

    await _tts.setLanguage(_language);
    await _tts.setSpeechRate(_speechRate);
    await _tts.awaitSpeakCompletion(true);
  }

  // מעדכן אם המשתמש שינה את ההעדפה המקורית
  Future<void> updateSettings({
    required String language,
    required double speechRate,
    required bool voiceAlertsEnabled,
  }) async {
    _language = language;
    _speechRate = speechRate;
    _voiceAlertsEnabled = voiceAlertsEnabled;

    await _tts.setLanguage(_language);
    await _tts.setSpeechRate(_speechRate);
  }

  // הודעת מערכת כשהאפליקציה מתחילה לעבוד
  Future<void> speakSystemStarted() async {
    if (!_voiceAlertsEnabled) return;
    await _tts.speak(
      _language.startsWith('he') ? 'המערכת הופעלה' : 'System started',
    );
  }

// הודעת מערכת כשהאפליקציה מפסיקה לעבוד
  Future<void> speakSystemStopped() async {
    if (!_voiceAlertsEnabled) return;
    await _tts.speak(
      _language.startsWith('he') ? 'המערכת הופסקה' : 'System stopped',
    );
  }

  // משמיע בדיקת קול בהגדרות
  Future<void> speakVoiceTest() async {
    if (!_voiceAlertsEnabled) return;
    await _tts.speak(
      _language.startsWith('he') ? 'זוהי בדיקת קול' : 'This is a voice test',
    );
  }

  // משמיע את ההודעה
  Future<void> speakDetection(Detection detection) async {
    if (!_voiceAlertsEnabled) return;
    await _tts.speak(_buildMessage(detection));
  }

  // בונה את ההודעה מהחומר הגולמי
  String _buildMessage(Detection detection) {
    final localizedObject = _localizedLabel(detection.tag);
    final severity = _severityText(detection.riskScore);

    if (_language.startsWith('he')) {
      return '$localizedObject $severity';
    }

    return '$localizedObject $severity';
  }

  String localizedLabel(String tag) => _localizedLabel(tag);

  String severityText(double riskScore) => _severityText(riskScore);

  // תרגום מהמודל לעברית
  String _localizedLabel(String tag) {
    if (_language.startsWith('he')) {
      switch (tag) {
        case 'person':
          return 'אדם';
        case 'car':
          return 'רכב';
        case 'bus':
          return 'אוטובוס';
        case 'truck':
          return 'משאית';
        case 'motorcycle':
          return 'אופנוע';
        case 'bicycle':
          return 'אופניים';
        case 'traffic light':
          return 'רמזור';
        case 'chair':
          return 'כיסא';
        case 'dog':
          return 'כלב';
        case 'stop sign':
          return 'תמרור עצור';
        default:
          return tag;
      }
    }

    return tag;
  }

  // הופך את הציון סיכון שחישבנו למילים
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
  }
}