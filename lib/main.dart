import 'package:flutter/material.dart';
import 'package:matrix/matrix.dart';
import 'screens/login_screen.dart';

void main() {
  Logs().level = Level.verbose;
  runApp(
    const MaterialApp(debugShowCheckedModeBanner: false, home: LoginScreen()),
  );
}
