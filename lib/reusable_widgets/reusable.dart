import 'package:flutter/material.dart';

TextField reusableTextField(
  String labelText,
  IconData icon,
  bool isPasswordType,
  TextEditingController controller, {
  Color textColor = Colors.black87,
  Color iconColor = Colors.blueAccent,
  Color fillColor = const Color(0xFFF5F7FA), // light off-white
  Color borderColor = Colors.grey,
  Color focusedBorderColor = Colors.blueAccent,
  required Color backgroundColor,
}) {
  return TextField(
    controller: controller,
    obscureText: isPasswordType,
    enableSuggestions: !isPasswordType,
    autocorrect: !isPasswordType,
    cursorColor: focusedBorderColor,
    style: TextStyle(color: textColor, fontSize: 16),
    decoration: InputDecoration(
      contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 18),
      prefixIcon: Icon(icon, color: iconColor),
      labelText: labelText,
      labelStyle: TextStyle(color: Colors.grey.shade600),
      filled: true,
      fillColor: fillColor,
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide(color: focusedBorderColor, width: 1.5),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide(color: borderColor, width: 1),
      ),
    ),
    keyboardType:
        isPasswordType
            ? TextInputType.visiblePassword
            : TextInputType.emailAddress,
  );
}

Container signInSignUpButton(
  BuildContext context,
  bool isLogin,
  VoidCallback onTap, {
  Color backgroundColor = Colors.blueAccent,
  Color textColor = Colors.white,
}) {
  return Container(
    width: double.infinity,
    height: 50,
    margin: const EdgeInsets.symmetric(vertical: 16),
    child: ElevatedButton(
      onPressed: onTap,
      style: ElevatedButton.styleFrom(
        backgroundColor: backgroundColor,
        foregroundColor: textColor,
        elevation: 4,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
      child: Text(
        isLogin ? 'LOG IN' : 'SIGN UP',
        style: const TextStyle(
          fontSize: 16,
          fontWeight: FontWeight.w600,
          letterSpacing: 1.1,
        ),
      ),
    ),
  );
}
