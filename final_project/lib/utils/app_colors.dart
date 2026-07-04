import 'package:flutter/material.dart';

const Color primaryColor = Color(0xFF064E3B);
const Color backgroundColor = Color(0xFFF9FAF6);
const Color cardColor = Colors.white;
const Color textColor = Color(0xFF111827);
const Color subTextColor = Color(0xFF64748B);
const Color borderColor = Color(0xFFE5E7EB);
const Color dangerColor = Color(0xFFEF4444);

/// רקע הדרגתי אחיד לכל המסכים.
const backgroundGradient = LinearGradient(
  begin: Alignment.topCenter,
  end: Alignment.bottomCenter,
  colors: [Color(0xFFFAFAF6), Color(0xFFF1F6F2)],
);