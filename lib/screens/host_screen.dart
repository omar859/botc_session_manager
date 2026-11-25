import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:qr_flutter/qr_flutter.dart';
import '../providers/game_provider.dart';
import 'admin_panel.dart';

class HostScreen extends StatefulWidget {
  const HostScreen({super.key});

  @override
  State<HostScreen> createState() => _HostScreenState();
}

class _HostScreenState extends State<HostScreen> {
  bool _showAppQr = false;
  bool _online = false;

  Future<void> _copyText(String value, String label) async {
    await Clipboard.setData(ClipboardData(text: value));
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('$label copied')),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Consumer<GameProvider>(
      builder: (context, provider, _) {
        final colors = Theme.of(context).colorScheme;
        if (!provider.isHost) {
          return Scaffold(
            appBar: AppBar(backgroundColor: Colors.transparent, elevation: 0),
            body: Center(
              child: SingleChildScrollView(
                padding: const EdgeInsets.symmetric(horizontal: 24),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.wifi_tethering, size: 56, color: colors.primary),
                    const SizedBox(height: 16),
                    Text(
                      'You\'ll host this game session. Players join by scanning a QR code — make sure every device is on the same hotspot.',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                          fontSize: 15, color: colors.onSurfaceVariant),
                    ),
                    const SizedBox(height: 28),
                    SegmentedButton<bool>(
                      segments: const [
                        ButtonSegment(
                            value: false,
                            label: Text('Hotspot'),
                            icon: Icon(Icons.wifi_tethering)),
                        ButtonSegment(
                            value: true,
                            label: Text('Online'),
                            icon: Icon(Icons.public)),
                      ],
                      selected: {_online},
                      onSelectionChanged: (selection) =>
                          setState(() => _online = selection.first),
                    ),
                    const SizedBox(height: 22),
                    OutlinedButton(
                      onPressed: () async {
                        final started = _online
                            ? await provider.startOnlineHosting()
                            : await provider.startHosting();
                        if (!started && context.mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(
                              content: Text(provider.lastError ??
                                  'Could not start hosting. Please try again.'),
                              duration: const Duration(seconds: 5),
                            ),
                          );
                        }
                      },
                      style: OutlinedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 32, vertical: 14),
                        textStyle: const TextStyle(fontSize: 18),
                        side: BorderSide(color: colors.primary, width: 1.2),
                        shape: const RoundedRectangleBorder(
                            borderRadius: BorderRadius.zero),
                        foregroundColor: colors.primary,
                      ),
                      child: Text(
                          _online ? 'Start Online Hosting' : 'Start Hosting'),
                    ),
                  ],
                ),
              ),
            ),
          );
        }

        final joinData =
            '${provider.hostIp}:${provider.hostPort}:${provider.roomCode}';
        final browserUrl = provider.onlineJoinUrl ??
            'http://${provider.hostIp}:${provider.hostPort}/play';
        final pendingCount = provider.room?.pendingRequests.length ?? 0;
        final seatedCount = provider.room?.players.length ?? 0;

        return PopScope(
          canPop: false,
          onPopInvokedWithResult: (didPop, result) async {
            if (didPop) return;
            final shouldLeave = await showDialog<bool>(
                  context: context,
                  builder: (dialogContext) => AlertDialog(
                    title: const Text('End session?'),
                    content: const Text(
                        'This will stop the current host session and return to the main screen.'),
                    actions: [
                      TextButton(
                          onPressed: () =>
                              Navigator.of(dialogContext).pop(false),
                          child: const Text('Cancel')),
                      FilledButton(
                          onPressed: () =>
                              Navigator.of(dialogContext).pop(true),
                          child: const Text('End Session')),
                    ],
                  ),
                ) ??
                false;
            if (!shouldLeave || !context.mounted) return;
            await provider.stopHosting();
            if (context.mounted) Navigator.of(context).pop();
          },
          child: Scaffold(
            appBar: AppBar(
              title: GestureDetector(
                onLongPress: () => _copyText(provider.roomCode, 'Room code'),
                child: Text('Room: ${provider.roomCode}'),
              ),
            ),
            body: SingleChildScrollView(
              padding: const EdgeInsets.symmetric(vertical: 16),
              child: Column(
                children: [
                  if (provider.isOnlineHost) ...[
                    Card(
                      margin: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                      child: ListTile(
                        leading: const Icon(Icons.public),
                        title: const Text('Online players'),
                        subtitle: Text(provider.onlineConnected
                            ? 'Connected — share the link or QR code'
                            : 'Connecting to Cloudflare relay…'),
                        trailing: Icon(
                          provider.onlineConnected
                              ? Icons.cloud_done
                              : Icons.cloud_sync,
                          color: colors.primary,
                        ),
                      ),
                    ),
                  ],
                  // Primary path: browser join, no app install needed.
                  const Text('Scan to join — no app needed',
                      style: TextStyle(fontSize: 13, color: Colors.white70)),
                  const SizedBox(height: 10),
                  Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(12)),
                    child: QrImageView(
                      data: browserUrl,
                      version: QrVersions.auto,
                      size: 220,
                      backgroundColor: Colors.white,
                      // ignore: deprecated_member_use
                      foregroundColor: Colors.black,
                    ),
                  ),
                  const SizedBox(height: 8),
                  GestureDetector(
                    onLongPress: () => _copyText(browserUrl, 'Join link'),
                    child: SelectableText(
                      browserUrl,
                      style: const TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.bold,
                          color: Colors.amber),
                    ),
                  ),
                  const SizedBox(height: 20),

                  // Secondary path: native app scan, collapsed by default.
                  TextButton.icon(
                    icon: Icon(
                        _showAppQr ? Icons.expand_less : Icons.expand_more),
                    label: const Text('Have the Table Chat app instead?'),
                    onPressed: () => setState(() => _showAppQr = !_showAppQr),
                  ),
                  if (_showAppQr) ...[
                    const SizedBox(height: 8),
                    Container(
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(12)),
                      child: QrImageView(
                        data: joinData,
                        version: QrVersions.auto,
                        size: 180,
                        backgroundColor: Colors.white,
                        // ignore: deprecated_member_use
                        foregroundColor: Colors.black,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text('IP: ${provider.hostIp}   Port: ${provider.hostPort}',
                        style: TextStyle(
                            fontSize: 12, color: colors.onSurfaceVariant)),
                  ],

                  const SizedBox(height: 28),
                  const Divider(indent: 24, endIndent: 24),
                  const SizedBox(height: 12),

                  // Status summary + single entry point into the live panel.
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      _statChip(Icons.person_add, '$pendingCount pending',
                          Colors.orange),
                      const SizedBox(width: 10),
                      _statChip(Icons.groups, '$seatedCount seated',
                          Colors.deepPurple),
                    ],
                  ),
                  const SizedBox(height: 20),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 24),
                    child: SizedBox(
                      width: double.infinity,
                      child: FilledButton.icon(
                        icon: const Icon(Icons.admin_panel_settings),
                        label: const Text('Enter Game'),
                        style: FilledButton.styleFrom(
                          backgroundColor: colors.primary,
                          foregroundColor: colors.onPrimary,
                          padding: const EdgeInsets.symmetric(vertical: 16),
                        ),
                        onPressed: () => Navigator.push(
                            context,
                            MaterialPageRoute(
                                builder: (_) => const AdminPanel())),
                      ),
                    ),
                  ),
                  const SizedBox(height: 8),
                  const Text(
                    'Approve players, import a script, and manage the game from there.',
                    textAlign: TextAlign.center,
                    style: TextStyle(fontSize: 11, color: Colors.grey),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _statChip(IconData icon, String label, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: color.withOpacity(0.15),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: color),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: color),
          const SizedBox(width: 6),
          Text(label,
              style: TextStyle(
                  fontSize: 12, color: color, fontWeight: FontWeight.w600)),
        ],
      ),
    );
  }
}
