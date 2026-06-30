/// מנהל את לוגיקת עדכון התצוגה של אובייקטים מזוהים.
class DisplayManager {

  /// זמן תחילת התצוגה של האובייקט הנוכחי.
  DateTime? currentDisplayStartTime;

  /// משך זמן מינימלי להצגת אובייקט לפני החלפה.
  static const minDisplayDuration = Duration(seconds: 2);

  /// סף שינוי סיכון שמאפשר עדכון מיידי.
  static const emergencyRiskThreshold = 15.0;

  /// קובע האם יש לעדכן את האובייקט המוצג.
  bool shouldUpdateDisplay({
    required bool hasCurrentObject,
    required double? newRisk,
    required double? currentRisk,
  }) {

    if (!hasCurrentObject) {
      return true;
    }

    if (currentDisplayStartTime == null) {
      return true;
    }

    final timeSinceDisplayStart =
    DateTime.now().difference(currentDisplayStartTime!);

    final riskDifference = (newRisk ?? 0) - (currentRisk ?? 0);

    if (timeSinceDisplayStart >= minDisplayDuration) {
      return true;
    }

    if (riskDifference >= emergencyRiskThreshold) {
      return true;
    }

    return false;
  }

  /// מסמן התחלה של הצגת אובייקט חדש.
  void markDisplayStart() {
    currentDisplayStartTime = DateTime.now();
  }

  /// מאפס את מצב התצוגה הפעיל.
  void clearDisplayStart() {
    currentDisplayStartTime = null;
  }
}