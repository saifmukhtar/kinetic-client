import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:kinetic/src/providers/identity_provider.dart';
import 'package:kinetic/src/theme/app_theme.dart';

class IdentityLookupSheet extends ConsumerStatefulWidget {
  const IdentityLookupSheet({super.key});

  @override
  ConsumerState<IdentityLookupSheet> createState() => _IdentityLookupSheetState();
}

class _IdentityLookupSheetState extends ConsumerState<IdentityLookupSheet> {
  final TextEditingController _controller = TextEditingController();

  @override
  void initState() {
    super.initState();
    Future.microtask(() {
      if (mounted) ref.read(identityProvider.notifier).clear();
    });
  }

  void _lookup() {
    final input = _controller.text.trim();
    if (input.isEmpty) {
      ref.read(identityProvider.notifier).clear();
      return;
    }
    FocusScope.of(context).unfocus();
    ref.read(identityProvider.notifier).resolveDomain(input);
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

    return Padding(
      padding: EdgeInsets.only(bottom: bottomInset),
      child: Container(
        padding: const EdgeInsets.all(24),
        decoration: const BoxDecoration(
          color: AppTheme.background,
          borderRadius: BorderRadius.vertical(top: Radius.circular(32)),
        ),
        constraints: BoxConstraints(maxHeight: MediaQuery.of(context).size.height * 0.85),
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
                'Lookup Identity',
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
          // Search field
          TextField(
            controller: _controller,
            textInputAction: TextInputAction.search,
            keyboardType: TextInputType.url,
            autocorrect: false,
            enableSuggestions: false,
            textCapitalization: TextCapitalization.none,
            onSubmitted: (_) => _lookup(),
            style: GoogleFonts.firaCode(fontSize: 16, color: AppTheme.textPrimary),
            decoration: InputDecoration(
              prefixIcon: const Icon(Icons.search_rounded, color: AppTheme.textHint, size: 20),
              hintText: 'example.kin',
              hintStyle: GoogleFonts.firaCode(fontSize: 16, color: AppTheme.textHint),
            ),
          ),
          const SizedBox(height: 16),

          // Lookup button
          SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              onPressed: identityState.isResolving ? null : _lookup,
              child: identityState.isResolving
                  ? const SizedBox(
                      height: 24,
                      width: 24,
                      child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2.5),
                    )
                  : const Text('Lookup'),
            ),
          ),
          const SizedBox(height: 24),

          Expanded(
            child: SingleChildScrollView(
              child: Column(
                children: [
                  // Error
                  if (identityState.error != null)
                    Container(
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: AppTheme.error.withOpacity(0.08),
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(color: AppTheme.error.withOpacity(0.2)),
                      ),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Icon(Icons.error_outline_rounded, color: AppTheme.error, size: 22),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Text(
                              identityState.error!.replaceFirst('Exception: ', ''),
                              style: const TextStyle(fontSize: 14, color: AppTheme.error),
                            ),
                          ),
                        ],
                      ),
                    ),

