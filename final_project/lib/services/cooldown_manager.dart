class CooldownManager {
  final Duration cooldownDuration;

  // זמן ההתראה האחרון לכל קטגוריה.
  final Map<String, DateTime> _lastAlertByCategory = {};

  CooldownManager({
    this.cooldownDuration = const Duration(seconds: 2),
  });

  /// בודק האם מותר לשלוח התראה עבור קטגוריה מסוימת.
  bool canAlert(String category) {
    final now = DateTime.now();

    final last = _lastAlertByCategory[category];

    if (last == null) return true;

    return now.difference(last) >= cooldownDuration;
  }

  /// מסמן שנשלחה התראה עבור הקטגוריה.
  void markAlerted(String category) {
    _cleanupOldEntries();

    _lastAlertByCategory[category] = DateTime.now();
  }

  /// מאפס את זמן ההתראה של קטגוריה מסוימת.
  void resetCategory(String category) {
    _lastAlertByCategory.remove(category);
  }

  /// מאפס את כל זמני ההתראות.
  void clear() {
    _lastAlertByCategory.clear();
  }

  /// מנקה רשומות ישנות כדי למנוע צבירת מידע מיותרת.
  void _cleanupOldEntries() {
    final now = DateTime.now();

    final cutoff = cooldownDuration * 2;

    _lastAlertByCategory.removeWhere(
          (key, value) => now.difference(value) > cutoff,
    );
  }
}