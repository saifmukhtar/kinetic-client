import 'package:flutter/material.dart';
import 'package:kinetic/src/constants.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:kinetic/src/theme/app_theme.dart';
import 'package:kinetic/src/screens/manage/identity_lookup_sheet.dart';
import 'package:kinetic/src/screens/manage/register_domain_sheet.dart';
import 'package:kinetic/src/rust/api/daemon.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'dart:async';

class ManageKinTab extends StatefulWidget {
  const ManageKinTab({super.key});

  @override
  State<ManageKinTab> createState() => _ManageKinTabState();
}

class _ManageKinTabState extends State<ManageKinTab> {
  List<String> _ownedDomains = [];
  bool _isLoading = true;
  bool _isConnected = false;
  late StreamSubscription<List<ConnectivityResult>> _connectivitySubscription;
  Timer? _p2pPingTimer;

  @override
  void initState() {
    super.initState();
    _loadDomains();
    _initConnectivity();
    _connectivitySubscription = Connectivity().onConnectivityChanged.listen((List<ConnectivityResult> results) {
      if (results.contains(ConnectivityResult.none)) {
        setState(() => _isConnected = false);
      } else {
        _verifyP2PConnection();
      }
    });

    // Periodically verify actual P2P connection
    _p2pPingTimer = Timer.periodic(const Duration(seconds: 30), (_) {
      if (!mounted) return;
      _verifyP2PConnection();
    });
  }

