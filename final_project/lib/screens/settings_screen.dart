import 'package:flutter/material.dart';

const primaryColor = Color(0xFFFF7A00);

// מסך דינמי לוכן stateful
class SettingsScreen extends StatefulWidget {
  final double speechRate;
  final bool vibrationEnabled;
  final String language;
  final List voices;
  final String? selectedVoice;
  final VoidCallback? onVoiceTest;

  // פונקציה שמעדכנת את ה mainScreen
  final Function(double, bool, String, String?) onChanged;

  // מקבל את הערכים מהמסך הראשי בהתחלה
  const SettingsScreen({
    super.key,
    required this.speechRate,
    required this.vibrationEnabled,
    required this.language,
    required this.voices,
    required this.selectedVoice,
    required this.onChanged,
    this.onVoiceTest,
  });

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

// מצבים פנימיים תוך כדי שינוי ההגדרות
class _SettingsScreenState extends State<SettingsScreen> {
  late double rate;
  late bool vibration;
  late String lang;
  String? voice;

  List filteredVoices = [];

  // כשנפתח המסך טוענים את ההגדרות שהגיעו מהמסך הראשי ואת רשימת הקולות התואמים לשפה
  @override
  void initState() {
    super.initState();
    rate = widget.speechRate;
    vibration = widget.vibrationEnabled;
    lang = widget.language;
    voice = widget.selectedVoice;
    _filterVoices();
  }

  // מסננת את הקולות לפי השפה הנבחרת
  void _filterVoices() {
    filteredVoices = widget.voices.where((v) {
      final locale = (v['locale'] ?? '').toString().toLowerCase();
      return locale.startsWith(lang.split('-')[0].toLowerCase());
    }).toList();

    final currentVoiceStillExists =
    filteredVoices.any((v) => v['name'] == voice);
    if (!currentVoiceStillExists) {
      voice = null;
    }
  }

  // זה היה ממש לא קריא את אתחלתי את השמות של כולם לאותו דבר - נראה נשנה וזה זמני
  // הייתי עושה אחד אחד אבל זה תלוי מכשיר הקולות הזמינים אז אמרתי נתלבט על זה לפני כל העבודה
  String _getVoiceName(dynamic v) {
    final locale = (v['locale'] ?? '').toString();
    final name = (v['name'] ?? '').toString();
    final shortName = name.split('-').take(2).join('-');
    return "$locale ($shortName)";
  }

  String get _languageTitle => lang.startsWith('he') ? 'עברית' : 'English';

