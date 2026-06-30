import 'package:flutter/material.dart';

class SafeStepLogo extends StatelessWidget {
  const SafeStepLogo({super.key, required this.size});

  final double size;

  @override
  Widget build(BuildContext context) {
    return Image.asset(
      'assets/images/logo_drawing.png',
      width: size,
      height: size,
      fit: BoxFit.contain,
    );
  }
}