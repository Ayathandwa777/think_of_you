import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:vibration/vibration.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'firebase_options.dart';
import 'dart:async';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);

  final prefs = await SharedPreferences.getInstance();
  final savedIdentity = prefs.getString('identity');

  runApp(MyApp(savedIdentity: savedIdentity));
}

class MyApp extends StatelessWidget {
  final String? savedIdentity;

  const MyApp({super.key, required this.savedIdentity});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Between Us',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFF7c3aed)),
        useMaterial3: true,
      ),
      home: savedIdentity == null
          ? const IdentityPage()
          : ThinkOfYouPage(identity: savedIdentity!),
    );
  }
}

class IdentityPage extends StatelessWidget {
  const IdentityPage({super.key});

  Future<void> _selectIdentity(BuildContext context, String identity) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('identity', identity);

    if (context.mounted) {
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(builder: (_) => ThinkOfYouPage(identity: identity)),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0f0a1e),
      body: SafeArea(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Spacer(),
            const Text('💜', style: TextStyle(fontSize: 80)),
            const SizedBox(height: 24),
            const Text(
              'who are you?',
              style: TextStyle(
                color: Colors.white,
                fontSize: 28,
                fontWeight: FontWeight.bold,
                letterSpacing: 2,
              ),
            ),
            const SizedBox(height: 8),
            const Text(
              'choose your identity',
              style: TextStyle(
                color: Colors.white38,
                fontSize: 14,
                letterSpacing: 1,
              ),
            ),
            const Spacer(),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 32),
              child: Column(
                children: [
                  _IdentityButton(
                    label: 'Aya',
                    onTap: () => _selectIdentity(context, 'aya'),
                  ),
                  const SizedBox(height: 16),
                  _IdentityButton(
                    label: 'Nosihle',
                    onTap: () => _selectIdentity(context, 'nosihle'),
                  ),
                ],
              ),
            ),
            const Spacer(),
          ],
        ),
      ),
    );
  }
}

class _IdentityButton extends StatelessWidget {
  final String label;
  final VoidCallback onTap;

  const _IdentityButton({required this.label, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(vertical: 20),
        decoration: BoxDecoration(
          gradient: const LinearGradient(
            colors: [Color(0xFF7c3aed), Color(0xFF5b21b6)],
          ),
          borderRadius: BorderRadius.circular(16),
        ),
        child: Text(
          label,
          textAlign: TextAlign.center,
          style: const TextStyle(
            color: Colors.white,
            fontSize: 20,
            fontWeight: FontWeight.bold,
            letterSpacing: 2,
          ),
        ),
      ),
    );
  }
}

class ThinkOfYouPage extends StatefulWidget {
  final String identity;
  const ThinkOfYouPage({super.key, required this.identity});

  @override
  State<ThinkOfYouPage> createState() => _ThinkOfYouPageState();
}

