class CooldownManager {
  // מחלקה שמנהלת זמן המתנה (cooldown) בין התראות
  // המטרה: למנוע ספאם של התראות חוזרות על אותו אובייקט/קטגוריה
  // לדוגמה: אם זיהינו רכב, לא נתריע עליו שוב כל פריים, אלא רק כל X שניות

  final Duration cooldownDuration;
  // Duration = טיפוס שמייצג פרק זמן (שניות, דקות, שעות וכו')
  // כמה זמן צריך לחכות בין התראות לאותה קטגוריה

  final Map<String, DateTime> _lastAlertByCategory = {};
  // Map = מפה שמקשרת מפתח לערך (כמו dictionary ב-Python או object ב-JavaScript)
  // מפתח: String = שם הקטגוריה (למשל "car", "person")
  // ערך: DateTime = הזמן שבו התרענו לאחרונה על הקטגוריה הזו
  // _ = משמעותו שהמשתנה פרטי (private) ולא נגיש מחוץ למחלקה

  CooldownManager({
    // קונסטרקטור עם named parameters (פרמטרים עם שמות)
    this.cooldownDuration = const Duration(seconds: 2),
    // פרמטר אופציונלי עם ברירת מחדל של 2 שניות
    // const = קבוע בזמן קומפילציה (אופטימיזציה לביצועים)
  });

  // בודק האם מותר להתריע שוב על קטגוריה מסוימת
  // מחזיר true אם עבר מספיק זמן מאז ההתראה האחרונה, או אם לא הייתה התראה מעולם
  bool canAlert(String category) {
    // פרמטר: category = שם הקטגוריה לבדיקה (למשל "car")
    final now = DateTime.now();
    // DateTime.now() = מחזיר את הזמן הנוכחי המדויק

    final last = _lastAlertByCategory[category];
    // שולף את זמן ההתראה האחרון עבור הקטגוריה הזו מהמפה
    // אם הקטגוריה לא קיימת במפה → last יהיה null

    if (last == null) return true;
    // אם לא הייתה התראה בעבר על הקטגוריה הזו → מותר להתריע

    return now.difference(last) >= cooldownDuration;
    // difference() = מחשב את הפרש הזמנים בין now ל-last (מחזיר Duration)
    // >= cooldownDuration = בודק אם הפרש הזמנים גדול או שווה ל-cooldown
    // לדוגמה: אם now=10:00:05, last=10:00:00, cooldownDuration=2 שניות
    // אז difference=5 שניות, שזה >= 2 שניות → מותר להתריע
  }

  // מסמן שהתרענו על קטגוריה זו עכשיו
  // קוראים לפונקציה הזו אחרי ששלחנו התראה, כדי לעדכן את הזמן
  void markAlerted(String category) {
    // פרמטר: category = שם הקטגוריה שעליה התרענו
    _cleanupOldEntries();
    // קורא לפונקציה שמנקה ערכים ישנים מהמפה (מונע דליפת זיכרון)

    _lastAlertByCategory[category] = DateTime.now();
    // מעדכן/יוצר ערך במפה: שומר את הזמן הנוכחי כזמן ההתראה האחרון
    // אם הקטגוריה כבר קיימת → מעדכן את הערך
    // אם הקטגוריה לא קיימת → יוצר ערך חדש
  }

  // איפוס קטגוריה ספציפית בלבד
  // שימושי כשרוצים "לשכוח" שהתרענו על קטגוריה מסוימת
  void resetCategory(String category) {
    // פרמטר: category = שם הקטגוריה לאיפוס
    _lastAlertByCategory.remove(category);
    // remove() = מסיר את המפתח והערך שלו מהמפה
    // אחרי זה, canAlert() יחזיר true על הקטגוריה הזו
  }

  // איפוס כללי של כל הקטגוריות
  // מוחק את כל ההיסטוריה של ההתראות
  void clear() {
    _lastAlertByCategory.clear();
    // clear() = מוחק את כל האיברים מהמפה (הופך אותה לריקה)
  }

  // מסיר ערכים שפג תוקפם כדי למנוע צבירת זיכרון מיותרת
  // הפונקציה פרטית (מתחילה ב-_) ולא נגישה מחוץ למחלקה
  void _cleanupOldEntries() {
    final now = DateTime.now();
    // הזמן הנוכחי

    final cutoff = cooldownDuration * 2;
    // גבול ניקוי = פי 2 מה-cooldown
    // לדוגמה: אם cooldown=2 שניות, אז cutoff=4 שניות
    // אנחנו מוחקים רק ערכים שעבר עליהם הרבה יותר מה-cooldown

    _lastAlertByCategory.removeWhere(
      // removeWhere() = מסיר מהמפה את כל האיברים שעומדים בתנאי
      // מקבל פונקציה שמקבלת (key, value) ומחזירה bool
          (key, value) => now.difference(value) > cutoff,
      // key = שם הקטגוריה (לא בשימוש בבדיקה, אבל חייב להיות בפרמטרים)
      // value = הזמן שבו התרענו על הקטגוריה
      // now.difference(value) = כמה זמן עבר מאז ההתראה
      // > cutoff = אם עבר יותר מהגבול → להסיר
    );
  }
}