import 'package:experimento7/telas/boas_vindas.dart';
import 'package:experimento7/theme/app_theme.dart'; 
import 'package:flutter/material.dart';

void main() {
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'App de Controle',
      debugShowCheckedModeBanner: false,
      
      
      theme: AppTheme.lightTheme,       
      darkTheme: AppTheme.darkTheme,     
      themeMode: ThemeMode.system,       
      
      home: const TelaBoasVindas(),
    );
  }
}
