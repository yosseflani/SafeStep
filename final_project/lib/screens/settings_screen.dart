import 'dart:ui';
import 'package:flutter/material.dart';
import '../utils/app_colors.dart';

class SettingsScreen extends StatefulWidget {
  final double speechRate;
  final bool vibrationEnabled;
  final String language;
  final Future<void> Function()? onVoiceTest;
  final Function(double, bool, String) onChanged;

  const SettingsScreen({
    super.key,
    required this.speechRate,
    required this.vibrationEnabled,
    required this.language,
    required this.onChanged,
    this.onVoiceTest,
  });

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  // ערכי ההגדרות המקומיים של המסך.
  late double rate;
  late bool vibration;
  late String lang;

  bool get _isHebrew => lang.startsWith('he');

  // מחזיר את שם השפה להצגה.
  String get _languageTitle => _isHebrew ? 'עברית' : 'English';

  // מחזיר תיאור מילולי למהירות הדיבור.
  String get _speechRateLabel {
    if (_isHebrew) {
      if (rate < 0.7) return 'איטית';
      if (rate < 1.2) return 'רגילה';
      return 'מהירה';
    }
    if (rate < 0.7) return 'Slow';
    if (rate < 1.2) return 'Normal';
    return 'Fast';
  }

  @override
  void initState() {
    super.initState();

    // טעינת ההגדרות שהתקבלו מהמסך הראשי.
    rate = widget.speechRate.clamp(0.1, 2.0);
    vibration = widget.vibrationEnabled;
    lang = widget.language;
  }

  // מודיע למסך הראשי על שינוי בהגדרות.
  void _notifyChanged() {
    widget.onChanged(rate, vibration, lang);
  }

