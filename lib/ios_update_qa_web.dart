import 'package:flutter/material.dart';
import 'app_language.dart';
import 'settings_screen.dart';

void main() => runApp(LanguageScope(child: const MaterialApp(
  debugShowCheckedModeBanner: false,
  home: SettingsScreen(),
)));
