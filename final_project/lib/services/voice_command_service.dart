import 'dart:async';
// ייבוא כלים לניהול זמן ו-streams אסינכרוניים

import 'dart:io';
// ייבוא כלים לעבודה עם קבצים ותיקיות

import 'dart:typed_data';
// ייבוא Float32List לצורך המרת אודיו לפורמט שהמודל מבין

import 'package:flutter/foundation.dart';
// kDebugMode = האם האפליקציה רצה במצב debug
// debugPrint = הדפסה נוחה ללוגים

import 'package:flutter/services.dart';
// rootBundle = גישה לקבצים שנמצאים בתיקיית assets של הפרויקט

import 'package:path_provider/path_provider.dart';
// גישה לתיקיות מקומיות במכשיר כמו documents ו-temp

import 'package:record/record.dart';
// ספריית הקלטת אודיו מהמיקרופון

import 'package:sherpa_onnx/sherpa_onnx.dart';
// ספריית זיהוי דיבור offline באמצעות sherpa-onnx
// כאן אנחנו משתמשים במודל Whisper מקומי
// כלומר: זיהוי דיבור בלי אינטרנט

class VoiceCommandService {
  // מחלקה שאחראית על כל הלוגיקה של זיהוי הפקודות הקוליות
  // משתמשת במודל Whisper דרך sherpa-onnx במקום speech_to_text
  // כך האפליקציה יכולה לעבוד offline בלי Google Speech

  OfflineRecognizer? _recognizer;
  // מנוע זיהוי הדיבור של sherpa-onnx
  // OfflineRecognizer = מזהה דיבור שעובד ללא אינטרנט

  final AudioRecorder _recorder = AudioRecorder();
  // מקליט האודיו מהמיקרופון
  // בחבילה record אין צורך ב-openRecorder

  bool _isListening = false;
  // האם כרגע אנחנו במצב האזנה

  Function()? _onErrorCallback;
  // callback חיצוני שמסך אחר יכול להעביר
  // יופעל אם קרתה שגיאה ונרצה לנסות להתאושש

  Timer? _processTimer;
  // טיימר שמפעיל עיבוד של האודיו כל כמה שניות
  // כך יוצרים האזנה כמעט רציפה:
  // מקליטים כמה שניות -> מעבדים -> מקליטים שוב

  String? _audioPath;
  // הנתיב לקובץ ה-WAV הזמני שאליו נשמרת ההקלטה

  bool get isListening => _isListening;
  // getter לקריאה בלבד
  // מאפשר למסכים אחרים לדעת אם השירות מאזין כרגע

  Future<bool> initialize() async {
    // אתחול מנוע זיהוי הדיבור
    // מחזיר true אם הכל הצליח, אחרת false

    try {
      // אתחול חובה של sherpa-onnx לפני שימוש במזהה הדיבור
      // אם Android Studio מסמן את השורה הזאת באדום,
      // צריך לבדוק בדוגמה של החבילה שלך מה שם פונקציית האתחול המדויק.
      initBindings();
      // מציאת תיקיית documents המקומית של האפליקציה
      // לשם נעתיק את קבצי המודל מתוך assets
      final dir = await getApplicationDocumentsDirectory();
      final modelDir = '${dir.path}/whisper';

      // יצירת תיקיית המודל אם היא עדיין לא קיימת
      await Directory(modelDir).create(recursive: true);

      // רשימת קבצי המודל שצריכים להיות ב-assets/whisper/
      // ודא שב-pubspec.yaml רשמת:
      //
      // flutter:
      //   assets:
      //     - assets/whisper/
      final files = [
        'tiny-encoder.int8.onnx',
        // קובץ encoder של Whisper

        'tiny-decoder.int8.onnx',
        // קובץ decoder של Whisper

        'tiny-tokens.txt',
        // קובץ tokens / מילון של המודל
      ];

      for (final file in files) {
        final target = File('$modelDir/$file');

        if (!target.existsSync()) {
          // אם הקובץ עדיין לא הועתק לתיקייה המקומית,
          // נעתיק אותו מתוך assets
          final data = await rootBundle.load('assets/whisper/$file');

          await target.writeAsBytes(data.buffer.asUint8List());

          if (kDebugMode) {
            debugPrint('Copied model file: $file');
          }
        }
      }

      // הגדרת המודל עם הנתיבים המקומיים
      // חשוב: הנתיבים חייבים להצביע לקבצים אמיתיים במערכת הקבצים,
      // לא ישירות ל-assets, ולכן קודם העתקנו אותם ל-documents.
      final config = OfflineRecognizerConfig(
        model: OfflineModelConfig(
          whisper: OfflineWhisperModelConfig(
            encoder: '$modelDir/tiny-encoder.int8.onnx',
            decoder: '$modelDir/tiny-decoder.int8.onnx',

            // זיהוי בעברית
            language: 'he',

            // transcribe = תמלול
            // לא translate, כי אנחנו לא רוצים תרגום לאנגלית
            task: 'transcribe',
          ),

          // קובץ הטוקנים של המודל
          tokens: '$modelDir/tiny-tokens.txt',

          // מספר threads לעיבוד
          // 2 מתאים לרוב הטלפונים בלי להעמיס יותר מדי
          numThreads: 2,

          // במצב debug נקבל יותר לוגים
          debug: kDebugMode,
        ),
      );

      // יצירת מנוע הזיהוי בפועל
      _recognizer = OfflineRecognizer(config);

      if (kDebugMode) {
        debugPrint('sherpa-onnx Whisper initialized successfully');
      }

      return true;
    } catch (e) {
      if (kDebugMode) {
        debugPrint('sherpa-onnx init error: $e');
      }

      _recognizer = null;
      return false;
    }
  }

