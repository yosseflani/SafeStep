class CooldownManager {
  // מחלקה שמנהלת זמן המתנה בין התראות (כדי למנוע ספאם)

  final Duration cooldownDuration;
  // כמה זמן צריך לחכות בין התראות לאותה קטגוריה

  final Map<String, DateTime> _lastAlertByCategory = {};
  // מפה ששומרת לכל קטגוריה את זמן ההתראה האחרון

  CooldownManager({
    this.cooldownDuration = const Duration(seconds: 3),
    // ברירת מחדל: 3 שניות בין התראות
  });

  // בודק האם מותר להתריע שוב על קטגוריה מסוימת
  bool canAlert(String category) {
    final now = DateTime.now();
    // הזמן הנוכחי

    final last = _lastAlertByCategory[category];
    // זמן ההתראה האחרון עבור הקטגוריה

    if (last == null) return true;
    // אם לא הייתה התראה בעבר → מותר

    return now.difference(last) >= cooldownDuration;
    // בודק אם עבר מספיק זמן מאז ההתראה האחרונה
  }

  // מסמן שהתרענו על קטגוריה זו עכשיו
  void markAlerted(String category) {
    _cleanupOldEntries();
    // מנקה נתונים ישנים כדי לא לצבור זיכרון

    _lastAlertByCategory[category] = DateTime.now();
    // שומר את הזמן הנוכחי כהתראה האחרונה
  }

  // איפוס קטגוריה ספציפית בלבד
  void resetCategory(String category) {
    _lastAlertByCategory.remove(category);
    // מוחק את הקטגוריה מהמפה (כאילו לא הייתה התראה)
  }

  // איפוס כללי של כל הקטגוריות
  void clear() {
    _lastAlertByCategory.clear();
    // מוחק את כל הנתונים
  }

  // מסיר ערכים שפג תוקפם כדי למנוע צבירת זיכרון מיותרת
  void _cleanupOldEntries() {
    final now = DateTime.now();
    // הזמן הנוכחי

    final cutoff = cooldownDuration * 2;
    // גבול ניקוי (פי 2 מה-cooldown)

    _lastAlertByCategory.removeWhere(
          (key, value) => now.difference(value) > cutoff,
      // מוחק קטגוריות שעבר עליהן הרבה זמן
    );
  }
}