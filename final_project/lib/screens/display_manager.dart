class DisplayManager {
  // מחלקה שמחליטה מתי לעדכן את התצוגה (UI)

  DateTime? currentDisplayStartTime;
  // הזמן שבו התחילה התצוגה הנוכחית (יכול להיות null אם אין תצוגה)

  static const minDisplayDuration = Duration(seconds: 3);
  // זמן מינימלי להצגת אובייקט לפני שמחליפים אותו

  static const emergencyRiskThreshold = 30.0;
  // סף חירום: אם הסיכון קופץ מעל ערך זה → מעדכנים מיד

  bool shouldUpdateDisplay({
    required bool hasCurrentObject,
    // האם כבר מוצג אובייקט כרגע

    required double? newRisk,
    // רמת סיכון של האובייקט החדש

    required double? currentRisk,
    // רמת סיכון של האובייקט הנוכחי
  }) {
    if (!hasCurrentObject) {
      return true;
      // אם אין אובייקט מוצג → כן לעדכן
    }

    if (currentDisplayStartTime == null) {
      return true;
      // אם לא ידוע מתי התחילה התצוגה → כן לעדכן
    }

    final timeSinceDisplayStart =
    DateTime.now().difference(currentDisplayStartTime!);
    // מחשב כמה זמן עבר מאז שהתחלנו להציג את האובייקט

    final riskDifference = (newRisk ?? 0) - (currentRisk ?? 0);
    // מחשב כמה הסיכון השתנה (אם null → מתייחס כ-0)

    if (timeSinceDisplayStart >= minDisplayDuration) {
      return true;
      // אם עבר מספיק זמן → מותר לעדכן
    } else if (riskDifference >= emergencyRiskThreshold) {
      return true;
      // אם יש קפיצה גדולה בסיכון → לעדכן מיד (חירום)
    }

    return false;
    // אחרת → לא לעדכן (כדי למנוע ריצוד)
  }

  void markDisplayStart() {
    currentDisplayStartTime = DateTime.now();
    // שומר את הזמן שבו התחילה התצוגה
  }

  void clearDisplayStart() {
    currentDisplayStartTime = null;
    // מאפס את זמן התצוגה (כאילו אין תצוגה פעילה)
  }
}