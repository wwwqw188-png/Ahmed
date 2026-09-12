import 'package:flutter/material.dart';

void main() {
  runApp(const TradingSignalsApp());
}

class TradingSignalsApp extends StatelessWidget {
  const TradingSignalsApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'Trading Signals',
      theme: ThemeData(
        brightness: Brightness.dark,
        useMaterial3: true,
      ),
      home: Scaffold(
        appBar: AppBar(
          title: const Text('Trading Signals'),
        ),
        body: const Center(
          child: Text(
            'Trading Signals',
            style: TextStyle(fontSize: 24),
          ),
        ),
      ),
    );
  }
}
