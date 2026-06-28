import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:kinetic/src/providers/identity_provider.dart';
import 'package:kinetic/src/theme/app_theme.dart';


/// The Identity tab. Lets users look up any .kin name and see its public
/// identity info fetched from the Kinetic DHT.
class IdentityTab extends ConsumerStatefulWidget {
  const IdentityTab({super.key});

  @override
  ConsumerState<IdentityTab> createState() => _IdentityTabState();
}

class _IdentityTabState extends ConsumerState<IdentityTab> {
  final TextEditingController _controller = TextEditingController();

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

    return SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(24, 32, 24, 120), // Extra padding for floating nav
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Header
            Row(
              children: [
                Image.asset(
                  'assets/images/logo.png',
                  width: 48,
                  height: 48,
                ),
                const SizedBox(width: 16),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Identity Lookup',
                      style: GoogleFonts.outfit(
                        fontSize: 24,
                        fontWeight: FontWeight.w700,
                        color: AppTheme.textPrimary,
                      ),
                    ),
                    const Text(
                      'Verify any .kin name on-chain',
                      style: TextStyle(fontSize: 14, color: AppTheme.textSecondary),
                    ),
                  ],
                ),
              ],
            ),
            const SizedBox(height: 32),

            // Search field
            TextField(
              controller: _controller,
              textInputAction: TextInputAction.search,
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
                    : const Text('Lookup Identity'),
              ),
            ),
            const SizedBox(height: 32),

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
              _buildResultCard(identityState.data!, identityState.url ?? ''),
          ],
        ),
      ),
    );
  }

  Widget _buildResultCard(Map<String, dynamic> data, String query) {
    final name = data['name'] as String? ?? query;
    final formattedName = name.endsWith('.kin') ? name : '$name.kin';
    final peerId = data['peer_id'] as String? ?? 'Unknown';
    final status = data['status'] as String? ?? 'Unknown';
    final isActive = status == 'Verified';
    final statusNote = data['note'] as String? ?? status;

    return AnimatedContainer(
      duration: const Duration(milliseconds: 300),
      margin: const EdgeInsets.only(top: 8),
      decoration: BoxDecoration(
        color: AppTheme.surface.withOpacity(0.7),
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: AppTheme.border.withOpacity(0.5)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.02),
            blurRadius: 10,
            offset: const Offset(0, 4),
          )
        ],
      ),
      child: Column(
        children: [
          // Name header
          Container(
            padding: const EdgeInsets.all(24),
            decoration: BoxDecoration(
              color: isActive ? AppTheme.successLight.withOpacity(0.5) : AppTheme.surfaceVariant.withOpacity(0.5),
              borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
            ),
            child: Row(
              children: [
                Icon(
                  isActive ? Icons.verified_rounded : Icons.error_outline_rounded,
                  color: isActive ? AppTheme.success : AppTheme.error,
                  size: 32,
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        formattedName,
                        style: GoogleFonts.firaCode(
                          fontSize: 20,
                          fontWeight: FontWeight.w700,
                          color: AppTheme.textPrimary,
                        ),
                      ),
                      const SizedBox(height: 6),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                        decoration: BoxDecoration(
                          color: isActive ? AppTheme.success : AppTheme.error,
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Text(
                          isActive ? 'Active' : 'Inactive',
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
              ],
            ),
          ),

          // Profile Section
          if (data['profile'] != null && (data['profile'] as Map).isNotEmpty)
            _ProfileHeader(profile: data['profile'] as Map<String, dynamic>),
          
          if (data['profile'] != null && (data['profile'] as Map).isNotEmpty)
            const Divider(height: 1),

          // Details
          Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              children: [
                _DetailRow(
                  icon: Icons.fingerprint_rounded,
                  label: 'Owner Public Key',
                  value: data['owner_pubkey'] as String? ?? 'Unknown',
                  mono: true,
                ),
                const Divider(height: 32),
                _DetailRow(
                  icon: Icons.timer_rounded,
                  label: 'VDF Iterations (Difficulty)',
                  value: (data['vdf_iterations'] as int?)?.toString() ?? 'Unknown',
                  mono: true,
                ),
                const Divider(height: 32),
                _DetailRow(
                  icon: Icons.public_rounded,
                  label: 'Drand Pulse Round',
                  value: (data['drand_pulse'] as int?)?.toString() ?? 'Unknown',
                  mono: true,
                ),
                const Divider(height: 32),
                _DetailRow(
                  icon: Icons.hub_rounded,
                  label: 'Resolution Path',
                  value: data['resolution'] as String? ?? 'Unknown',
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _DetailRow extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;
  final bool mono;

  const _DetailRow({
    required this.icon,
    required this.label,
    required this.value,
    this.mono = false,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, size: 20, color: AppTheme.textSecondary),
        const SizedBox(width: 16),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                label,
                style: const TextStyle(fontSize: 13, color: AppTheme.textHint, fontWeight: FontWeight.w500),
              ),
              const SizedBox(height: 6),
              Text(
                value,
                style: mono
                    ? GoogleFonts.firaCode(fontSize: 14, color: AppTheme.textPrimary, fontWeight: FontWeight.w500)
                    : const TextStyle(fontSize: 15, color: AppTheme.textPrimary, fontWeight: FontWeight.w500),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _ProfileHeader extends StatelessWidget {
  final Map<String, dynamic> profile;

  const _ProfileHeader({required this.profile});

  @override
  Widget build(BuildContext context) {
    final avatar = profile['picture'] as String? ?? profile['avatar'] as String?;
    final banner = profile['banner'] as String?;
    final displayName = profile['name'] as String? ?? profile['display_name'] as String?;
    final about = profile['about'] as String? ?? profile['description'] as String?;
    final nip05 = profile['nip05'] as String?;
    final website = profile['website'] as String? ?? profile['url'] as String?;
    final github = profile['github'] as String?;
    final twitter = profile['twitter'] as String? ?? profile['x'] as String?;
    final lud16 = profile['lud16'] as String?;

    return Column(
      children: [
        if (banner != null)
          Container(
            height: 100,
            width: double.infinity,
            decoration: BoxDecoration(
              image: DecorationImage(
                image: NetworkImage(banner),
                fit: BoxFit.cover,
              ),
            ),
          ),
        Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            children: [
              if (avatar != null)
                CircleAvatar(
                  radius: 40,
                  backgroundImage: NetworkImage(avatar),
                  backgroundColor: AppTheme.surfaceVariant,
                ),
              if (avatar != null) const SizedBox(height: 16),
              if (displayName != null)
                Text(
                  displayName,
                  style: GoogleFonts.outfit(fontSize: 22, fontWeight: FontWeight.w700, color: AppTheme.textPrimary),
                  textAlign: TextAlign.center,
                ),
              if (nip05 != null)
                Padding(
                  padding: const EdgeInsets.only(top: 4),
                  child: Text(
                    nip05,
                    style: const TextStyle(fontSize: 14, color: AppTheme.success, fontWeight: FontWeight.w500),
                  ),
                ),
              if (about != null)
                Padding(
                  padding: const EdgeInsets.only(top: 12),
                  child: Text(
                    about,
                    style: const TextStyle(fontSize: 15, color: AppTheme.textSecondary),
                    textAlign: TextAlign.center,
                  ),
                ),
              if (website != null || github != null || twitter != null || lud16 != null)
                Padding(
                  padding: const EdgeInsets.only(top: 16),
                  child: Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    alignment: WrapAlignment.center,
                    children: [
                      if (website != null) _SocialChip(icon: Icons.language_rounded, label: 'Website', url: website),
                      if (github != null) _SocialChip(icon: Icons.code_rounded, label: 'GitHub', url: github),
                      if (twitter != null) _SocialChip(icon: Icons.chat_bubble_rounded, label: 'Twitter', url: twitter),
                      if (lud16 != null) _SocialChip(icon: Icons.bolt_rounded, label: 'Lightning', url: lud16),
                    ],
                  ),
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
  final String url;
  
  const _SocialChip({required this.icon, required this.label, required this.url});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: AppTheme.surfaceVariant.withOpacity(0.5),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: AppTheme.border.withOpacity(0.5)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 16, color: AppTheme.textSecondary),
          const SizedBox(width: 6),
          Text(label, style: const TextStyle(fontSize: 13, color: AppTheme.textSecondary, fontWeight: FontWeight.w500)),
        ],
      ),
    );
  }
}
