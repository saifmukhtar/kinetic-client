import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:kinetic/src/theme/app_theme.dart';
import 'package:kinetic/src/providers/registration_provider.dart';

class RegistrationSheet extends ConsumerStatefulWidget {
  final String name;

  const RegistrationSheet({super.key, required this.name});

  @override
  ConsumerState<RegistrationSheet> createState() => _RegistrationSheetState();
}

class _RegistrationSheetState extends ConsumerState<RegistrationSheet> {
  final TextEditingController _urlController = TextEditingController(text: '');

  @override
  void dispose() {
    _urlController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final regState = ref.watch(registrationProvider);
    final isIdle = regState.status == RegistrationStatus.idle;
    final isError = regState.status == RegistrationStatus.error;
    final isSuccess = regState.status == RegistrationStatus.success;

    return Container(
      padding: EdgeInsets.only(
        bottom: MediaQuery.of(context).viewInsets.bottom + 24,
        left: 24,
        right: 24,
        top: 24,
      ),
      decoration: const BoxDecoration(
        color: AppTheme.surface,
        borderRadius: BorderRadius.vertical(top: Radius.circular(32)),
      ),
      child: SingleChildScrollView(
        child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Register Name',
            style: GoogleFonts.outfit(
              fontSize: 24,
              fontWeight: FontWeight.w700,
              color: AppTheme.textPrimary,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'Claim \${widget.name} on the Kinetic DHT.',
            style: const TextStyle(color: AppTheme.textSecondary),
          ),
          const SizedBox(height: 24),
          
          if (isIdle || isError) ...[
            TextField(
              controller: _urlController,
              keyboardType: TextInputType.url,
              autocorrect: false,
              enableSuggestions: false,
              textCapitalization: TextCapitalization.none,
              decoration: InputDecoration(
                labelText: 'Desktop Node (npub or local URL)',
                hintText: 'npub1... or http://10.0.2.2:8080',
                labelStyle: const TextStyle(color: AppTheme.textHint),
                enabledBorder: OutlineInputBorder(
                  borderSide: BorderSide(color: AppTheme.border.withValues(alpha: 0.5)),
                  borderRadius: BorderRadius.circular(16),
                ),
                focusedBorder: OutlineInputBorder(
                  borderSide: const BorderSide(color: AppTheme.primary),
                  borderRadius: BorderRadius.circular(16),
                ),
              ),
              onChanged: (val) => ref.read(registrationProvider.notifier).setDesktopUrl(val),
            ),
            const SizedBox(height: 16),

            SizedBox(
              width: double.infinity,
              height: 56,
              child: ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppTheme.primary,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                ),
                onPressed: () {
                  ref.read(registrationProvider.notifier).startRegistration(widget.name);
                },
                child: const Text('Start Cryptographic Registration', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
              ),
            ),
          ] else if (isSuccess) ...[
            const Center(
              child: Icon(Icons.check_circle_outline_rounded, color: AppTheme.success, size: 64),
            ),
            const SizedBox(height: 16),
            const Center(
              child: Text(
                'Registration Successful!',
                style: TextStyle(color: AppTheme.success, fontSize: 20, fontWeight: FontWeight.bold),
              ),
            ),
            const SizedBox(height: 16),
            SizedBox(
              width: double.infinity,
              height: 56,
              child: ElevatedButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('Done'),
              ),
            ),
          ] else ...[
            _buildProgressItem(
              title: 'Hardware Attestation',
              isActive: regState.status == RegistrationStatus.attesting || (isError && regState.failedStep == RegistrationStatus.attesting),
              isDone: regState.status.index > RegistrationStatus.attesting.index && !(isError && regState.failedStep == RegistrationStatus.attesting),
              isError: isError && regState.failedStep == RegistrationStatus.attesting,
              errorText: (isError && regState.failedStep == RegistrationStatus.attesting) ? regState.error?.message : null,
            ),
            _buildProgressItem(
              title: 'Requesting VDF Proof',
              isActive: regState.status == RegistrationStatus.requestingVdf || (isError && regState.failedStep == RegistrationStatus.requestingVdf),
              isDone: regState.status.index > RegistrationStatus.requestingVdf.index && !(isError && regState.failedStep == RegistrationStatus.requestingVdf),
              isError: isError && regState.failedStep == RegistrationStatus.requestingVdf,
              errorText: (isError && regState.failedStep == RegistrationStatus.requestingVdf) ? regState.error?.message : null,
            ),
            _buildProgressItem(
              title: 'Desktop Computing VDF... (takes a few minutes)',
              isActive: regState.status == RegistrationStatus.pollingVdf || (isError && regState.failedStep == RegistrationStatus.pollingVdf),
              isDone: regState.status.index > RegistrationStatus.pollingVdf.index && !(isError && regState.failedStep == RegistrationStatus.pollingVdf),
              isError: isError && regState.failedStep == RegistrationStatus.pollingVdf,
              errorText: (isError && regState.failedStep == RegistrationStatus.pollingVdf) ? regState.error?.message : null,
            ),
            _buildProgressItem(
              title: 'Broadcasting Reveal to DHT',
              isActive: regState.status == RegistrationStatus.broadcasting || (isError && regState.failedStep == RegistrationStatus.broadcasting),
              isDone: regState.status.index > RegistrationStatus.broadcasting.index && !(isError && regState.failedStep == RegistrationStatus.broadcasting),
              isError: isError && regState.failedStep == RegistrationStatus.broadcasting,
              errorText: (isError && regState.failedStep == RegistrationStatus.broadcasting) ? regState.error?.message : null,
            ),
          ],
        ],
      ),
      ),
    );
  }

  Widget _buildProgressItem({
    required String title,
    required bool isActive,
    required bool isDone,
    bool isError = false,
    String? errorText,
  }) {
    Color color = AppTheme.textHint;
    if (isDone) {
      color = AppTheme.success;
    }
    if (isError) {
      color = AppTheme.error;
    } else if (isActive) {
      color = AppTheme.primary;
    }

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8.0),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (isError)
            const Icon(Icons.error_outline_rounded, color: AppTheme.error, size: 24)
          else if (isDone)
            const Icon(Icons.check_circle_rounded, color: AppTheme.success, size: 24)
          else if (isActive)
            const SizedBox(
              width: 24,
              height: 24,
              child: CircularProgressIndicator(strokeWidth: 2.5),
            )
          else
            const Icon(Icons.radio_button_unchecked, color: AppTheme.textHint, size: 24),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: TextStyle(
                    color: color,
                    fontWeight: isActive || isError ? FontWeight.bold : FontWeight.normal,
                  ),
                ),
                if (errorText != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 4.0),
                    child: Text(
                      errorText,
                      style: const TextStyle(color: AppTheme.error, fontSize: 13),
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
