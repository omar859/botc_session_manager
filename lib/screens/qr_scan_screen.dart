import 'package:flutter/material.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

class QrScanScreen extends StatefulWidget {
  const QrScanScreen({super.key});

  @override
  State<QrScanScreen> createState() => _QrScanScreenState();
}

class _QrScanScreenState extends State<QrScanScreen> {
  bool _handled = false;

  void _onDetect(BarcodeCapture capture) {
    if (_handled) return;
    if (capture.barcodes.isEmpty) return;
    final raw = capture.barcodes.first.rawValue;
    if (raw == null) return;
    // Expected format: ip:port:roomCode
    final parts = raw.split(':');
    if (parts.length < 3) return;
    _handled = true;
    Navigator.pop(context, {
      'ip': parts[0],
      'port': parts[1],
      'roomCode': parts.sublist(2).join(':'),
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Scan Room QR Code')),
      body: MobileScanner(onDetect: _onDetect),
    );
  }
}
