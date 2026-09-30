import 'package:flutter/material.dart';

import 'ghostwriter_page.dart';

void main() => runApp(const GhostWriterApp());

class GhostWriterApp extends StatelessWidget {
  const GhostWriterApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'GhostWriter',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(useMaterial3: true),
      home: const GhostWriterPage(),
    );
  }
}
