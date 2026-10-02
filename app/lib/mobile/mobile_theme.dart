import 'package:flutter/material.dart';

/// Colours shared by the GhostWriter phone UI.
abstract final class GwColors {
  static const background = Color(0xFF222323);
  static const bar = Color(0xFF1B1C1C);
  static const panel = Color(0xFF181919);
  static const chip = Color(0xFF2A2B2B);
  static const border = Color(0xFF3A3C3C);
  static const muted = Color(0xFFA0A2A5);
  static const hint = Color(0xFF7C7E81);
  static const accent = Color(0xFFFF343C);
  static const accentSoft = Color(0xFFFF5258);
  static const gold = Color(0xFFFFC53D);
}

/// Typefaces. Primary is used for headings, buttons and labels; secondary
/// for body copy, hints and anything the user reads at length.
abstract final class GwFonts {
  static const primary = 'PlusJakartaSans';
  static const secondary = 'Poppins';

  /// Secondary text falls back to the primary face if Poppins is missing.
  static const secondaryFallback = [primary];
}

/// Composer and top-bar button size.
const double kGwButton = 44;
