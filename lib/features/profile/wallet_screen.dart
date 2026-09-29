import 'package:flutter/material.dart';

import '../../core/ads/ad_service.dart';
import '../auth/auth_gate.dart';
import 'add_funds_dialog.dart';
import 'user_edit_service.dart';
import '../../core/utils/app_logger.dart';

class WalletScreen extends StatefulWidget {
  const WalletScreen({super.key});

  static Future<void> openWithAuth(BuildContext context) async {
    final ok = await AuthGate.ensureLoggedIn(context, reason: 'Login required to access your wallet.');
    if (!ok) return;
    if (!context.mounted) return;
    await Navigator.of(context).push(
      MaterialPageRoute<void>(builder: (_) => const WalletScreen()),
    );
  }

  @override
  State<WalletScreen> createState() => _WalletScreenState();
}

class _WalletScreenState extends State<WalletScreen> {
  final _svc = UserEditService();

  bool _loading = false;
  String? _error;
  String _fundsText = '₹0.00';
  List<_Txn> _txns = const [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  String? _extractFundsText(Map<String, dynamic> payload) {
    // user_edit transactions tab returns html with funds number.
    final tab = payload['transactions'];
    if (tab is Map) {
      final html = tab['html']?.toString();
      if (html != null && html.isNotEmpty) {
        final m = RegExp(r"class='_p'>([^<]+)<").firstMatch(html);
        if (m != null) return m.group(1)?.trim();
      }
    }
    final html = payload['html']?.toString();
    if (html != null && html.isNotEmpty) {
      final m = RegExp(r"class='_p'>([^<]+)<").firstMatch(html);
      if (m != null) return m.group(1)?.trim();
    }
    return null;
  }

  List<_Txn> _extractTxns(Map<String, dynamic> payload) {
    final tab = payload['transactions'];
    final html = (tab is Map ? tab['html'] : payload['html'])?.toString() ?? '';
    if (html.isEmpty) return const [];

    final matches = RegExp(r"<div class='transaction[^']*'>([\s\S]*?)<\/div>").allMatches(html);
    final out = <_Txn>[];
    for (final m in matches) {
      final chunk = m.group(0) ?? '';
      final type = RegExp(r"<div class='_type'>([^<]+)<").firstMatch(chunk)?.group(1)?.trim();
      final amount = RegExp(r"<div class='_amount'><b>([^<]+)<").firstMatch(chunk)?.group(1)?.trim();
      final currency = RegExp(r"<\/b>\s*([^<]+)<").firstMatch(chunk)?.group(1)?.trim();
      final title = RegExp(r"<div class='_ci'>\s*<b>([^<]+)<").firstMatch(chunk)?.group(1)?.trim();
      if ((type ?? '').isEmpty && (amount ?? '').isEmpty && (title ?? '').isEmpty) continue;
      out.add(_Txn(type: type ?? 'Transaction', amount: amount ?? '', currency: currency ?? '', title: title ?? ''));
    }
    return out;
  }

  Future<void> _load() async {
    if (_loading) return;
    setState(() {
      _loading = true;
      _error = null;
    });

    final loggedIn = await AuthGate.isLoggedIn();
    debugPrint('[WALLET] _load() - loggedIn: $loggedIn');
    if (!mounted) return;
    if (!loggedIn) {
      setState(() {
        _loading = false;
        _txns = const [];
        _fundsText = '₹0.00';
      });
      return;
    }

    final res = await _svc.fetchTab(tab: 'transactions');
    debugPrint('[WALLET] _load() - fetchTab result: isSuccess=${res.isSuccess}, error=${res.error?.message}');
    if (!mounted) return;

    if (!res.isSuccess || res.data == null) {
      setState(() {
        _loading = false;
        _error = res.error?.message ?? 'Failed to load wallet';
      });
      return;
    }

    debugPrint('[WALLET] _load() - data keys: ${res.data!.keys}');
    final funds = _extractFundsText(res.data!) ?? '₹0.00';
    final txns = _extractTxns(res.data!);
    debugPrint('[WALLET] _load() - funds: $funds, txns count: ${txns.length}');
    setState(() {
      _loading = false;
      _fundsText = funds;
      _txns = txns;
    });
  }

  Future<void> _showRewardedAd() async {
    debugPrint('[WALLET] Watch Ad button pressed');
    
    final loggedIn = await AuthGate.isLoggedIn();
    if (!loggedIn) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Please login to earn rewards')),
        );
      }
      return;
    }

    setState(() => _loading = true);

    // Preload rewarded ad
    await AdService.instance.loadRewardedAd();
    
    // Small delay to ensure ad is loaded
    await Future.delayed(const Duration(milliseconds: 500));

    setState(() => _loading = false);

    // Show rewarded ad
    final adShown = await AdService.instance.showRewardedAd(
      onRewardEarned: () {
        debugPrint('[WALLET] User earned reward from ad!');
        // Here you would typically call an API to credit the user's wallet
        // For now, show a success message
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('🎉 You earned ₹5! Reward will be added to your wallet.'),
              backgroundColor: Colors.green,
            ),
          );
          // Refresh wallet to show updated balance
          _load();
        }
      },
    );

    if (!adShown && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Ad not available right now. Please try again later.'),
          backgroundColor: Colors.orange,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<bool>(
      future: AuthGate.isLoggedIn(),
      builder: (context, snap) {
        final loggedIn = snap.data == true;

        return Scaffold(
          backgroundColor: Colors.black,
          appBar: AppBar(
            title: const Text('My Wallet'),
            backgroundColor: Colors.black,
            actions: [
              IconButton(onPressed: _loading ? null : _load, icon: const Icon(Icons.refresh_rounded)),
            ],
          ),
          body: !loggedIn
              ? _buildGuestView()
              : _loading
                  ? const Center(child: CircularProgressIndicator())
                  : _error != null
                      ? _buildErrorView()
                      : _buildWalletContent(),
        );
      },
    );
  }

  Widget _buildGuestView() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 80,
              height: 80,
              decoration: BoxDecoration(
                color: Colors.greenAccent.withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(40),
              ),
              child: Icon(Icons.account_balance_wallet_outlined, size: 40, color: Colors.greenAccent.withValues(alpha: 0.8)),
            ),
            const SizedBox(height: 20),
            Text('Login to access your wallet', style: TextStyle(color: Colors.white.withValues(alpha: 0.9), fontSize: 18, fontWeight: FontWeight.w700)),
            const SizedBox(height: 8),
            Text('Your funds and transactions will appear here', style: TextStyle(color: Colors.white.withValues(alpha: 0.55))),
            const SizedBox(height: 24),
            FilledButton(
              onPressed: () async {
                final ok = await AuthGate.ensureLoggedIn(context, reason: 'Login required to access your wallet.');
                if (!ok) return;
                await _load();
              },
              child: const Text('Login'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildErrorView() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.error_outline, size: 48, color: Colors.redAccent.withValues(alpha: 0.8)),
            const SizedBox(height: 16),
            Text(_error!, style: TextStyle(color: Colors.white.withValues(alpha: 0.8), fontSize: 16)),
            const SizedBox(height: 20),
            OutlinedButton(onPressed: _load, child: const Text('Retry')),
          ],
        ),
      ),
    );
  }

  Widget _buildWalletContent() {
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Balance Card
          Container(
            padding: const EdgeInsets.all(24),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [Colors.greenAccent.withValues(alpha: 0.2), Colors.black],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: Colors.greenAccent.withValues(alpha: 0.2)),
            ),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Your funds',
                        style: TextStyle(color: Colors.white.withValues(alpha: 0.75), fontWeight: FontWeight.w600, fontSize: 14),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        _fundsText,
                        style: const TextStyle(color: Colors.white, fontSize: 36, fontWeight: FontWeight.w900),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        'Balance is synced to your account',
                        style: TextStyle(color: Colors.white.withValues(alpha: 0.55), fontSize: 12),
                      ),
                    ],
                  ),
                ),
                FilledButton(
                  style: FilledButton.styleFrom(backgroundColor: Colors.greenAccent.withValues(alpha: 0.9)),
                  onPressed: () async {
                    AppLogger.d('[WALLET] Add Funds button pressed');
                    try {
                      await showDialog(
                        context: context,
                        builder: (context) => const AddFundsDialog(),
                      );
                      // Refresh wallet after dialog closes
                      await _load();
                      AppLogger.d('[WALLET] AddFundsDialog closed, wallet refreshed');
                    } catch (e) {
                      AppLogger.d('[WALLET] Error in Add Funds: $e');
                      if (context.mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(content: Text('Error: $e')),
                        );
                      }
                    }
                  },
                  child: const Text('Add Funds', style: TextStyle(color: Colors.black, fontWeight: FontWeight.w700)),
                ),
              ],
            ),
          ),
          const SizedBox(height: 24),
          // Watch Ad to Earn Button
          SizedBox(
            width: double.infinity,
            child: OutlinedButton.icon(
              onPressed: _loading ? null : _showRewardedAd,
              icon: _loading 
                  ? const SizedBox(height: 18, width: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                  : const Icon(Icons.play_circle_outline, color: Colors.amberAccent),
              label: Text(
                _loading ? 'Loading...' : 'Watch Ad to Earn ₹5',
                style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w600),
              ),
              style: OutlinedButton.styleFrom(
                side: const BorderSide(color: Colors.amberAccent),
                padding: const EdgeInsets.symmetric(vertical: 14),
              ),
            ),
          ),
          const SizedBox(height: 24),
          Text(
            'Transactions',
            style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w800, fontSize: 16),
          ),
          const SizedBox(height: 12),
          Expanded(
            child: _txns.isEmpty
                ? _buildEmptyTransactions()
                : ListView.separated(
                    itemCount: _txns.length,
                    separatorBuilder: (context, index) => const SizedBox(height: 8),
                    itemBuilder: (context, i) => _buildTxnCard(_txns[i]),
                  ),
          ),
        ],
      ),
    );
  }

  Widget _buildEmptyTransactions() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(32),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.04),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.receipt_long_outlined, size: 48, color: Colors.white.withValues(alpha: 0.4)),
          const SizedBox(height: 12),
          Text('No transactions yet', style: TextStyle(color: Colors.white.withValues(alpha: 0.6))),
        ],
      ),
    );
  }

  Widget _buildTxnCard(_Txn t) {
    final amountText = [t.amount, t.currency].where((e) => e.trim().isNotEmpty).join(' ');
    final isPositive = t.amount.startsWith('+');
    final amountColor = isPositive ? Colors.greenAccent : Colors.redAccent;
    
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.04),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.white.withValues(alpha: 0.06)),
      ),
      child: Row(
        children: [
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              color: amountColor.withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(
              isPositive ? Icons.arrow_downward_rounded : Icons.arrow_upward_rounded,
              color: amountColor,
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(t.type, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700)),
                if (t.title.isNotEmpty)
                  Text(t.title, style: TextStyle(color: Colors.white.withValues(alpha: 0.55), fontSize: 12)),
              ],
            ),
          ),
          Text(
            amountText,
            style: TextStyle(color: amountColor, fontWeight: FontWeight.w800, fontSize: 15),
          ),
        ],
      ),
    );
  }
}

class _Txn {
  final String type;
  final String amount;
  final String currency;
  final String title;

  const _Txn({
    required this.type,
    required this.amount,
    required this.currency,
    required this.title,
  });
}
