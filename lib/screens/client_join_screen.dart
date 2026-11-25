import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/game_provider.dart';
import '../theme/profile_controller.dart';
import 'lobby_screen.dart';
import 'qr_scan_screen.dart';

class ClientJoinScreen extends StatefulWidget {
  const ClientJoinScreen({super.key});

  @override
  State<ClientJoinScreen> createState() => _ClientJoinScreenState();
}

class _ClientJoinScreenState extends State<ClientJoinScreen> {
  final ipController = TextEditingController();
  final portController = TextEditingController(text: '8080');
  final nameController = TextEditingController();
  bool _connecting = false;
  bool _nameEdited = false;

  @override
  void initState() {
    super.initState();
  }

  Future<void> _scanQr() async {
    final result = await Navigator.push<Map<String, String>>(
      context,
      MaterialPageRoute(builder: (_) => const QrScanScreen()),
    );
    if (result != null) {
      setState(() {
        ipController.text = result['ip']!;
        portController.text = result['port']!;
      });
    }
  }

  Future<void> _connect() async {
    final ip = ipController.text.trim();
    final port = int.tryParse(portController.text.trim()) ?? 8080;
    final name = nameController.text.trim();
    if (ip.isEmpty || name.isEmpty) return;

    setState(() => _connecting = true);

    final profile = context.read<ProfileController>();
    final provider = context.read<GameProvider>();
    await profile.setName(name);
    final success = await provider.joinGame(ip, port, name);

    if (!mounted) return;
    setState(() => _connecting = false);

    if (success) {
      if (mounted) {
        Navigator.pushReplacement(
            context, MaterialPageRoute(builder: (_) => const LobbyScreen()));
      }
    } else {
      // NEW: this is the fix — the person now actually SEES that the
      // connection failed, instead of silently landing on a dead screen.
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Could not connect. Double-check the IP and port match exactly what\'s shown on the host screen, and that both phones are on the same hotspot.',
          ),
          duration: Duration(seconds: 5),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final profile = context.watch<ProfileController>();
    if (!_nameEdited && nameController.text != profile.name) {
      nameController.text = profile.name;
    }
    return Scaffold(
      appBar: AppBar(title: const Text('Join Game')),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          children: [
            ElevatedButton.icon(
              icon: const Icon(Icons.qr_code_scanner),
              label: const Text('Scan QR Code'),
              onPressed: _connecting ? null : _scanQr,
            ),
            const SizedBox(height: 20),
            TextField(
              controller: ipController,
              decoration: const InputDecoration(labelText: 'Host IP'),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: portController,
              decoration: const InputDecoration(labelText: 'Port'),
              keyboardType: TextInputType.number,
            ),
            const SizedBox(height: 12),
            TextField(
              controller: nameController,
              decoration: const InputDecoration(
                labelText: 'Your Name',
                hintText: 'Uses your profile name when available',
              ),
              onChanged: (_) => _nameEdited = true,
            ),
            const SizedBox(height: 20),
            ElevatedButton(
              onPressed: _connecting ? null : _connect,
              child: _connecting
                  ? const SizedBox(
                      height: 20,
                      width: 20,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Text('Connect'),
            ),
          ],
        ),
      ),
    );
  }
}
