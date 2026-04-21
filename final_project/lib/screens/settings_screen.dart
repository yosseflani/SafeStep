import 'package:flutter/material.dart'; // ייבוא ספריית Material של Flutter (כוללת את כל רכיבי ה-UI כמו Scaffold, Widget וכו')

const primaryColor = Color(0xFFFF7A00); // קבוע גלובלי של צבע ראשי (כתום). 0xFF = שקיפות מלאה, FF7A00 = הצבע

/// מסך הגדרות לאפליקציית Safe Step
/// מאפשר שליטה בשפה, קול, מהירות דיבור ורטט
class SettingsScreen extends StatefulWidget { // הגדרת מסך שהוא Stateful (כלומר משתנה בזמן ריצה)

  final List<Map<String, dynamic>> voices; // רשימת קולות (voices), כל קול הוא Map עם נתונים כמו name ו-locale

  final double speechRate; // מהירות דיבור התחלתית (למשל 0.5 עד 1.0)

  final bool vibrationEnabled; // האם רטט מופעל או לא (true/false)

  final String language; // השפה הנוכחית (למשל "he-IL" או "en-US")

  final String? selectedVoice; // הקול שנבחר (יכול להיות null אם לא נבחר)

  final Future<void> Function()? onVoiceTest;
  // פונקציה אופציונלית לבדיקת קול
  // היא async (מחזירה Future) ולא מקבלת פרמטרים

  final Function(double, bool, String, String?) onChanged;
  // פונקציה שמופעלת בכל שינוי בהגדרות
  // מקבלת: מהירות, רטט, שפה, קול

  const SettingsScreen({ // קונסטרקטור של המחלקה (יוצר את המסך)
    super.key, // העברת key ל-Widget האב (לניהול זיהוי ה-widget בעץ)

    required this.speechRate, // חובה לשלוח מהירות דיבור
    required this.vibrationEnabled, // חובה לשלוח מצב רטט
    required this.language, // חובה לשלוח שפה
    required this.voices, // חובה לשלוח רשימת קולות
    required this.selectedVoice, // חובה לשלוח קול נבחר (גם אם null)
    required this.onChanged, // חובה לשלוח פונקציה לטיפול בשינויים

    this.onVoiceTest, // לא חובה – ייתכן שלא תהיה פונקציה לבדיקה
  });

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
// Flutter קורא לפונקציה הזו כדי ליצור את ה-State של המסך
// כלומר כאן מתחיל החלק הדינמי של הקומפוננטה
}
class _SettingsScreenState extends State<SettingsScreen> {
  // מחלקת ה-State של המסך (מה שמשתנה בזמן ריצה)

  late double rate; // מהירות דיבור מקומית (תאותחל בהמשך)

  late bool vibration; // מצב רטט מקומי

  late String lang; // שפה נוכחית

  String? voice; // קול נבחר (יכול להיות null)

  List<Map<String, dynamic>> filteredVoices = [];
  // רשימת קולות אחרי סינון לפי שפה

  bool _isTestingVoice = false;
  // האם כרגע מתבצעת בדיקת קול

  @override
  void initState() {
    super.initState(); // קריאה ל-initState של האב (חובה)

    rate = widget.speechRate.clamp(0.1, 2.0);
    // לוקח מהירות מה-widget ומגביל בין 0.3 ל-1.0

    vibration = widget.vibrationEnabled;
    // מעתיק מצב רטט

    lang = widget.language;
    // מעתיק שפה

    voice = widget.selectedVoice;
    // מעתיק קול נבחר

    _filterVoices();
    // מסנן קולות לפי השפה
  }

  /// מסנן קולות לפי השפה
  void _filterVoices() {
    filteredVoices = widget.voices.where((v) {
      // עובר על כל הקולות

      final locale = (v['locale'] ?? '').toString().toLowerCase();
      // לוקח locale ומוודא שהוא string קטן

      return locale.startsWith(lang.split('-')[0].toLowerCase());
      // שומר רק קולות שמתאימים לשפה (למשל "he")
    }).toList();
    // הופך לרשימה חדשה

    // אם הקול שנבחר כבר לא קיים – מאפסים
    if (voice != null && !filteredVoices.any((v) => v['name'] == voice)) {
      voice = null;
    }
  }