                  // Result card
                  if (identityState.data != null && !identityState.isResolving)
                    _buildResultCard(context, identityState.data!, identityState.url ?? ''),
                ],
              ),
            ),
          ),
        ],
      ),
      ),
    );
  }

  Widget _buildResultCard(BuildContext context, Map<String, dynamic> data, String query) {
    final isDirectNpub = query.startsWith('npub1');
    final name = data['name'] as String? ?? query;
    final formattedName = isDirectNpub ? name : (name.endsWith('.kin') ? name : '$name.kin');
    final status = data['status'] as String? ?? 'Unknown';
    final isActive = status == 'Verified';

    final hasProfile = data['profile'] != null && (data['profile'] as Map).isNotEmpty;

    return AnimatedContainer(
      duration: const Duration(milliseconds: 300),
      margin: const EdgeInsets.only(top: 8),
      decoration: BoxDecoration(
        color: AppTheme.surface.withOpacity(0.7),
        borderRadius: BorderRadius.circular(32),
        border: Border.all(color: AppTheme.border.withOpacity(0.5)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.04),
            blurRadius: 16,
            offset: const Offset(0, 8),
          )
        ],
      ),
      child: Column(
        children: [
          // Name header
          Container(
            padding: const EdgeInsets.all(24),
            decoration: BoxDecoration(
              color: isActive ? AppTheme.successLight.withOpacity(0.2) : AppTheme.surfaceVariant.withOpacity(0.2),
              borderRadius: const BorderRadius.vertical(top: Radius.circular(32)),
            ),
            child: Row(
              children: [
                Icon(
                  isActive ? Icons.verified_rounded : Icons.error_outline_rounded,
                  color: isActive ? AppTheme.success : AppTheme.error,
                  size: 28,
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Text(
                    formattedName,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: GoogleFonts.outfit(
                      fontSize: 22,
                      fontWeight: FontWeight.w700,
                      color: AppTheme.textPrimary,
                    ),
                  ),
                ),
                if (!isDirectNpub)
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                    decoration: BoxDecoration(
                      color: isActive ? AppTheme.success : AppTheme.error,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text(
                      isActive ? 'Kinetic DHT' : 'Inactive',
                      style: const TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                        color: Colors.white,
                      ),
                    ),
                  ),
              ],
            ),
          ),

          // Profile Section
          if (hasProfile)
            _ProfileHeader(profile: data['profile'] as Map<String, dynamic>),
            
          if (!hasProfile)
            Padding(
              padding: const EdgeInsets.all(48.0),
              child: Column(
                children: [
                  Icon(Icons.person_off_rounded, size: 48, color: AppTheme.textHint.withOpacity(0.5)),
                  const SizedBox(height: 16),
                  const Text('No Nostr Identity Linked', style: TextStyle(color: AppTheme.textHint)),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

class _ProfileHeader extends StatelessWidget {
  final Map<String, dynamic> profile;

  const _ProfileHeader({required this.profile});

  @override
  Widget build(BuildContext context) {
    final displayName = (profile['name'] is String ? profile['name'] : null) ?? (profile['display_name'] is String ? profile['display_name'] : null);
    final nip05 = profile['nip05'] is String ? profile['nip05'] as String : null;
    final website = (profile['website'] is String ? profile['website'] : null) ?? (profile['url'] is String ? profile['url'] : null);
    final github = profile['github'] is String ? profile['github'] as String : null;
    final twitter = (profile['twitter'] is String ? profile['twitter'] : null) ?? (profile['x'] is String ? profile['x'] : null);
    final lud16 = profile['lud16'] is String ? profile['lud16'] as String : null;

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            children: [
              Container(
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  border: Border.all(color: AppTheme.primary.withOpacity(0.2), width: 4),
                  boxShadow: [
                    BoxShadow(
                      color: AppTheme.primary.withOpacity(0.1),
                      blurRadius: 24,
                      offset: const Offset(0, 8),
                    )
                  ],
                ),
                child: CircleAvatar(
                  radius: 56,
                  backgroundColor: AppTheme.surfaceVariant,
                  child: Icon(Icons.person_rounded, size: 56, color: AppTheme.textHint),
                ),
              ),
              const SizedBox(height: 24),
              
              if (displayName != null && displayName.isNotEmpty)
                Text(
                  displayName,
                  style: GoogleFonts.outfit(
                    fontSize: 28, 
                    fontWeight: FontWeight.w800, 
                    color: AppTheme.textPrimary,
                    letterSpacing: -0.5,
                  ),
                  textAlign: TextAlign.center,
                ),
                
              if (nip05 != null && nip05.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                    decoration: BoxDecoration(
                      color: AppTheme.successLight.withOpacity(0.2),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(Icons.verified_rounded, size: 16, color: AppTheme.success),
                        const SizedBox(width: 6),
                        Text(
                          nip05,
                          style: const TextStyle(fontSize: 14, color: AppTheme.success, fontWeight: FontWeight.w600),
                        ),
                      ],
                    ),
                  ),
                ),
                
              const SizedBox(height: 32),
              
              Wrap(
                spacing: 12,
                runSpacing: 12,
                alignment: WrapAlignment.center,
                children: [
                  if (website != null && website.isNotEmpty) _SocialChip(icon: Icons.language_rounded, label: 'Website'),
                  if (github != null && github.isNotEmpty) _SocialChip(icon: Icons.code_rounded, label: 'GitHub'),
                  if (twitter != null && twitter.isNotEmpty) _SocialChip(icon: Icons.alternate_email_rounded, label: 'Twitter'),
                  if (lud16 != null && lud16.isNotEmpty) _SocialChip(icon: Icons.bolt_rounded, label: 'Lightning'),
                ],
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _SocialChip extends StatelessWidget {
  final IconData icon;
  final String label;
  
  const _SocialChip({required this.icon, required this.label});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: AppTheme.surfaceVariant.withOpacity(0.5),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppTheme.border.withOpacity(0.5)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 18, color: AppTheme.textPrimary),
          const SizedBox(width: 8),
          Text(label, style: const TextStyle(fontSize: 14, color: AppTheme.textPrimary, fontWeight: FontWeight.w600)),
        ],
      ),
    );
  }
}
