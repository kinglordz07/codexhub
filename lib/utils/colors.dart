import 'package:flutter/material.dart';

/// Converts a hex color string (e.g. "#FFFFFF" or "FFFFFF") to a [Color].
/// Supports strings with or without the leading '#'.
/// If the alpha channel is not specified, it defaults to fully opaque.
Color hexStringToColor(String hexColor) {
  // Remove leading '#' and convert to uppercase
  String cleanedHex = hexColor.toUpperCase().replaceAll("#", "");

  // Add alpha channel if not provided
  if (cleanedHex.length == 6) {
    cleanedHex = "FF$cleanedHex";
  }

  // Validate length (should be 8 after adding alpha)
  if (cleanedHex.length != 8) {
    throw FormatException("Invalid hex color format: $hexColor");
  }

  return Color(int.parse(cleanedHex, radix: 16));
}
