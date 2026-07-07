import 'package:flutter/material.dart';
import 'package:kinetic/src/constants.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:kinetic/src/theme/app_theme.dart';


/// The glassmorphism address bar used on the Browser tab.
/// Shows a `kin://` prefix hint and fires [onSubmitted] when the user taps Go.
class KinAddressBar extends StatefulWidget {
  final TextEditingController controller;
  final bool loading;
  final VoidCallback onSubmitted;

  const KinAddressBar({
    super.key,
    required this.controller,
    required this.loading,
    required this.onSubmitted,
  });

  @override
  State<KinAddressBar> createState() => _KinAddressBarState();
}

class _KinAddressBarState extends State<KinAddressBar> {
  final FocusNode _focusNode = FocusNode();
  bool _isFocused = false;

  @override
  void initState() {
    super.initState();
    _focusNode.addListener(() => setState(() => _isFocused = _focusNode.hasFocus));
  }

  @override
  void dispose() {
    _focusNode.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedContainer(
      duration: const Duration(milliseconds: 200),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: _isFocused ? AppTheme.primary : AppTheme.border.withValues(alpha: 0.5),
          width: _isFocused ? 2 : 1,
        ),
        color: AppTheme.surface.withValues(alpha: 0.6),
        boxShadow: _isFocused
            ? [
                BoxShadow(
                  color: AppTheme.primary.withValues(alpha: 0.12),
                  blurRadius: 16,
                  offset: const Offset(0, 4),
                )
              ]
            : [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.02),
                  blurRadius: 10,
                  offset: const Offset(0, 4),
                )
              ],
      ),
      child: Row(
        children: [
          const SizedBox(width: 16),
          Icon(
            Icons.language_rounded,
            size: 20,
            color: _isFocused ? AppTheme.primary : AppTheme.textHint,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: TextField(
              controller: widget.controller,
              focusNode: _focusNode,
              keyboardType: TextInputType.url,
              autocorrect: false,
              enableSuggestions: false,
              textCapitalization: TextCapitalization.none,
              style: GoogleFonts.outfit(
                fontSize: 16,
                color: AppTheme.textPrimary,
                fontWeight: FontWeight.w500,
              ),
              decoration: const InputDecoration(
                hintText: 'example${AppConstants.dotTld} or google.com',
                border: InputBorder.none,
                enabledBorder: InputBorder.none,
                focusedBorder: InputBorder.none,
                filled: false,
                contentPadding: EdgeInsets.symmetric(vertical: 16),
                hintStyle: TextStyle(color: AppTheme.textHint),
              ),
              textInputAction: TextInputAction.go,
              onSubmitted: (_) => widget.onSubmitted(),
            ),
          ),
          if (widget.loading)
            const Padding(
              padding: EdgeInsets.only(right: 16),
              child: SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(
                  strokeWidth: 2.5,
                  color: AppTheme.primary,
                ),
              ),
            )
          else
            GestureDetector(
              onTap: widget.onSubmitted,
              child: Container(
                margin: const EdgeInsets.only(right: 8),
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: AppTheme.primary,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Icon(Icons.arrow_forward_rounded, size: 18, color: Colors.white),
              ),
            ),
        ],
      ),
    );
  }
}