  Future<void> _verifyP2PConnection() async {
    try {
      // Actually ping the Kinetic P2P daemon
      await fetchLatestDrand();
      if (mounted) {
        setState(() => _isConnected = true);
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isConnected = false);
      }
    }
  }

  Future<void> _initConnectivity() async {
    final results = await Connectivity().checkConnectivity();
    if (!results.contains(ConnectivityResult.none)) {
      await _verifyP2PConnection();
    } else {
      setState(() {
        _isConnected = false;
      });
    }
  }

  @override
  void dispose() {
    _p2pPingTimer?.cancel();
    _connectivitySubscription.cancel();
    super.dispose();
  }

  Future<void> _loadDomains() async {
    final prefs = await SharedPreferences.getInstance();
    setState(() {
      _ownedDomains = prefs.getStringList('delegated_names') ?? [];
      _isLoading = false;
    });
  }

  void _showLookupSheet() {
    showModalBottomSheet(
      context: context,
      useRootNavigator: true,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => const IdentityLookupSheet(),
    );
  }

  void _showRegisterSheet() {
    showModalBottomSheet(
      context: context,
      useRootNavigator: true,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => RegisterDomainSheet(onRegistered: _loadDomains),
    );
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(24, 32, 24, 120),
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
                      'Manage Kin',
                      style: GoogleFonts.outfit(
                        fontSize: 24,
                        fontWeight: FontWeight.w700,
                        color: AppTheme.textPrimary,
                      ),
                    ),
                    const Text(
                      'Your decentralized identities',
                      style: TextStyle(fontSize: 14, color: AppTheme.textSecondary),
                    ),
                  ],
                ),
              ],
            ),
            const SizedBox(height: 32),

            // Action Buttons
            Row(
              children: [
                Expanded(
                  child: _ActionButton(
                    icon: Icons.search_rounded,
                    label: 'Lookup\nIdentity',
                    onTap: _showLookupSheet,
                    color: AppTheme.surfaceVariant,
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: _ActionButton(
                    icon: Icons.add_rounded,
                    label: 'Register\nDomain',
                    onTap: _showRegisterSheet,
                    color: AppTheme.primary.withValues(alpha: 0.2),
                    iconColor: AppTheme.primary,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 48),

            // Owned Domains List
            Text(
              'My Domains',
              style: GoogleFonts.outfit(
                fontSize: 20,
                fontWeight: FontWeight.w700,
                color: AppTheme.textPrimary,
              ),
            ),
            const SizedBox(height: 16),

            if (_isLoading)
              const Center(child: CircularProgressIndicator())
            else if (_ownedDomains.isEmpty)
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(32),
                decoration: BoxDecoration(
                  color: AppTheme.surface.withValues(alpha: 0.5),
                  borderRadius: BorderRadius.circular(24),
                  border: Border.all(color: AppTheme.border.withValues(alpha: 0.5)),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.04),
                      blurRadius: 16,
                      offset: const Offset(0, 8),
                    )
                  ],
                ),
                child: Column(
                  children: [
                    Icon(Icons.layers_clear_rounded, size: 48, color: AppTheme.textHint.withValues(alpha: 0.5)),
                    const SizedBox(height: 16),
                    const Text(
                      'No domains owned yet',
                      style: TextStyle(color: AppTheme.textHint, fontWeight: FontWeight.w600),
                    ),
                  ],
                ),
              )
            else
              ListView.separated(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                itemCount: _ownedDomains.length,
                separatorBuilder: (context, index) => const SizedBox(height: 12),
                itemBuilder: (context, index) {
                  final domain = _ownedDomains[index];
                  return Container(
                    padding: const EdgeInsets.all(20),
                    decoration: BoxDecoration(
                      color: AppTheme.surface,
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(color: AppTheme.border.withValues(alpha: 0.5)),
                    ),
                    child: Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.all(10),
                          decoration: BoxDecoration(
                            color: AppTheme.primary.withValues(alpha: 0.1),
                            shape: BoxShape.circle,
                          ),
                          child: const Icon(Icons.language_rounded, color: AppTheme.primary, size: 24),
                        ),
                        const SizedBox(width: 16),
                        Expanded(
                          child: Text(
                            '$domain${AppConstants.dotTld}',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: GoogleFonts.firaCode(
                              fontSize: 18,
                              fontWeight: FontWeight.w600,
                              color: AppTheme.textPrimary,
                            ),
                          ),
                        ),
                        const Icon(Icons.verified_rounded, color: AppTheme.success, size: 24),
                      ],
                    ),
                  );
                },
              ),
            const SizedBox(height: 48),

            // Connection Status Card
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: _isConnected ? AppTheme.success.withValues(alpha: 0.1) : AppTheme.error.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(24),
                border: Border.all(
                  color: _isConnected ? AppTheme.success.withValues(alpha: 0.3) : AppTheme.error.withValues(alpha: 0.3),
                ),
              ),
              child: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: _isConnected ? AppTheme.success.withValues(alpha: 0.2) : AppTheme.error.withValues(alpha: 0.2),
                      shape: BoxShape.circle,
                    ),
                    child: Icon(
                      _isConnected ? Icons.wifi_tethering_rounded : Icons.wifi_off_rounded,
                      color: _isConnected ? AppTheme.success : AppTheme.error,
                      size: 28,
                    ),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          _isConnected ? 'Connected to Network' : 'Disconnected',
                          style: GoogleFonts.outfit(
                            fontSize: 18,
                            fontWeight: FontWeight.w600,
                            color: _isConnected ? AppTheme.success : AppTheme.error,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          _isConnected ? 'Connected to P2P nodes' : 'No internet connection',
                          style: TextStyle(
                            fontSize: 14,
                            color: (_isConnected ? AppTheme.success : AppTheme.error).withValues(alpha: 0.8),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ActionButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final Color color;
  final Color? iconColor;

  const _ActionButton({
    required this.icon,
    required this.label,
    required this.onTap,
    required this.color,
    this.iconColor,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 24, horizontal: 16),
        decoration: BoxDecoration(
          color: color,
          borderRadius: BorderRadius.circular(24),
          border: Border.all(color: AppTheme.border.withValues(alpha: 0.5)),
        ),
        child: Column(
          children: [
            Icon(icon, size: 32, color: iconColor ?? AppTheme.textPrimary),
            const SizedBox(height: 12),
            Text(
              label,
              textAlign: TextAlign.center,
              style: GoogleFonts.outfit(
                fontSize: 16,
                fontWeight: FontWeight.w600,
                color: AppTheme.textPrimary,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