  // כל התצוגה של המסך
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0F1115),
      appBar: AppBar(
        backgroundColor: const Color(0xFF0F1115),
        elevation: 0,
        scrolledUnderElevation: 0,
        title: const Text(
          "Settings",
          style: TextStyle(
            color: Colors.white,
            fontWeight: FontWeight.bold,
          ),
        ),
        iconTheme: const IconThemeData(color: Colors.white),
      ),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          _buildTopCard(),
          const SizedBox(height: 18),
          _buildGlassSection(
            title: "Language",
            icon: Icons.language_rounded,
            child: DropdownButtonFormField<String>(
              value: lang,
              dropdownColor: const Color(0xFF1A1F27),
              style: const TextStyle(color: Colors.white),
              decoration: _inputDecoration(),
              items: const [
                DropdownMenuItem(
                  value: "he-IL",
                  child: Text("עברית 🇮🇱"),
                ),
                DropdownMenuItem(
                  value: "en-US",
                  child: Text("English 🇺🇸"),
                ),
              ],
              onChanged: (value) {
                if (value != null) {
                  setState(() {
                    lang = value;
                    _filterVoices();
                  });
                  widget.onChanged(rate, vibration, lang, voice);
                }
              },
            ),
          ),
          const SizedBox(height: 16),
          _buildGlassSection(
            title: "Voice",
            icon: Icons.record_voice_over_rounded,
            child: Column(
              children: [
                DropdownButtonFormField<String>(
                  value: voice,
                  dropdownColor: const Color(0xFF1A1F27),
                  style: const TextStyle(color: Colors.white),
                  decoration: _inputDecoration(),
                  hint: const Text(
                    "Select voice",
                    style: TextStyle(color: Colors.white70),
                  ),
                  items: filteredVoices.map<DropdownMenuItem<String>>((v) {
                    return DropdownMenuItem<String>(
                      value: v['name'],
                      child: Text(_getVoiceName(v)),
                    );
                  }).toList(),
                  onChanged: (value) {
                    setState(() => voice = value);
                    widget.onChanged(rate, vibration, lang, voice);
                  },
                ),
                const SizedBox(height: 14),
                SizedBox(
                  width: double.infinity,
                  child: OutlinedButton.icon(
                    onPressed: widget.onVoiceTest,
                    icon: const Icon(Icons.volume_up_rounded),
                    label: const Text("Voice test"),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: primaryColor,
                      side: BorderSide(
                        color: primaryColor.withOpacity(0.7),
                      ),
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(16),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          _buildGlassSection(
            title: "Speech Rate",
            icon: Icons.speed_rounded,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SliderTheme(
                  data: SliderTheme.of(context).copyWith(
                    activeTrackColor: primaryColor,
                    inactiveTrackColor: Colors.white24,
                    thumbColor: primaryColor,
                    overlayColor: primaryColor.withOpacity(0.15),
                    valueIndicatorColor: primaryColor,
                  ),
                  child: Slider(
                    value: rate,
                    min: 0.3,
                    max: 1,
                    divisions: 7,
                    label: rate.toStringAsFixed(1),
                    onChanged: (v) {
                      setState(() => rate = v);
                      widget.onChanged(rate, vibration, lang, voice);
                    },
                  ),
                ),
                Text(
                  "Current speed: ${rate.toStringAsFixed(1)}",
                  style: const TextStyle(
                    fontSize: 14,
                    color: Colors.white70,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          _buildGlassSection(
            title: "Vibration",
            icon: Icons.vibration_rounded,
            child: SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: Text(
                vibration ? "Vibration enabled" : "Vibration disabled",
                style: const TextStyle(
                  fontSize: 16,
                  color: Colors.white,
                ),
              ),
              value: vibration,
              activeColor: primaryColor,
              onChanged: (v) {
                setState(() => vibration = v);
                widget.onChanged(rate, vibration, lang, voice);
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTopCard() {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [
            Color(0xFFFF8A26),
            Color(0xFFFF6A00),
          ],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(26),
        boxShadow: [
          BoxShadow(
            color: primaryColor.withOpacity(0.24),
            blurRadius: 18,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Row(
        children: [
          Container(
            width: 62,
            height: 62,
            decoration: BoxDecoration(
              color: Colors.white.withOpacity(0.16),
              borderRadius: BorderRadius.circular(18),
            ),
            child: const Icon(
              Icons.tune_rounded,
              color: Colors.white,
              size: 30,
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  "System Settings",
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 22,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  "Current language: $_languageTitle",
                  style: TextStyle(
                    color: Colors.white.withOpacity(0.92),
                    fontSize: 14,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildGlassSection({
    required String title,
    required IconData icon,
    required Widget child,
  }) {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: const Color(0xFF171B22),
        borderRadius: BorderRadius.circular(24),
        border: Border.all(
          color: Colors.white.withOpacity(0.05),
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.22),
            blurRadius: 16,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, color: primaryColor),
              const SizedBox(width: 8),
              Text(
                title,
                style: const TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                  color: Colors.white,
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          child,
        ],
      ),
    );
  }

  InputDecoration _inputDecoration() {
    return InputDecoration(
      filled: true,
      fillColor: const Color(0xFF1E242D),
      hintStyle: const TextStyle(color: Colors.white54),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(16),
        borderSide: BorderSide(
          color: Colors.white.withOpacity(0.05),
        ),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(16),
        borderSide: const BorderSide(
          color: primaryColor,
        ),
      ),
      contentPadding: const EdgeInsets.symmetric(
        horizontal: 14,
        vertical: 14,
      ),
    );
  }
}