  /// מציג שם קול בצורה קריאה
  String _getVoiceName(Map<String, dynamic> v) {
    // פונקציה שמקבלת קול אחד (Map) ומחזירה שם יפה לתצוגה

    final locale = (v['locale'] ?? '').toString();
    // לוקח את ה-locale (למשל "en-US"), ואם אין → מחרוזת ריקה

    final name = (v['name'] ?? '').toString();
    // לוקח את שם הקול (למשל "female_1"), ואם אין → ריק

    return "$locale ($name)";
    // מחזיר טקסט בפורמט: en-US (female_1)
  }

  String get _languageTitle => lang.startsWith('he') ? 'עברית' : 'English';
// getter שמחזיר שם שפה לתצוגה
// אם השפה מתחילה ב-he → עברית, אחרת → English

  bool get _isHebrew => lang.startsWith('he');
// getter שמחזיר true אם השפה היא עברית
// שימושי לשינוי טקסטים ב-UI

  @override
  Widget build(BuildContext context) {
    // הפונקציה שבונה את ה-UI של המסך

    return Scaffold(
      // Scaffold הוא המבנה הראשי של המסך (AppBar, body וכו')

      backgroundColor: const Color(0xFF0F1115),
      // צבע הרקע הכללי של המסך

      appBar: AppBar(
        // הפס העליון של המסך

        backgroundColor: const Color(0xFF0F1115),
        // צבע רקע של ה-AppBar

        elevation: 0,
        // מבטל צל מתחת ל-AppBar

        scrolledUnderElevation: 0,
        // מבטל שינוי elevation בגלילה

        title: Text(
          _isHebrew ? 'הגדרות' : 'Settings',
          // כותרת לפי השפה הנבחרת

          style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
          // עיצוב הטקסט: לבן ובולט
        ),

        iconTheme: const IconThemeData(color: Colors.white),
        // צבע האייקונים ב-AppBar (לבן)
      ),

      body: ListView(
        // אזור התוכן הראשי, עם גלילה אנכית

        padding: const EdgeInsets.all(20),
        // רווח פנימי של 20 מכל הצדדים

        children: [
          // כל הווידג'טים שיופיעו בתוך הרשימה

          const SizedBox(height: 18),
          // רווח אנכי של 18 פיקסלים

          // שפה
          _buildGlassSection(
            // בונה קופסה מעוצבת של ההגדרה

            title: _isHebrew ? 'שפה' : 'Language',
            // כותרת הסקשן לפי השפה

            icon: Icons.language_rounded,
            // אייקון של שפה

            child: DropdownButtonFormField<String>(
              // תיבת בחירה של שפה

              value: lang,
              // הערך הנבחר כרגע

              dropdownColor: const Color(0xFF1A1F27),
              // צבע הרקע של הרשימה שנפתחת

              style: const TextStyle(color: Colors.white),
              // צבע הטקסט בתוך ה-Dropdown

              decoration: _inputDecoration(),
              // עיצוב השדה (גבול, צבע רקע וכו')

              items: const [
                DropdownMenuItem(value: "he-IL", child: Text("עברית 🇮🇱")),
                // אפשרות לעברית

                DropdownMenuItem(value: "en-US", child: Text("English 🇺🇸")),
                // אפשרות לאנגלית
              ],

              onChanged: (value) {
                // מה קורה כשהמשתמש בוחר שפה חדשה

                if (value != null) {
                  // מוודא שהערך לא null

                  setState(() {
                    lang = value;
                    // מעדכן את השפה המקומית

                    _filterVoices();
                    // מסנן מחדש את הקולות לפי השפה החדשה
                  });

                  widget.onChanged(rate, vibration, lang, voice);
                  // שולח את ההגדרות המעודכנות החוצה
                }
              },
            ),
          ),

          const SizedBox(height: 16),
// רווח בין סקשנים

// קול
          _buildGlassSection(
            // סקשן מעוצב של בחירת קול

            title: _isHebrew ? 'קול' : 'Voice',
            // כותרת לפי השפה

            icon: Icons.record_voice_over_rounded,
            // אייקון של קול

            child: Column(
              // עמודה שמכילה כמה רכיבים

              children: [
                DropdownButtonFormField<String>(
                  // תיבת בחירה של קול

                  value: voice,
                  // הקול שנבחר כרגע

                  dropdownColor: const Color(0xFF1A1F27),
                  // צבע הרשימה

                  style: const TextStyle(color: Colors.white),
                  // צבע טקסט

                  decoration: _inputDecoration(),
                  // עיצוב השדה

                  hint: Text(
                    filteredVoices.isEmpty
                        ? (_isHebrew ? 'אין קולות זמינים' : 'No voices available')
                        : (_isHebrew ? 'בחר קול' : 'Select voice'),
                    // טקסט שמופיע אם אין ערך או אין קולות

                    style: const TextStyle(color: Colors.white70),
                  ),

                  items: filteredVoices.map<DropdownMenuItem<String>>((v) {
                    // עובר על כל הקולות המסוננים

                    return DropdownMenuItem<String>(
                      value: v['name'],
                      // הערך של הפריט (שם הקול)

                      child: Text(_getVoiceName(v)),
                      // טקסט יפה לתצוגה (locale + name)
                    );
                  }).toList(),
                  // הופך לרשימה

                  onChanged: filteredVoices.isEmpty
                      ? null
                  // אם אין קולות → מבטל את הבחירה

                      : (value) {
                    if (value != null) {
                      setState(() => voice = value);
                      // מעדכן את הקול שנבחר

                      widget.onChanged(rate, vibration, lang, voice);
                      // שולח את השינוי החוצה
                    }
                  },
                ),

                const SizedBox(height: 14),
                // רווח

                SizedBox(
                  width: double.infinity,
                  // הכפתור יתפרס על כל הרוחב

                  child: OutlinedButton.icon(
                    // כפתור עם אייקון

                    onPressed: _isTestingVoice || widget.onVoiceTest == null
                        ? null
                    // מבטל כפתור אם:
                    // 1. כבר מנגן
                    // 2. אין פונקציה

                        : () async {
                      setState(() => _isTestingVoice = true);
                      // מתחיל מצב טעינה

                      try {
                        await widget.onVoiceTest!();
                        // מפעיל בדיקת קול (async)
                      } catch (e) {
                        // אם יש שגיאה

                        if (mounted) {
                          // בודק שהמסך עדיין קיים

                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(
                              content: Text(
                                _isHebrew
                                    ? 'שגיאה בבדיקת קול: $e'
                                    : 'Voice test error: $e',
                              ),
                              // הודעת שגיאה

                              backgroundColor: Colors.red.shade900,
                            ),
                          );
                        }
                      } finally {
                        if (mounted) setState(() => _isTestingVoice = false);
                        // מסיים טעינה
                      }
                    },

                    icon: _isTestingVoice
                        ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(
                        // מציג loader בזמן ניגון

                        strokeWidth: 2,
                        color: primaryColor,
                      ),
                    )
                        : const Icon(Icons.volume_up_rounded),
                    // אם לא מנגן → אייקון רגיל

                    label: Text(
                      _isTestingVoice
                          ? (_isHebrew ? 'מנגן...' : 'Playing...')
                          : (_isHebrew ? 'בדיקת קול' : 'Voice test'),
                      // טקסט משתנה לפי מצב
                    ),

                    style: OutlinedButton.styleFrom(
                      foregroundColor: primaryColor,
                      // צבע טקסט ואייקון

                      side: BorderSide(color: primaryColor.withOpacity(0.7)),
                      // גבול

                      padding: const EdgeInsets.symmetric(vertical: 14),
                      // גובה הכפתור

                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(16),
                        // פינות מעוגלות
                      ),
                    ),
                  ),
                ),

                if (filteredVoices.isEmpty) ...[
                  // אם אין קולות → מציג הודעה

                  const SizedBox(height: 10),

                  Text(
                    _isHebrew
                        ? '💡 טיפ: התקן חבילת שפה במכשיר להוספת קולות'
                        : '💡 Tip: Install a language pack on your device to add voices',

                    style: const TextStyle(fontSize: 12, color: Colors.white54),
                    textAlign: TextAlign.center,
                  ),
                ],
              ],
            ),
          ),

          const SizedBox(height: 16),
// רווח לסקשן הבא

          // מהירות דיבור
          _buildGlassSection(
            // סקשן מעוצב של מהירות דיבור

            title: _isHebrew ? 'מהירות דיבור' : 'Speech Rate',
            // כותרת לפי השפה

            icon: Icons.speed_rounded,
            // אייקון של מהירות

            child: Column(
              // עמודה שמכילה את ה-Slider והטקסט

              crossAxisAlignment: CrossAxisAlignment.start,
              // מיישר את הילדים להתחלה (שמאל/ימין לפי הכיוון)

              children: [
                SliderTheme(
                  // עיצוב מותאם ל-Slider

                  data: SliderTheme.of(context).copyWith(
                    // לוקח את העיצוב הקיים ומשנה חלקים ממנו

                    activeTrackColor: primaryColor,
                    // צבע החלק הפעיל של הפס

                    inactiveTrackColor: Colors.white24,
                    // צבע החלק הלא פעיל

                    thumbColor: primaryColor,
                    // צבע העיגול של ה-Slider

                    overlayColor: primaryColor.withOpacity(0.15),
                    // צבע ה"הילה" מסביב בזמן נגיעה

                    valueIndicatorColor: primaryColor,
                    // צבע בועת הערך
                  ),

                  child: Slider(
                    // רכיב הזזה לבחירת מהירות

                    value: rate,
                    // הערך הנוכחי

                    min: 0.1,
                    // ערך מינימלי

                    max: 2,
                    // ערך מקסימלי

                    divisions: 7,
                    // מחלק את הטווח ל-7 חלקים

                    label: rate.toStringAsFixed(1),
                    // טקסט הערך עם ספרה אחת אחרי הנקודה

                    onChanged: (v) => setState(() => rate = v),
                    // בזמן גרירה מעדכן את rate ומרענן UI

                    onChangeEnd: (v) =>
                        widget.onChanged(rate, vibration, lang, voice),
                    // כשהמשתמש מסיים לגרור, שולח את הערכים החוצה
                  ),
                ),

                Text(
                  _isHebrew
                      ? 'מהירות נוכחית: ${rate.toStringAsFixed(1)}'
                      : 'Current speed: ${rate.toStringAsFixed(1)}',
                  // מציג את הערך הנוכחי לפי השפה

                  style: const TextStyle(fontSize: 14, color: Colors.white70),
                  // עיצוב הטקסט
                ),
              ],
            ),
          ),

          const SizedBox(height: 16),
// רווח בין הסקשנים

// רטט
          _buildGlassSection(
            // סקשן מעוצב של רטט

            title: _isHebrew ? 'רטט' : 'Vibration',
            // כותרת לפי השפה

            icon: Icons.vibration_rounded,
            // אייקון של רטט

            child: SwitchListTile(
              // שורת הגדרה עם מתג

              contentPadding: EdgeInsets.zero,
              // מבטל רווח פנימי ברירת מחדל

              title: Text(
                vibration
                    ? (_isHebrew ? 'רטט פעיל' : 'Vibration enabled')
                    : (_isHebrew ? 'רטט כבוי' : 'Vibration disabled'),
                // טקסט משתנה לפי מצב הרטט והשפה

                style: const TextStyle(fontSize: 16, color: Colors.white),
                // עיצוב הטקסט
              ),

              value: vibration,
              // האם המתג דלוק או כבוי

              activeColor: primaryColor,
              // צבע המתג כשהוא פעיל

              onChanged: (v) {
                setState(() => vibration = v);
                // מעדכן את מצב הרטט במסך

                widget.onChanged(rate, vibration, lang, voice);
                // שולח את הערכים המעודכנים החוצה
              },
            ),
          ),

          const SizedBox(height: 24),
// רווח גדול יותר לפני החלק הבא

          // איפוס להגדרות ברירת מחדל
          Center(
            // ממרכז את הכפתור

            child: TextButton.icon(
              // כפתור טקסט עם אייקון

              onPressed: () {
                // מה קורה כשלוחצים על הכפתור

                setState(() {
                  rate = 0.5;
                  // מחזיר את מהירות הדיבור לברירת מחדל

                  vibration = true;
                  // מפעיל רטט כברירת מחדל

                  lang = 'he-IL';
                  // מחזיר שפה לעברית

                  voice = null;
                  // מאפס קול נבחר

                  _filterVoices();
                  // מסנן מחדש קולות לפי השפה החדשה
                });

                widget.onChanged(0.5, true, 'he-IL', null);
                // שולח החוצה את ערכי ברירת המחדל
              },

              icon: const Icon(Icons.refresh_rounded, size: 18),
              // אייקון של רענון/איפוס

              label: Text(
                _isHebrew ? 'איפוס להגדרות ברירת מחדל' : 'Reset to defaults',
                // טקסט הכפתור לפי השפה

                style: const TextStyle(fontSize: 13),
                // גודל טקסט
              ),

              style: TextButton.styleFrom(foregroundColor: Colors.grey),
              // צבע הכפתור
            ),
          ),
        ],
// סוף רשימת ה-children של ה-ListView

      ),
      // סוף ה-ListView

    );
    // סוף ה-Scaffold
  }
  // סוף build()

  Widget _buildGlassSection({
    // פונקציית עזר שבונה סקשן מעוצב קבוע

    required String title,
    // כותרת הסקשן

    required IconData icon,
    // אייקון הסקשן

    required Widget child,
    // התוכן הפנימי של הסקשן
  }) {
    return Container(
      // קונטיינר מעוצב שמחזיק את כל הסקשן

      padding: const EdgeInsets.all(18),
      // רווח פנימי מכל הצדדים

      decoration: BoxDecoration(
        // עיצוב הרקע והמסגרת

        color: const Color(0xFF171B22),
        // צבע רקע של הסקשן

        borderRadius: BorderRadius.circular(24),
        // פינות מעוגלות

        border: Border.all(color: Colors.white.withOpacity(0.05)),
        // מסגרת עדינה

        boxShadow: [
          // צל של הקופסה

          BoxShadow(
            color: Colors.black.withOpacity(0.22),
            // צבע הצל

            blurRadius: 16,
            // רמת הטשטוש של הצל

            offset: const Offset(0, 8),
            // מיקום הצל: למטה
          ),
        ],
      ),

      child: Column(
        // התוכן בתוך הסקשן מסודר אנכית

        crossAxisAlignment: CrossAxisAlignment.start,
        // יישור להתחלה

        children: [
          Row(
            // שורה של אייקון + כותרת

            children: [
              Icon(icon, color: primaryColor),
              // מציג את האייקון בצבע הראשי

              const SizedBox(width: 8),
              // רווח בין האייקון לטקסט

              Text(
                title,
                // כותרת הסקשן

                style: const TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                  color: Colors.white,
                  // עיצוב הכותרת
                ),
              ),
            ],
          ),

          const SizedBox(height: 14),
          // רווח בין הכותרת לתוכן

          child,
          // כאן נכנס התוכן שנשלח לפונקציה
        ],
      ),
    );
  }

  InputDecoration _inputDecoration() {
    // פונקציה שמחזירה עיצוב אחיד לשדות קלט (כמו Dropdown)

    return InputDecoration(
      // אובייקט שמגדיר איך שדה הקלט נראה

      filled: true,
      // אומר שהשדה יהיה עם רקע מלא

      fillColor: const Color(0xFF1E242D),
      // צבע הרקע של השדה

      hintStyle: const TextStyle(color: Colors.white54),
      // עיצוב טקסט ה-hint (טקסט אפור בהיר)

      enabledBorder: OutlineInputBorder(
        // גבול השדה כשהוא לא בפוקוס

        borderRadius: BorderRadius.circular(16),
        // פינות מעוגלות

        borderSide: BorderSide(color: Colors.white.withOpacity(0.05)),
        // גבול עדין מאוד
      ),

      focusedBorder: OutlineInputBorder(
        // גבול כשהשדה בפוקוס (לחוץ/נבחר)

        borderRadius: BorderRadius.circular(16),
        // אותו עיגול פינות

        borderSide: const BorderSide(color: primaryColor),
        // גבול בצבע הראשי (כתום)
      ),

      contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
      // רווח פנימי בתוך השדה (ימין/שמאל + למעלה/למטה)
    );
  }
}