class _ThinkOfYouPageState extends State<ThinkOfYouPage>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _scaleAnimation;

  int tapCount = 0;
  String lastPing = 'Never';
  String lastPingType = 'thinking';

  bool isCoolingDown = false;
  int _secondsRemaining = 0;
  Timer? _cooldownTimer;

  bool isSynced = false;

  String get myIdentity => widget.identity;
  String get theirIdentity => widget.identity == 'aya' ? 'nosihle' : 'aya';
  String get theirName => widget.identity == 'aya' ? 'Nosihle' : 'Aya';

  @override
  void initState() {
    super.initState();

    _controller = AnimationController(
      duration: const Duration(milliseconds: 300),
      vsync: this,
    );

    _scaleAnimation = Tween<double>(
      begin: 1.0,
      end: 0.85,
    ).animate(CurvedAnimation(parent: _controller, curve: Curves.easeInOut));

    _listenForPings();
    _loadTapCount();
    _checkCooldown();
  }

  void _checkCooldown() async {
    final doc = await FirebaseFirestore.instance
        .collection('pings')
        .doc('cooldown_$myIdentity')
        .get();

    if (doc.exists) {
      final lastTap = (doc.data()?['lastTap'] as Timestamp?)?.toDate();
      if (lastTap != null) {
        final diff = DateTime.now().difference(lastTap).inSeconds;
        if (diff < 300) {
          _startCooldown(300 - diff);
        }
      }
    }
  }

  void _startCooldown(int seconds) {
    setState(() {
      isCoolingDown = true;
      _secondsRemaining = seconds;
    });

    _cooldownTimer?.cancel();

    _cooldownTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      setState(() {
        _secondsRemaining--;
      });

      if (_secondsRemaining <= 0) {
        timer.cancel();
        setState(() => isCoolingDown = false);
      }
    });
  }

  void _loadTapCount() async {
    final doc = await FirebaseFirestore.instance
        .collection('pings')
        .doc('stats_$myIdentity')
        .get();

    final today = DateTime.now().toIso8601String().substring(0, 10);

    if (doc.exists) {
      final data = doc.data();
      final storedDate = data?['date'] ?? '';

      if (storedDate == today) {
        setState(() => tapCount = data?['count'] ?? 0);
      } else {
        setState(() => tapCount = 0);
        await doc.reference.set({'count': 0, 'date': today});
      }
    }
  }

  void _listenForPings() {
    FirebaseFirestore.instance
        .collection('pings')
        .doc('latest')
        .snapshots()
        .listen((snapshot) {
          if (snapshot.exists) {
            final data = snapshot.data();
            if (data != null && data['from'] == theirIdentity) {
              _onReceivePing(data['type'] ?? 'thinking');
            }
          }
        });

    FirebaseMessaging.onMessage.listen((message) {
      _onReceivePing('thinking');
    });
  }

  void _onReceivePing(String type) async {
    if (await Vibration.hasVibrator() ?? false) {
      if (type == 'missing') {
        Vibration.vibrate(pattern: [0, 500, 200, 500, 200, 500]);
      } else {
        Vibration.vibrate(pattern: [0, 400, 200, 400]);
      }
    }

    setState(() {
      lastPing = _formatTime(DateTime.now());
      lastPingType = type;
    });
  }

  String _formatTime(DateTime time) {
    final hour = time.hour > 12 ? time.hour - 12 : time.hour;
    final minute = time.minute.toString().padLeft(2, '0');
    final period = time.hour >= 12 ? 'PM' : 'AM';
    return '$hour:$minute $period';
  }

  void _sendPing(String type) async {
    if (isCoolingDown) return;

    _controller.forward().then((_) => _controller.reverse());

    if (await Vibration.hasVibrator() ?? false) {
      Vibration.vibrate(duration: 200);
    }

    final newCount = tapCount + 1;
    final today = DateTime.now().toIso8601String().substring(0, 10);
    final now = DateTime.now();

    setState(() => tapCount = newCount);

    final theirDoc = await FirebaseFirestore.instance
        .collection('pings')
        .doc('tap_$theirIdentity')
        .get();

    if (theirDoc.exists) {
      final theirTap = (theirDoc.data()?['timestamp'] as Timestamp?)?.toDate();

      if (theirTap != null && now.difference(theirTap).inSeconds.abs() <= 10) {
        _triggerSyncMoment();
      }
    }

    await FirebaseFirestore.instance
        .collection('pings')
        .doc('tap_$myIdentity')
        .set({'timestamp': FieldValue.serverTimestamp()});

    await FirebaseFirestore.instance.collection('pings').doc('latest').set({
      'from': myIdentity,
      'type': type,
      'timestamp': FieldValue.serverTimestamp(),
    });

    await FirebaseFirestore.instance
        .collection('pings')
        .doc('stats_$myIdentity')
        .set({'count': newCount, 'date': today});

    await FirebaseFirestore.instance
        .collection('pings')
        .doc('cooldown_$myIdentity')
        .set({'lastTap': FieldValue.serverTimestamp()});

    _startCooldown(300);
  }

  void _triggerSyncMoment() {
    setState(() => isSynced = true);

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => const SyncDialog(),
    );

    Future.delayed(const Duration(seconds: 4), () {
      if (mounted) {
        Navigator.pop(context);
        setState(() => isSynced = false);
      }
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    _cooldownTimer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0f0a1e),
      body: SafeArea(
        child: Column(
          children: [
            const SizedBox(height: 40),
            const Text(
              'Between Us',
              style: TextStyle(
                color: Color(0xFFc084fc),
                fontSize: 16,
                letterSpacing: 4,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              '$theirName 💜',
              style: const TextStyle(
                color: Colors.white,
                fontSize: 32,
                fontWeight: FontWeight.bold,
              ),
            ),
            const Spacer(),
            ScaleTransition(
              scale: _scaleAnimation,
              child: GestureDetector(
                onTap: isCoolingDown ? null : () => _sendPing('thinking'),
                onLongPress: isCoolingDown ? null : () => _sendPing('missing'),
                child: Container(
                  width: 220,
                  height: 220,
                  decoration: const BoxDecoration(
                    shape: BoxShape.circle,
                    gradient: RadialGradient(
                      colors: [Color(0xFF9f60f7), Color(0xFF5b21b6)],
                    ),
                  ),
                  child: const Center(
                    child: Text('💜', style: TextStyle(fontSize: 60)),
                  ),
                ),
              ),
            ),
            const Spacer(),
            Text(
              lastPingType == 'missing'
                  ? '$theirName misses you'
                  : '$theirName thought of you',
              style: const TextStyle(color: Colors.white54),
            ),
            const SizedBox(height: 48),
          ],
        ),
      ),
    );
  }
}

class SyncDialog extends StatelessWidget {
  const SyncDialog({super.key});

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: Colors.transparent,
      child: Container(
        padding: const EdgeInsets.all(40),
        decoration: BoxDecoration(
          color: const Color(0xFF0f0a1e),
          borderRadius: BorderRadius.circular(24),
        ),
        child: const Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text('💜', style: TextStyle(fontSize: 60)),
            SizedBox(height: 16),
            Text(
              'same moment',
              style: TextStyle(color: Color(0xFFc084fc), letterSpacing: 4),
            ),
            SizedBox(height: 8),
            Text(
              'you both thought\nof each other',
              textAlign: TextAlign.center,
              style: TextStyle(color: Colors.white, fontSize: 22),
            ),
          ],
        ),
      ),
    );
  }
}
