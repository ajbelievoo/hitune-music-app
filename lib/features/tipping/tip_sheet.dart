import 'package:flutter/material.dart';

import '../player/models/track.dart';
import 'tip_service.dart';

/// Quick tip sheet — pick an amount, send it to the track's artist.
class TipSheet extends StatefulWidget {
  final Track track;
  const TipSheet({super.key, required this.track});

  static Future<void> show(BuildContext context, Track track) {
    return showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (_) => TipSheet(track: track),
    );
  }

  @override
  State<TipSheet> createState() => _TipSheetState();
}

class _TipSheetState extends State<TipSheet> {
  static const _amounts = [10, 20, 50, 100, 200];
  double? _wallet;
  int _selected = 1;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    TipService.instance.wallet().then((w) {
      if (mounted) setState(() => _wallet = w?.balance);
    });
  }

  Future<void> _send() async {
    final amount = _amounts[_selected].toDouble();
    setState(() => _busy = true);
    final res = await TipService.instance.sendTip(
      trackHash: widget.track.objectHash ?? widget.track.id,
      amount: amount,
    );
    if (!mounted) return;
    setState(() => _busy = false);
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(res.success ? '₹${amount.toInt()} tip sent to the artist' : 'Tip failed: ${res.error}'),
    ));
    if (res.success) Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 20, 20, 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text('Tip the artist',
                style: theme.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w700)),
            const SizedBox(height: 4),
            Text(
              widget.track.title,
              style: theme.textTheme.bodyMedium,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
            if (_wallet != null) ...[
              const SizedBox(height: 6),
              Text('Wallet balance: ₹${_wallet!.toStringAsFixed(0)}',
                  style: theme.textTheme.bodySmall),
            ],
            const SizedBox(height: 16),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: List.generate(_amounts.length, (i) {
                final sel = i == _selected;
                return ChoiceChip(
                  label: Text('₹${_amounts[i]}'),
                  selected: sel,
                  onSelected: _busy ? null : (_) => setState(() => _selected = i),
                );
              }),
            ),
            const SizedBox(height: 18),
            FilledButton.icon(
              onPressed: _busy ? null : _send,
              icon: const Icon(Icons.volunteer_activism_rounded),
              label: Text(_busy ? 'Sending…' : 'Send ₹${_amounts[_selected]} tip'),
            ),
            const SizedBox(height: 6),
            Text(
              'Artists get 80% of every tip — 100% on Creator Day.',
              style: theme.textTheme.bodySmall,
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }
}
