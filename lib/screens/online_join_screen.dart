import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/game_provider.dart';
import '../theme/profile_controller.dart';
import 'lobby_screen.dart';

class OnlineJoinScreen extends StatefulWidget {
  const OnlineJoinScreen({super.key});

  @override
  State<OnlineJoinScreen> createState() => _OnlineJoinScreenState();
}

class _OnlineJoinScreenState extends State<OnlineJoinScreen> {
  final roomController = TextEditingController();
  final nameController = TextEditingController();
  bool joining = false;

  @override
  void initState() {
    super.initState();
    nameController.text = context.read<ProfileController>().name;
  }

  @override
  void dispose() {
    roomController.dispose();
    nameController.dispose();
    super.dispose();
  }

  Future<void> _join() async {
    final room = roomController.text.trim();
    final name = nameController.text.trim();
    if (room.isEmpty || name.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Enter a room code and your name.')));
      return;
    }
    setState(() => joining = true);
    final profile = context.read<ProfileController>();
    final provider = context.read<GameProvider>();
    await profile.setName(name);
    final success = await provider.joinOnlineGame(room, name);
    if (!mounted) return;
    setState(() => joining = false);
    if (success) {
      Navigator.pushReplacement(
          context, MaterialPageRoute(builder: (_) => const LobbyScreen()));
    } else {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(provider.lastError ?? 'Could not join online game.')));
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(title: const Text('Join Online Game')),
        body: ListView(
          padding: const EdgeInsets.all(24),
          children: [
            const Text('Room code'),
            TextField(
                controller: roomController,
                textCapitalization: TextCapitalization.characters),
            const SizedBox(height: 18),
            const Text('Your name'),
            TextField(controller: nameController),
            const SizedBox(height: 28),
            FilledButton.icon(
              onPressed: joining ? null : _join,
              icon: joining
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2))
                  : const Icon(Icons.public),
              label: Text(joining ? 'Joining...' : 'Join Online Game'),
            ),
          ],
        ),
      );
}
