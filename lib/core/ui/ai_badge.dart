import 'package:flutter/material.dart';

/// "AI Original" badge shown on tracks whose backend `ai_pct` > 0
/// (strategy doc §3 visual tagging requirement).
class AiBadge extends StatelessWidget {
  final int aiPct;
  final bool compact;

  const AiBadge({super.key, required this.aiPct, this.compact = true});

  @override
  Widget build(BuildContext context) {
    if (aiPct <= 0) return const SizedBox.shrink();
    return Container(
      padding: EdgeInsets.symmetric(
        horizontal: compact ? 6 : 8,
        vertical: compact ? 2 : 4,
      ),
      decoration: BoxDecoration(
        color: const Color(0xFF8B5CF6).withValues(alpha: 0.25),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: const Color(0xFF8B5CF6).withValues(alpha: 0.6)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.auto_awesome, size: compact ? 10 : 12, color: const Color(0xFFC4B5FD)),
          const SizedBox(width: 3),
          Text(
            compact ? 'AI' : 'AI Original',
            style: TextStyle(
              color: const Color(0xFFC4B5FD),
              fontSize: compact ? 9 : 11,
              fontWeight: FontWeight.w700,
              letterSpacing: 0.4,
            ),
          ),
        ],
      ),
    );
  }
}
