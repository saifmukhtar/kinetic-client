import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:kinetic/src/providers/identity_provider.dart';
import 'package:kinetic/src/theme/app_theme.dart';
import 'package:kinetic/src/widgets/registration_sheet.dart';

class RegisterDomainSheet extends ConsumerStatefulWidget {
  final VoidCallback onRegistered;

  const RegisterDomainSheet({
    super.key,
    required this.onRegistered,
  });

  @override
  ConsumerState<RegisterDomainSheet> createState() => _RegisterDomainSheetState();
}

class _RegisterDomainSheetState extends ConsumerState<RegisterDomainSheet> {
  final TextEditingController _controller = TextEditingController();

  @override
  void initState() {
    super.initState();
    Future.microtask(() {
      if (mounted) ref.read(identityProvider.notifier).clear();
    });
  }

  void _checkAvailability() {
    final input = _controller.text.trim();
    if (input.isEmpty) return;
    
    // Remove .kin if present
    final name = input.endsWith('.kin') ? input.substring(0, input.length - 4) : input;
    
    if (name.length < 8) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Domain name must be at least 8 characters long.')),
      );
      return;
    }
    
    FocusScope.of(context).unfocus();
    ref.read(identityProvider.notifier).resolveDomain(name);
  }

  void _proceedToRegistration(String name) {
    Navigator.pop(context); // Close the search sheet
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => RegistrationSheet(
        name: name,
        // Wait, RegistrationSheet doesn't have an onRegistered callback out of the box,
        // but we'll reload the parent when they pull down the ManageKinTab.
      ),
    ).then((_) {
      widget.onRegistered();
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final identityState = ref.watch(identityProvider);
    final bottomInset = MediaQuery.of(context).viewInsets.bottom;

    final input = _controller.text.trim();
    final name = input.endsWith('.kin') ? input.substring(0, input.length - 4) : input;

    // It's available if there's an error (not found) or explicitly inactive
    final isAvailable = identityState.error != null || 
        (identityState.data != null && identityState.data!['status'] != 'Verified');
        
    final isTaken = identityState.data != null && identityState.data!['status'] == 'Verified' && identityState.error == null;

    return Padding(
      padding: EdgeInsets.only(bottom: bottomInset),
      child: Container(
        padding: const EdgeInsets.all(24),
        decoration: const BoxDecoration(
          color: AppTheme.background,
          borderRadius: BorderRadius.vertical(top: Radius.circular(32)),
        ),
        constraints: BoxConstraints(maxHeight: MediaQuery.of(context).size.height * 0.85),
      child: SingleChildScrollView(
        child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Center(
            child: Container(
              width: 40,
              height: 4,
              margin: const EdgeInsets.only(bottom: 24),
              decoration: BoxDecoration(
                color: AppTheme.border,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'Register Domain',
                style: GoogleFonts.outfit(
                  fontSize: 24,
                  fontWeight: FontWeight.w700,
                  color: AppTheme.textPrimary,
                ),
              ),
              IconButton(
                icon: const Icon(Icons.close_rounded, color: AppTheme.textSecondary),
                onPressed: () => Navigator.pop(context),
              ),
            ],
          ),
          const SizedBox(height: 16),
          
          Text(
            'Check if your desired .kin domain is available.',
            style: const TextStyle(fontSize: 14, color: AppTheme.textSecondary),
          ),
          const SizedBox(height: 16),

          // Search field
          TextField(
            controller: _controller,
            textInputAction: TextInputAction.search,
            keyboardType: TextInputType.url,
            autocorrect: false,
            enableSuggestions: false,
            textCapitalization: TextCapitalization.none,
            onSubmitted: (_) => _checkAvailability(),
            onChanged: (_) {
              setState(() {});
              if (identityState.data != null || identityState.error != null) {
                ref.read(identityProvider.notifier).clear();
              }
            },
            style: GoogleFonts.firaCode(fontSize: 16, color: AppTheme.textPrimary),
            decoration: InputDecoration(
              prefixIcon: const Icon(Icons.language_rounded, color: AppTheme.textHint, size: 20),
              suffixText: '.kin',
              suffixStyle: GoogleFonts.firaCode(fontSize: 16, color: AppTheme.textHint),
              hintText: 'myname',
              hintStyle: GoogleFonts.firaCode(fontSize: 16, color: AppTheme.textHint),
            ),
          ),
          const SizedBox(height: 16),

          // Check button
          SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              onPressed: identityState.isResolving || input.isEmpty ? null : _checkAvailability,
              child: identityState.isResolving
                  ? const SizedBox(
                      height: 24,
                      width: 24,
                      child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2.5),
                    )
                  : const Text('Check Availability'),
            ),
          ),
          const SizedBox(height: 24),
          
          if (isTaken)
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: AppTheme.error.withOpacity(0.08),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: AppTheme.error.withOpacity(0.2)),
              ),
              child: Row(
                children: [
                  const Icon(Icons.cancel_rounded, color: AppTheme.error),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      '$name.kin is already registered',
                      style: const TextStyle(color: AppTheme.error, fontWeight: FontWeight.w600),
                    ),
                  ),
                ],
              ),
            ),

          if (isAvailable && name.length >= 8)
            Container(
              padding: const EdgeInsets.all(24),
              decoration: BoxDecoration(
                color: AppTheme.successLight.withOpacity(0.1),
                borderRadius: BorderRadius.circular(24),
                border: Border.all(color: AppTheme.success.withOpacity(0.3)),
              ),
              child: Column(
                children: [
                  Row(
                    children: [
                      const Icon(Icons.check_circle_rounded, color: AppTheme.success),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          '$name.kin is available!',
                          style: GoogleFonts.outfit(
                            fontSize: 18,
                            fontWeight: FontWeight.w600,
                            color: AppTheme.success,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 24),
                  SizedBox(
                    width: double.infinity,
                    child: OutlinedButton.icon(
                      icon: const Icon(Icons.add_circle_outline_rounded),
                      label: Text('Register $name.kin'),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: AppTheme.primary,
                        side: const BorderSide(color: AppTheme.primary, width: 2),
                        padding: const EdgeInsets.symmetric(vertical: 16),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                      ),
                      onPressed: () => _proceedToRegistration(name),
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
      ),
      ),
    );
  }
}
