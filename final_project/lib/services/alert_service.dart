import 'package:flutter/foundation.dart';
import 'package:flutter_tts/flutter_tts.dart';
import '../models/detection.dart';

class AlertService {
  final FlutterTts _tts = FlutterTts();

  String _language = 'he-IL';
  double _speechRate = 0.5;
  bool _voiceAlertsEnabled = true;

  bool _isSpeaking = false;
  bool get isSpeaking => _isSpeaking;

  DateTime? _speakingStartTime;
  static const Duration _maxSpeakingDuration = Duration(seconds: 5);

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
    await _tts.awaitSpeakCompletion(true);
    _registerHandlers();

    _debug('✅ initialized (lang: $_language, rate: $_speechRate)');
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
    _registerHandlers();
  }

  void _registerHandlers() {
    _tts.setCompletionHandler(() {
      _debug('speech completed');
      _resetSpeakingState();
      _processPendingAlert();
    });

    _tts.setErrorHandler((msg) {
      _debug('speech error: $msg');
      _resetSpeakingState();
      _processPendingAlert();
    });

    _tts.setCancelHandler(() {
      _debug('speech cancelled');
      _resetSpeakingState();
    });
  }

  Future<void> speakSystemStarted() async {
    if (!_voiceAlertsEnabled) return;
    await _speakSystemMessage(
      _language.startsWith('he') ? 'המערכת הופעלה' : 'System started',
    );
  }

  Future<void> speakSystemStopped() async {
    if (!_voiceAlertsEnabled) return;
    await _speakSystemMessage(
      _language.startsWith('he') ? 'המערכת הופסקה' : 'System stopped',
    );
  }

  Future<void> speakVoiceTest() async {
    await _speakSystemMessage(
      _language.startsWith('he') ? 'זוהי בדיקת קול' : 'This is a voice test',
    );
  }

  Future<void> _speakSystemMessage(String message) async {
    if (_isSpeakingStuck()) {
      await _tts.stop();
      _resetSpeakingState();
    }

    if (_isSpeaking) {
      await _tts.stop();
      _resetSpeakingState();
    }

    _isSpeaking = true;
    _speakingStartTime = DateTime.now();

    try {
      _debug('system speaking: "$message"');
      await _tts.speak(message);
    } catch (e) {
      _debug('system message failed: $e');
    } finally {
      _resetSpeakingState();
      _processPendingAlert();
    }
  }

  Future<bool> trySpeakDetection(
      Detection detection, {
        double? currentRisk,
      }) async {
    if (!_voiceAlertsEnabled) return false;

    if (_isSpeakingStuck()) {
      _debug('speech stuck – resetting');
      await _tts.stop();
      _resetSpeakingState();
    }

    if (_isSpeaking) {
      final newRisk = detection.riskScore;

      if (_pendingHighPriorityAlert == null ||
          newRisk > _pendingHighPriorityAlert!.riskScore) {
        _pendingHighPriorityAlert = detection;
        _debug(
          'queued: ${detection.tag} '
              '(risk: ${newRisk.toStringAsFixed(1)})',
        );
      } else {
        _debug(
          'ignored lower priority: ${detection.tag} '
              '(risk: ${newRisk.toStringAsFixed(1)})',
        );
      }

      return false;
    }

    final message = _buildMessage(detection);

    _isSpeaking = true;
    _speakingStartTime = DateTime.now();

    try {
      _debug(
        'speaking: "$message" '
            '(risk: ${detection.riskScore.toStringAsFixed(1)})',
      );
      await _tts.speak(message);
      return true;
    } catch (e) {
      _debug('speak failed: $e');
      return false;
    } finally {
      _resetSpeakingState();
      _processPendingAlert();
    }
  }

  Future<void> stop() async {
    await _tts.stop();
    _resetSpeakingState();
    _pendingHighPriorityAlert = null;
    _debug('stopped');
  }

  void resetSpeakingState() {
    _resetSpeakingState();
    _pendingHighPriorityAlert = null;
  }

  bool _isSpeakingStuck() {
    if (!_isSpeaking) return false;
    if (_speakingStartTime == null) return true;

    return DateTime.now().difference(_speakingStartTime!) >
        _maxSpeakingDuration;
  }

  void _resetSpeakingState() {
    _isSpeaking = false;
    _speakingStartTime = null;
  }

  void _processPendingAlert() {
    if (_pendingHighPriorityAlert == null) return;

    final pending = _pendingHighPriorityAlert!;
    _pendingHighPriorityAlert = null;

    Future.delayed(const Duration(milliseconds: 150), () {
      if (_voiceAlertsEnabled && !_isSpeaking) {
        trySpeakDetection(pending);
      }
    });
  }

  Future<void> _safeSetLanguage(String language) async {
    try {
      final result = await _tts.setLanguage(language);
      if (result != 1) {
        _debug('language $language may not be fully supported');
      }
    } catch (e) {
      _debug('language error – falling back to en-US: $e');
      await _tts.setLanguage('en-US');
    }
  }

  String _buildMessage(Detection detection) {
    return '${_localizedLabel(detection.tag)} ${_severityText(detection.riskScore)}';
  }

  String localizedLabel(String tag) => _localizedLabel(tag);

  String severityText(double riskScore) => _severityText(riskScore);

  String _localizedLabel(String tag) {
    if (!_language.startsWith('he')) return tag;

    return switch (tag) {
      'car' => 'מכונית',
      'bus' => 'אוטובוס',
      'truck' => 'משאית',
      'train' => 'רכבת',
      'motorcycle' => 'אופנוע',
      'person' => 'אדם',
      'bicycle' => 'אופניים',
      'skateboard' => 'סקייטבורד',
      'scooter' => 'קורקינט',
      'crosswalk' => 'מעבר חציה',
      'traffic light' => 'רמזור',
      'stop sign' => 'תמרור עצור',
      'fire hydrant' => 'ברז כיבוי אש',
      'dog' => 'כלב',
      'cat' => 'חתול',
      'horse' => 'סוס',
      'sheep' => 'כבשה',
      'cow' => 'פרה',
      'elephant' => 'פיל',
      'bear' => 'דוב',
      'zebra' => 'זברה',
      'giraffe' => 'ג׳ירפה',
      'bird' => 'ציפור',
      'bench' => 'ספסל',
      'chair' => 'כיסא',
      'couch' => 'ספה',
      'bed' => 'מיטה',
      'dining table' => 'שולחן אוכל',
      'potted plant' => 'עציץ',
      'backpack' => 'תיק גב',
      'handbag' => 'תיק יד',
      'suitcase' => 'מזוודה',
      'umbrella' => 'מטרייה',
      'skis' => 'מגלשיים',
      'sports ball' => 'כדור',
      'surfboard' => 'גלשן',
      'tennis racket' => 'מחבט טניס',
      'vase' => 'אגרטל',
      'bottle' => 'בקבוק',
      'cup' => 'כוס',
      'book' => 'ספר',
      'cell phone' => 'טלפון',
      'tv' => 'טלוויזיה',
      'laptop' => 'מחשב נייד',
      _ => tag,
    };
  }

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

  void _debug(String msg) {
    if (!kDebugMode) return;

    final t = DateTime.now()
        .toIso8601String()
        .split('T')
        .last
        .split('.')
        .first;

    debugPrint('[AlertService][$t] $msg');
  }
}