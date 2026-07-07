import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:kinetic/src/providers/daemon_provider.dart';
import 'package:kinetic/src/theme/app_theme.dart';

class TetheredModeScreen extends ConsumerStatefulWidget {
  const TetheredModeScreen({super.key});

  @override
  ConsumerState<TetheredModeScreen> createState() => _TetheredModeScreenState();
}

class _TetheredModeScreenState extends ConsumerState<TetheredModeScreen> {
  final _npubController = TextEditingController();

  @override
  void dispose() {
    _npubController.dispose();
    super.dispose();
  }

  void _onTether() {
    final npub = _npubController.text.trim();
    if (npub.isEmpty) return;
    ref.read(daemonProvider.notifier).startDaemon(overrideNpub: npub);
  }

  void _onSkip() {
    ref.read(daemonProvider.notifier).startDaemon(bypassRootCheck: true);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.background,
      body: SafeArea(
        child: SingleChildScrollView(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 24.0, vertical: 48.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // Icon Section
                Container(
                  height: 120,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: AppTheme.surface,
                    boxShadow: [
                      BoxShadow(
                        color: AppTheme.error.withValues(alpha: 0.1),
                        blurRadius: 40,
                        spreadRadius: 10,
                      ),
                      BoxShadow(
                        color: AppTheme.primary.withValues(alpha: 0.1),
                        blurRadius: 40,
                        spreadRadius: 10,
                      ),
                    ],
                  ),
                  child: const Center(
                    child: Icon(
                      Icons.gpp_bad_rounded,
                      size: 70,
                      color: AppTheme.error,
                    ),
                  ),
                ),
                const SizedBox(height: 32),

                // Text Section
                const Text(
                  'SYSTEM INTEGRITY COMPROMISED',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: AppTheme.error,
                    fontSize: 12,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 1.5,
                  ),
                ),
                const SizedBox(height: 8),
                const Text(
                  'Root Access Detected',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: AppTheme.textPrimary,
                    fontSize: 28,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 16),
                
                // Explanation Card
                Container(
                  padding: const EdgeInsets.all(20),
                  decoration: BoxDecoration(
                    color: AppTheme.error.withValues(alpha: 0.05),
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(
                      color: AppTheme.error.withValues(alpha: 0.1),
                    ),
                  ),
                  child: const Text(
                    'Security Alert: All active mining processes have been DISABLED for your protection. You can still access and browse the network by tethering to your secure Desktop Node.',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: AppTheme.textSecondary,
                      fontSize: 14,
                      height: 1.5,
                    ),
                  ),
                ),
                const SizedBox(height: 48),

                // Input Section
                const Text(
                  'Enter Nostr npub to tether',
                  style: TextStyle(
                    color: AppTheme.textSecondary,
                    fontSize: 14,
                    fontWeight: FontWeight.w500,
                  ),
                ),
                const SizedBox(height: 8),
                TextField(
                  controller: _npubController,
                  style: const TextStyle(color: AppTheme.textPrimary),
                  decoration: InputDecoration(
                    hintText: 'npub1...',
                    hintStyle: const TextStyle(color: AppTheme.textHint),
                    filled: true,
                    fillColor: AppTheme.surface,
                    contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(16),
                      borderSide: const BorderSide(color: AppTheme.border),
                    ),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(16),
                      borderSide: const BorderSide(color: AppTheme.border),
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(16),
                      borderSide: const BorderSide(color: AppTheme.primary, width: 2),
                    ),
                  ),
                ),
                const SizedBox(height: 24),

                // Action Buttons
                ElevatedButton(
                  onPressed: _onTether,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppTheme.primary,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(16),
                    ),
                    elevation: 0,
                  ),
                  child: const Text(
                    'Tether to Node',
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                
                TextButton(
                  onPressed: _onSkip,
                  child: const Text(
                    'Skip for now',
                    style: TextStyle(
                      color: AppTheme.textHint,
                      fontSize: 16,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