  @override
  Widget build(BuildContext context) {
    return Directionality(
      textDirection: _isHebrew ? TextDirection.rtl : TextDirection.ltr,
      child: Scaffold(
        backgroundColor: backgroundColor,
        body: Container(
          // רקע הדרגתי למסך ההגדרות.
          decoration: const BoxDecoration(
            gradient: backgroundGradient,
          ),
          child: SafeArea(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(20, 14, 20, 22),
              child: Column(
                children: [
                  _buildHeader(),
                  const SizedBox(height: 26),
                  Expanded(
                    child: SingleChildScrollView(
                      child: Column(
                        children: [
                          _buildSettingTile(
                            icon: Icons.language_rounded,
                            title: _isHebrew ? 'שפה' : 'Language',
                            subtitle: _languageTitle,
                            onTap: _showLanguageSheet,
                          ),
                          const SizedBox(height: 20),
                          _buildSettingTile(
                            icon: Icons.speed_rounded,
                            title: _isHebrew ? 'מהירות דיבור' : 'Speech rate',
                            subtitle: _speechRateLabel,
                            onTap: _showSpeechRateSheet,
                          ),
                          const SizedBox(height: 20),
                          _buildSettingTile(
                            icon: Icons.vibration_rounded,
                            title: _isHebrew ? 'רטט' : 'Vibration',
                            subtitle: vibration
                                ? (_isHebrew ? 'פעיל' : 'Enabled')
                                : (_isHebrew ? 'כבוי' : 'Disabled'),
                            trailing: Switch(
                              value: vibration,
                              activeThumbColor: Colors.white,
                              activeTrackColor: primaryColor,
                              inactiveThumbColor: Colors.white,
                              inactiveTrackColor: const Color(0xFFCBD5E1),
                              onChanged: (value) {
                                setState(() => vibration = value);
                                _notifyChanged();
                              },
                            ),
                            onTap: () {
                              setState(() => vibration = !vibration);
                              _notifyChanged();
                            },
                          ),
                          const SizedBox(height: 26),
                          _buildResetButton(),
                          const SizedBox(height: 4),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  // כותרת המסך.
  Widget _buildHeader() {
    return Row(
      children: [
        _buildBackButton(),
        Expanded(
          child: Center(
            child: Text(
              _isHebrew ? 'הגדרות' : 'Settings',
              style: const TextStyle(
                color: primaryColor,
                fontSize: 34,
                fontWeight: FontWeight.w900,
                letterSpacing: -0.4,
              ),
            ),
          ),
        ),
        const SizedBox(width: 66, height: 66),
      ],
    );
  }

  // כפתור חזרה למסך הראשי.
  Widget _buildBackButton() {
    return Semantics(
      button: true,
      label: _isHebrew ? 'חזרה' : 'Back',
      child: InkWell(
        borderRadius: BorderRadius.circular(999),
        onTap: () => Navigator.of(context).pop(),
        child: Container(
          width: 66,
          height: 66,
          decoration: BoxDecoration(
            color: primaryColor,
            shape: BoxShape.circle,
            border: Border.all(
              color: const Color(0xFFFFF7E8),
              width: 1.4,
            ),
            boxShadow: [
              BoxShadow(
                color: primaryColor.withValues(alpha: .35),
                blurRadius: 22,
                offset: const Offset(0, 10),
              ),
            ],
          ),
          child: const Icon(
            Icons.arrow_back_ios_new_rounded,
            color: Color(0xFFFFF7E8),
            size: 28,
          ),
        ),
      ),
    );
  }

  // כרטיס הגדרה כללי.
  Widget _buildSettingTile({
    required IconData icon,
    required String title,
    required String subtitle,
    required VoidCallback onTap,
    Widget? trailing,
  }) {
    return Semantics(
      button: true,
      label: '$title, $subtitle',
      child: InkWell(
        borderRadius: BorderRadius.circular(34),
        onTap: onTap,
        child: ClipRRect(
          borderRadius: BorderRadius.circular(34),
          child: BackdropFilter(
            filter: ImageFilter.blur(sigmaX: 12, sigmaY: 12),
            child: Container(
              width: double.infinity,
              constraints: const BoxConstraints(
                minHeight: 132,
              ),
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 28),
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.84),
                borderRadius: BorderRadius.circular(34),
                border: Border.all(
                  color: primaryColor.withValues(alpha: 0.55),
                  width: 1.6,
                ),
                boxShadow: _tileShadow,
              ),
              child: Row(
                children: [
                  Container(
                    width: 82,
                    height: 82,
                    decoration: BoxDecoration(
                      color: primaryColor,
                      borderRadius: BorderRadius.circular(26),
                      boxShadow: [
                        BoxShadow(
                          color: primaryColor.withValues(alpha: 0.30),
                          blurRadius: 16,
                          offset: const Offset(0, 7),
                        ),
                      ],
                    ),
                    child: Center(
                      child: Icon(
                        icon,
                        color: const Color(0xFFFFF7E8),
                        size: 42,
                      ),
                    ),
                  ),
                  const SizedBox(width: 22),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Text(
                          title,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            color: textColor,
                            fontSize: 27,
                            fontWeight: FontWeight.w900,
                            height: 1.08,
                          ),
                        ),
                        const SizedBox(height: 10),
                        Text(
                          subtitle,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            color: subTextColor,
                            fontSize: 18,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                      ],
                    ),
                  ),
                  if (trailing != null) ...[
                    const SizedBox(width: 10),
                    trailing,
                  ] else
                    const Icon(
                      Icons.chevron_right_rounded,
                      color: primaryColor,
                      size: 38,
                    ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  // מאפס את ההגדרות לברירת המחדל.
  Widget _buildResetButton() {
    return SizedBox(
      width: double.infinity,
      height: 78,
      child: ElevatedButton.icon(
        onPressed: () {
          setState(() {
            rate = 0.5;
            vibration = true;
            lang = 'he-IL';
          });
          widget.onChanged(0.5, true, 'he-IL');
        },
        icon: const Icon(Icons.refresh_rounded, size: 26),
        label: Text(
          _isHebrew ? 'איפוס הגדרות' : 'Reset settings',
          style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w900),
        ),
        style: ElevatedButton.styleFrom(
          backgroundColor: primaryColor,
          foregroundColor: const Color(0xFFFFF7E8),
          elevation: 0,
          shadowColor: Colors.transparent,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(28)),
        ),
      ),
    );
  }

  // מציג בחירת שפה.
  void _showLanguageSheet() {
    _showSafeStepSheet(
      title: _isHebrew ? 'בחר שפה' : 'Choose language',
      child: Column(
        children: [
          _buildSheetOption(
            title: 'עברית',
            subtitle: 'Hebrew',
            selected: lang == 'he-IL',
            onTap: () {
              setState(() => lang = 'he-IL');
              _notifyChanged();
              Navigator.pop(context);
            },
          ),
          const SizedBox(height: 12),
          _buildSheetOption(
            title: 'English',
            subtitle: 'United States',
            selected: lang == 'en-US',
            onTap: () {
              setState(() => lang = 'en-US');
              _notifyChanged();
              Navigator.pop(context);
            },
          ),
        ],
      ),
    );
  }

  // מציג בחירת מהירות דיבור.
  void _showSpeechRateSheet() {
    double tempRate = rate;

    _showSafeStepSheet(
      title: _isHebrew ? 'מהירות דיבור' : 'Speech rate',
      child: StatefulBuilder(
        builder: (context, setModalState) {
          return Column(
            children: [
              Text(
                tempRate.toStringAsFixed(1),
                style: const TextStyle(
                  color: primaryColor,
                  fontSize: 42,
                  fontWeight: FontWeight.w900,
                ),
              ),
              const SizedBox(height: 8),
              SliderTheme(
                data: SliderTheme.of(context).copyWith(
                  activeTrackColor: primaryColor,
                  inactiveTrackColor: const Color(0xFFD9E5DE),
                  thumbColor: primaryColor,
                  overlayColor: primaryColor.withValues(alpha: 0.15),
                  valueIndicatorColor: primaryColor,
                  trackHeight: 7,
                ),
                child: Slider(
                  value: tempRate,
                  min: 0.1,
                  max: 2.0,
                  divisions: 7,
                  label: tempRate.toStringAsFixed(1),
                  onChanged: (value) {
                    setModalState(() => tempRate = value);
                    setState(() => rate = value);
                  },
                  onChangeEnd: (_) => _notifyChanged(),
                ),
              ),
              const SizedBox(height: 6),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(_isHebrew ? 'איטי' : 'Slow', style: _sheetHintStyle),
                  Text(_isHebrew ? 'מהיר' : 'Fast', style: _sheetHintStyle),
                ],
              ),
            ],
          );
        },
      ),
    );
  }

  // מציג Bottom Sheet אחיד עבור כל ההגדרות.
  void _showSafeStepSheet({required String title, required Widget child}) {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (context) {
        return Directionality(
          textDirection: _isHebrew ? TextDirection.rtl : TextDirection.ltr,
          child: Container(
            padding: EdgeInsets.only(
              left: 22,
              right: 22,
              top: 12,
              bottom: MediaQuery.of(context).viewInsets.bottom + 26,
            ),
            decoration: const BoxDecoration(
              color: backgroundColor,
              borderRadius: BorderRadius.vertical(top: Radius.circular(32)),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Center(
                  child: Container(
                    width: 42,
                    height: 5,
                    decoration: const BoxDecoration(
                      color: Color(0xFFD1D5DB),
                      borderRadius: BorderRadius.all(Radius.circular(999)),
                    ),
                  ),
                ),
                const SizedBox(height: 22),
                Text(
                  title,
                  style: const TextStyle(
                    color: textColor,
                    fontSize: 24,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                const SizedBox(height: 18),
                child,
              ],
            ),
          ),
        );
      },
    );
  }

  // אפשרות בודדת בתוך חלון בחירה.
  Widget _buildSheetOption({
    required String title,
    required String subtitle,
    required bool selected,
    required VoidCallback onTap,
  }) {
    return InkWell(
      borderRadius: BorderRadius.circular(22),
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: cardColor,
          borderRadius: BorderRadius.circular(22),
          border: Border.all(
            color: selected ? primaryColor : borderColor,
            width: selected ? 2 : 1,
          ),
        ),
        child: Row(
          children: [
            Container(
              width: 34,
              height: 34,
              decoration: BoxDecoration(
                color: selected ? primaryColor : const Color(0xFFF1F5F9),
                shape: BoxShape.circle,
              ),
              child: Icon(
                selected ? Icons.check_rounded : Icons.circle_outlined,
                color: selected ? Colors.white : subTextColor,
                size: 20,
              ),
            ),
            const SizedBox(width: 14),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(
                    color: textColor,
                    fontSize: 18,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  subtitle,
                  style: const TextStyle(
                    color: subTextColor,
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  // הצללה אחידה עבור כרטיסי ההגדרות.
  List<BoxShadow> get _tileShadow => [
    BoxShadow(
      color: primaryColor.withValues(alpha: 0.08),
      blurRadius: 28,
      offset: const Offset(0, 14),
    ),
    BoxShadow(
      color: Colors.black.withValues(alpha: 0.045),
      blurRadius: 14,
      offset: const Offset(0, 6),
    ),
  ];

  // סגנון טקסט אחיד להערות בחלונות הבחירה.
  TextStyle get _sheetHintStyle => const TextStyle(
    color: subTextColor,
    fontSize: 14,
    fontWeight: FontWeight.w700,
  );
}