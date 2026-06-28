import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:webview_flutter/webview_flutter.dart';
import 'package:kinetic/src/models/resolved_site.dart';
import 'package:kinetic/src/theme/app_theme.dart';
import 'package:kinetic/src/widgets/trust_sheet.dart';
import 'package:google_fonts/google_fonts.dart';

/// Full-screen browser page that loads a resolved .kin site in a WebView.
/// Shows a floating glassmorphic bottom bar with the URL, controls, and trust state.
class BrowserPage extends StatefulWidget {
  final ResolvedSite site;

  const BrowserPage({super.key, required this.site});

  @override
  State<BrowserPage> createState() => _BrowserPageState();
}

class _BrowserPageState extends State<BrowserPage> {
  late final WebViewController _controller;
  bool _isLoading = true;
  int _loadingProgress = 0;

  @override
  void initState() {
    super.initState();
    _controller = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setNavigationDelegate(
        NavigationDelegate(
          onPageStarted: (_) => setState(() {
            _isLoading = true;
            _loadingProgress = 0;
          }),
          onProgress: (progress) => setState(() => _loadingProgress = progress),
          onPageFinished: (_) => setState(() => _isLoading = false),
        ),
      )
      ..loadRequest(Uri.parse(widget.site.targetUrl));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.background,
      body: Stack(
        children: [
          SafeArea(
            bottom: false,
            child: WebViewWidget(controller: _controller),
          ),
          _buildFloatingBottomBar(context),
        ],
      ),
    );
  }

  Widget _buildFloatingBottomBar(BuildContext context) {
    return Positioned(
      bottom: MediaQuery.of(context).padding.bottom + 16,
      left: 16,
      right: 16,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(32),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 16, sigmaY: 16),
          child: Container(
            decoration: BoxDecoration(
              color: AppTheme.surface.withOpacity(0.75),
              borderRadius: BorderRadius.circular(32),
              border: Border.all(color: AppTheme.border.withOpacity(0.5)),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.1),
                  blurRadius: 20,
                  offset: const Offset(0, 10),
                )
              ],
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (_isLoading)
                  LinearProgressIndicator(
                    value: _loadingProgress / 100,
                    backgroundColor: Colors.transparent,
                    color: AppTheme.primary,
                    minHeight: 2,
                  ),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
                  child: Row(
                    children: [
                      // Close Button
                      IconButton(
                        icon: const Icon(Icons.close_rounded, size: 22, color: AppTheme.textSecondary),
                        onPressed: () => Navigator.pop(context),
                        tooltip: 'Close',
                      ),
                      
                      // URL & Trust Badge (Center)
                      Expanded(
                        child: GestureDetector(
                          onTap: () => TrustSheet.show(
                            context,
                            kinName: widget.site.kinUrl,
                            trustStateJson: widget.site.trustStateJson,
                          ),
                          child: Container(
                            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                            decoration: BoxDecoration(
                              color: AppTheme.surfaceVariant.withOpacity(0.5),
                              borderRadius: BorderRadius.circular(20),
                            ),
                            child: Row(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                const Icon(Icons.lock_rounded, color: AppTheme.success, size: 14),
                                const SizedBox(width: 8),
                                Flexible(
                                  child: Text(
                                    '${widget.site.displayName}.kin',
                                    style: GoogleFonts.firaCode(
                                      fontSize: 14,
                                      fontWeight: FontWeight.w600,
                                      color: AppTheme.textPrimary,
                                    ),
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                      
                      // Refresh Button
                      IconButton(
                        icon: _isLoading 
                            ? const SizedBox(
                                width: 20, 
                                height: 20, 
                                child: CircularProgressIndicator(strokeWidth: 2, color: AppTheme.textSecondary)
                              )
                            : const Icon(Icons.refresh_rounded, size: 22, color: AppTheme.textSecondary),
                        onPressed: _isLoading ? null : () => _controller.reload(),
                        tooltip: 'Refresh',
                      ),
                    ],
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
