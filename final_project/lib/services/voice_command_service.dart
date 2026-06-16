import 'package:flutter/foundation.dart';
import 'package:speech_to_text/speech_to_text.dart';

class VoiceCommandService {

  final SpeechToText _speech = SpeechToText();

  bool _isListening = false;
  bool _isInitialized = false;
  Function()? _onErrorCallback;

  bool get isListening => _isListening;
  bool get isInitialized => _isInitialized;

  // ════════════════════════════════════════════════════════
  // INITIALIZE
  // ════════════════════════════════════════════════════════

  Future<bool> initialize() async {
    _debug('initialize()');

    final available = await _speech.initialize(
      debugLogging: kDebugMode,

      onStatus: (status) {
        _debug('status → $status');

        if (status == 'listening') {
          _isListening = true;
        } else if (status == 'notListening' || status == 'done') {
          _isListening = false;
        }
      },

      onError: (error) {
        _debug(
          'error → ${error.errorMsg} (permanent: ${error.permanent})',
        );

        _isListening = false;

        final delay = error.errorMsg.contains('network')
            ? const Duration(seconds: 3)
            : const Duration(milliseconds: 500);

        Future.delayed(delay, () {
          _onErrorCallback?.call();
        });
      },
    );

    _isInitialized = available;

    if (kDebugMode && available) {
      final locales = await _speech.locales();
      final systemLocale = await _speech.systemLocale();

      _debug('system locale: ${systemLocale?.localeId}');
      _debug(
        'supported locales: ${locales.map((l) => l.localeId).join(', ')}',
      );
    }

    _debug(
      available
          ? '✅ speech available'
          : '❌ speech not available on this device',
    );

    return available;
  }

  // ════════════════════════════════════════════════════════
  // START LISTENING
  // ════════════════════════════════════════════════════════

  Future<void> startListening(
      Function(String) onCommand, {
        required String localeId,
        Function()? onError,
      }) async {

    if (!_speech.isAvailable) {
      _debug('speech not available');
      return;
    }

    if (_isListening) {
      _debug('already listening');
      return;
    }

    _onErrorCallback = onError;
    _isListening = true;

    _debug('startListening() locale=$localeId');

    await _speech.listen(
      onResult: (result) {
        _debug(
          'result="${result.recognizedWords}" final=${result.finalResult}',
        );

        if (result.finalResult &&
            result.recognizedWords.trim().isNotEmpty) {
          onCommand(result.recognizedWords.trim());
        }
      },

      listenMode: ListenMode.dictation,

      localeId: localeId,

      pauseFor: const Duration(seconds: 4),

      listenFor: const Duration(seconds: 30),

      cancelOnError: false,

      partialResults: false,

      // חשוב:
      // מאפשר שימוש במנוע הזיהוי של Android/Google
      // ולא מחייב זיהוי מקומי בלבד
      onDevice: false,
    );
  }

  // ════════════════════════════════════════════════════════
  // STOP LISTENING
  // ════════════════════════════════════════════════════════

  Future<void> stopListening() async {
    if (!_isListening) return;

    _onErrorCallback = null;

    await _speech.stop();

    _isListening = false;

    _debug('stopped');
  }

  // ════════════════════════════════════════════════════════
  // PRIVATE
  // ════════════════════════════════════════════════════════

  void _debug(String msg) {
    if (!kDebugMode) return;

    final t = DateTime.now()
        .toIso8601String()
        .split('T')
        .last
        .split('.')
        .first;

    debugPrint('[VoiceCmd][$t] $msg');
  }
}