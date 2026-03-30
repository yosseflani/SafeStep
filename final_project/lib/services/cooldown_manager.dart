class CooldownManager {
  final Duration cooldownDuration;
  final Map<String, DateTime> _lastAlertByCategory = {}; // שומר את זמן ההתראה האחרון

  CooldownManager({
    this.cooldownDuration = const Duration(seconds: 3), // מחכים 3 שניות
  });

  // בודקת האם מותר להתריע שוב
  bool canAlert(String category) {
    final now = DateTime.now();
    final last = _lastAlertByCategory[category];

    if (last == null) return true;
    return now.difference(last) >= cooldownDuration;
  }

  void markAlerted(String category) {
    _lastAlertByCategory[category] = DateTime.now();
  }

  void clear() {
    _lastAlertByCategory.clear();
  }
}