  Future<void> startListening(
      Function(String) onCommand, {
        required String localeId,
        // נשאר כדי לא לשבור את הקוד הקיים ב-MainScreen
        // בפועל sherpa-onnx משתמש ב-language: 'he' שהגדרנו למודל

        Function()? onError,
      }) async {
    // התחלת האזנה לפקודות קוליות
    //
    // onCommand = הפונקציה שתופעל כאשר מזוהה טקסט
    // onError = callback אופציונלי לשגיאות

    if (_recognizer == null) {
      // אם המודל לא אותחל, אין מה להתחיל האזנה
      if (kDebugMode) {
        debugPrint('Recognizer not initialized');
      }
      return;
    }

    if (_isListening) {
      // מניעת הפעלה כפולה של האזנה
      if (kDebugMode) {
        debugPrint('Already listening');
      }
      return;
    }

    _onErrorCallback = onError;

    try {
      final hasPermission = await _recorder.hasPermission();
      // בדיקה שיש הרשאת מיקרופון

      if (!hasPermission) {
        if (kDebugMode) {
          debugPrint('No microphone permission');
        }
        return;
      }

      final dir = await getTemporaryDirectory();
      _audioPath = '${dir.path}/voice_command.wav';
      // קובץ זמני שאליו נקליט כל מקטע דיבור

      await _recorder.start(
        const RecordConfig(
          encoder: AudioEncoder.wav,
          sampleRate: 16000,
          numChannels: 1,
        ),
        path: _audioPath!,
      );

      _isListening = true;

      if (kDebugMode) {
        debugPrint('Recording started');
      }

      _processTimer = Timer.periodic(
        const Duration(seconds: 4),
            (_) async {
          await _processAudio(onCommand);
        },
      );
      // כל 4 שניות:
      // 1. עוצרים הקלטה
      // 2. מעבדים את הקובץ
      // 3. שולחים טקסט אם זוהה
      // 4. מתחילים להקליט שוב
    } catch (e) {
      if (kDebugMode) {
        debugPrint('startListening error: $e');
      }

      _isListening = false;
      _onErrorCallback?.call();
    }
  }

  Future<void> _processAudio(Function(String) onCommand) async {
    // עיבוד קטע האודיו שהוקלט
    // הפונקציה הזאת נקראת כל כמה שניות על ידי הטיימר

    if (!_isListening || _recognizer == null || _audioPath == null) {
      return;
    }

    try {
      await _recorder.stop();
      // עוצרים הקלטה כדי שהקובץ ייסגר ואפשר יהיה לקרוא אותו

      final audioFile = File(_audioPath!);

      if (!audioFile.existsSync()) {
        await _restartRecording();
        return;
      }

      final audioBytes = await audioFile.readAsBytes();

      if (audioBytes.length < 44) {
        // קובץ WAV קצר מדי או לא תקין
        await _restartRecording();
        return;
      }

      // קובץ WAV רגיל מכיל header של 44 בייט
      // אחרי ה-header נמצאים נתוני PCM
      final pcmBytes = audioBytes.sublist(44);

      // המרת PCM 16-bit little-endian ל-Float32List
      final samples = Float32List(pcmBytes.length ~/ 2);

      for (int i = 0; i < samples.length; i++) {
        final lo = pcmBytes[i * 2];
        final hi = pcmBytes[i * 2 + 1];

        final sample = (hi << 8) | lo;

        // המרה מטווח int16 לטווח float של [-1.0, 1.0]
        samples[i] = sample > 32767
            ? (sample - 65536) / 32768.0
            : sample / 32768.0;
      }

      final stream = _recognizer!.createStream();
      // יצירת stream חד-פעמי לזיהוי

      stream.acceptWaveform(
        samples: samples,
        sampleRate: 16000,
      );

      _recognizer!.decode(stream);
      // הפעלת הזיהוי

      final result = _recognizer!.getResult(stream);
      // קבלת הטקסט שזוהה

      stream.free();
      // שחרור stream מהזיכרון

      final text = result.text.trim();

      if (kDebugMode) {
        debugPrint('Whisper recognized: "$text"');
      }

      if (text.isNotEmpty) {
        onCommand(text);
      }

      await _restartRecording();
    } catch (e) {
      if (kDebugMode) {
        debugPrint('processAudio error: $e');
      }

      await _restartRecording();
    }
  }

  Future<void> _restartRecording() async {
    // התחלת הקלטה מחדש אחרי כל עיבוד
    // רק אם עדיין נמצאים במצב האזנה

    if (!_isListening || _audioPath == null) {
      return;
    }

    try {
      await _recorder.start(
        const RecordConfig(
          encoder: AudioEncoder.wav,
          sampleRate: 16000,
          numChannels: 1,
        ),
        path: _audioPath!,
      );

      if (kDebugMode) {
        debugPrint('Recording restarted');
      }
    } catch (e) {
      if (kDebugMode) {
        debugPrint('restartRecording error: $e');
      }
    }
  }

  Future<void> stopListening() async {
    // עצירת האזנה

    if (!_isListening) {
      return;
    }

    _isListening = false;

    _processTimer?.cancel();
    _processTimer = null;

    _onErrorCallback = null;

    try {
      await _recorder.stop();
    } catch (e) {
      if (kDebugMode) {
        debugPrint('stopListening error: $e');
      }
    }
  }

  void dispose() {
    // שחרור משאבים
    // חשוב לקרוא לזה מתוך dispose של המסך

    stopListening();

    _processTimer?.cancel();
    _processTimer = null;

    _recognizer?.free();
    _recognizer = null;
  }
}