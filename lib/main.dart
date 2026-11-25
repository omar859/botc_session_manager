import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'providers/game_provider.dart';
import 'screens/host_screen.dart';
import 'screens/join_game_screen.dart';
import 'screens/lobby_screen.dart';
import 'screens/game_info_screen.dart';
import 'screens/profile_screen.dart';
import 'theme/app_theme.dart'; // NEW
import 'theme/appearance_controller.dart';
import 'theme/profile_controller.dart';
import 'widgets/night_overlay.dart';

void main() {
  runApp(
    MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (_) => GameProvider()),
        ChangeNotifierProvider(
          create: (_) => AppearanceController()..load(),
        ),
        ChangeNotifierProvider(
          create: (_) => ProfileController()..load(),
        ),
      ],
      child: const MyApp(),
    ),
  );
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    final appearance = context.watch<AppearanceController>();
    return MaterialApp(
      title: 'Table Chat',
      theme: buildAppTheme(
        mode: appearance.mode,
        accent: appearance.accent,
      ),
      builder: (context, child) => Stack(
        fit: StackFit.expand,
        children: [
          child ?? const SizedBox.shrink(),
          const NightOverlay(),
          const DayNightSoundListener(),
        ],
      ),
      home: const HomeScreen(),
    );
  }
}

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  bool _resuming = false;

  @override
  void initState() {
    super.initState();
  }

  Future<void> _resumeGame(GameProvider provider) async {
    setState(() => _resuming = true);
    final success = await provider.resumeSession();
    if (!mounted) return;
    setState(() => _resuming = false);
    if (success) {
      if (mounted) {
        Navigator.push(
            context, MaterialPageRoute(builder: (_) => const LobbyScreen()));
      }
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(provider.lastError ??
              'Could not resume — the host may be offline. Try Join Game instead.'),
          duration: const Duration(seconds: 5),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<GameProvider>();
    final colors = Theme.of(context).colorScheme;
    return Scaffold(
      extendBodyBehindAppBar: true,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
      ),
      body: Container(
        decoration: const BoxDecoration(
          image: DecorationImage(
            image: AssetImage('assets/images/back_ground.png'),
            fit: BoxFit.cover,
          ),
        ),
        child: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              if (provider.hasResumableSession) ...[
                OutlinedButton.icon(
                  icon: _resuming
                      ? const SizedBox(
                          height: 18,
                          width: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.replay),
                  label: Text(_resuming ? 'RESUMING...' : 'RESUME GAME'),
                  style: OutlinedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 24, vertical: 12),
                    textStyle: const TextStyle(fontSize: 18),
                    side: BorderSide(color: colors.primary, width: 1.2),
                    shape: const RoundedRectangleBorder(
                      borderRadius: BorderRadius.zero,
                    ),
                    foregroundColor: colors.primary,
                  ),
                  onPressed: _resuming ? null : () => _resumeGame(provider),
                ),
                const SizedBox(height: 20),
              ],
              OutlinedButton.icon(
                icon: const Icon(Icons.wifi_tethering),
                label: const Text('HOST GAME'),
                style: OutlinedButton.styleFrom(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                  textStyle: const TextStyle(fontSize: 18),
                  side: BorderSide(color: colors.primary, width: 1.2),
                  shape: const RoundedRectangleBorder(
                    borderRadius: BorderRadius.zero,
                  ),
                  foregroundColor: colors.primary,
                ),
                onPressed: () => Navigator.push(
                  context,
                  MaterialPageRoute(builder: (_) => const HostScreen()),
                ),
              ),
              const SizedBox(height: 20),
              OutlinedButton.icon(
                icon: const Icon(Icons.phone_android),
                label: const Text('JOIN GAME'),
                style: OutlinedButton.styleFrom(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                  textStyle: const TextStyle(fontSize: 18),
                  side: BorderSide(color: colors.primary, width: 1.2),
                  shape: const RoundedRectangleBorder(
                    borderRadius: BorderRadius.zero,
                  ),
                  foregroundColor: colors.primary,
                ),
                onPressed: () => Navigator.push(
                  context,
                  MaterialPageRoute(builder: (_) => const JoinGameScreen()),
                ),
              ),
              const SizedBox(height: 20),
              OutlinedButton.icon(
                icon: const Icon(Icons.menu_book),
                label: const Text('GAME INFO'),
                style: OutlinedButton.styleFrom(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                  textStyle: const TextStyle(fontSize: 18),
                  side: BorderSide(
                      color: colors.primary.withOpacity(0.7), width: 1.2),
                  shape: const RoundedRectangleBorder(
                    borderRadius: BorderRadius.zero,
                  ),
                  foregroundColor: colors.primary,
                ),
                onPressed: () => Navigator.push(
                  context,
                  MaterialPageRoute(builder: (_) => const GameInfoScreen()),
                ),
              ),
              const SizedBox(height: 20),
              OutlinedButton.icon(
                icon: const Icon(Icons.person_outline),
                label: const Text('PROFILE'),
                style: OutlinedButton.styleFrom(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                  textStyle: const TextStyle(fontSize: 18),
                  side: BorderSide(color: colors.primary, width: 1.2),
                  shape: const RoundedRectangleBorder(
                      borderRadius: BorderRadius.zero),
                  foregroundColor: colors.primary,
                ),
                onPressed: () => Navigator.push(
                  context,
                  MaterialPageRoute(builder: (_) => const ProfileScreen()),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
