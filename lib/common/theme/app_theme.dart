import 'package:flutter/material.dart';

const appSeedColor = Color(0xFF0073A4); // Color base de ZeePubs

ThemeData buildAppTheme(ColorScheme colorScheme) {
  return ThemeData(
    useMaterial3: true,
    visualDensity: VisualDensity.compact,
    colorScheme: colorScheme,
  );
}
