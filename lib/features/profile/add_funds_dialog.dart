import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/storage/secure_storage.dart';
import '../auth/auth_gate.dart';
import 'user_edit_service.dart';
import '../../core/utils/app_logger.dart';

class AddFundsDialog extends StatefulWidget {
  const AddFundsDialog({super.key});

  @override
  State<AddFundsDialog> createState() => _AddFundsDialogState();
}

class _AddFundsDialogState extends State<AddFundsDialog> {
  final _svc = UserEditService();
  final _amountController = TextEditingController();
  
  bool _loading = false;
  String? _error;
  List<Map<String, dynamic>> _gateways = [];
  String? _selectedGateway;
  double _selectedAmount = 10.0;

  final List<double> _presetAmounts = [5.0, 10.0, 25.0, 50.0, 100.0];

  @override
  void initState() {
    super.initState();
    _loadPaymentGateways();
  }

  @override
  void dispose() {
    _amountController.dispose();
    super.dispose();
  }

  Future<void> _loadPaymentGateways() async {
    AppLogger.d('[ADD_FUNDS] Loading payment gateways...');
    setState(() {
      _loading = true;
      _error = null;
    });

    final loggedIn = await AuthGate.isLoggedIn();
    AppLogger.d('[ADD_FUNDS] Logged in: $loggedIn');
    if (!mounted) return;
    if (!loggedIn) {
      if (mounted) {
        setState(() {
          _loading = false;
          _error = 'Please login to add funds';
        });
      }
      return;
    }

    AppLogger.d('[ADD_FUNDS] Calling initializePayment...');
    final res = await _svc.initializePayment();
    AppLogger.d('[ADD_FUNDS] Payment init result: ${res.isSuccess}, error: ${res.error?.message}');
    if (!mounted) return;

    if (!res.isSuccess || res.data == null) {
      setState(() {
        _loading = false;
        _error = res.error?.message ?? 'Failed to load payment options';
      });
      return;
    }

    // Gateways is a Map with gateway names as keys, convert to List
    final gatewaysMap = res.data!['gateways'] as Map<String, dynamic>?;
    final List<Map<String, dynamic>> gateways = [];
    
    if (gatewaysMap != null) {
      gatewaysMap.forEach((key, value) {
        if (value is Map<String, dynamic>) {
          // Add the gateway name/id to the map
          final gatewayData = Map<String, dynamic>.from(value);
          gatewayData['id'] = key;
          gatewayData['name'] = gatewayData['title'] ?? key;
          gateways.add(gatewayData);
        }
      });
    }

    setState(() {
      _loading = false;
      _gateways = gateways;
      if (_gateways.isNotEmpty) {
        _selectedGateway = _gateways.first['id']?.toString();
      }
    });

    // Some backend builds answer user_pay_ini with a direct payment-page
    // link instead of a gateways map — open it straight away.
    if (gateways.isEmpty) {
      final direct = UserEditService.extractPaymentUrl(res.data!);
      if (direct != null) {
        final uri = Uri.parse(direct);
        if (await canLaunchUrl(uri)) {
          await launchUrl(uri, mode: LaunchMode.externalApplication);
          if (mounted) Navigator.of(context).pop();
        }
      }
    }
  }

  Future<void> _proceedWithPayment() async {
    if (_selectedGateway == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please select a payment method')),
      );
      return;
    }

    final amount = _amountController.text.isNotEmpty 
        ? double.tryParse(_amountController.text)
        : _selectedAmount;

    if (amount == null || amount <= 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please enter a valid amount')),
      );
      return;
    }

    setState(() => _loading = true);

    final userId = await SecureStore.getUserId();
    AppLogger.d('[ADD_FUNDS] User ID: $userId');

    // For add funds, purchaseData should be null (not subscription data)
    // Backend expects null for wallet funds, not an object with type/hook/period
    final Map<String, dynamic>? purchaseData = null;
    AppLogger.d('[ADD_FUNDS] Purchase data: null (for wallet funds)');

    final res = await _svc.getPaymentLink(
      gateway: _selectedGateway!,
      amount: amount,
      purchaseData: purchaseData,
    );

    if (!mounted) return;

    setState(() => _loading = false);

    if (!res.isSuccess || res.data == null) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(res.error?.message ?? 'Failed to create payment')),
        );
      }
      return;
    }

    // Backend builds differ on where the checkout URL lives — deep-scan.
    final paymentUrl = UserEditService.extractPaymentUrl(res.data!);
    if (paymentUrl != null && paymentUrl.isNotEmpty) {
      final uri = Uri.parse(paymentUrl);
      if (await canLaunchUrl(uri)) {
        await launchUrl(uri, mode: LaunchMode.externalApplication);
        if (mounted) {
          Navigator.of(context).pop(); // Close dialog after opening payment
        }
      } else {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Could not open payment link')),
          );
        }
      }
    } else {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Invalid payment response')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: Colors.black,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      insetPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
      child: Container(
        width: MediaQuery.of(context).size.width * 0.9,
        constraints: BoxConstraints(
          maxHeight: MediaQuery.of(context).size.height * 0.85,
        ),
        padding: const EdgeInsets.all(20),
        child: SingleChildScrollView(
          keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  const Icon(Icons.account_balance_wallet_outlined, 
                           color: Colors.greenAccent, size: 28),
                  const SizedBox(width: 12),
                  const Expanded(
                    child: Text(
                      'Add Funds',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 24,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                  IconButton(
                    onPressed: () => Navigator.of(context).pop(),
                    icon: const Icon(Icons.close, color: Colors.white70),
                  ),
                ],
              ),
              const SizedBox(height: 24),

            if (_error != null) ...[
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.red.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: Colors.red.withValues(alpha: 0.3)),
                ),
                child: Row(
                  children: [
                    Icon(Icons.error_outline, color: Colors.redAccent, size: 20),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        _error!,
                        style: const TextStyle(color: Colors.redAccent, fontSize: 14),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),
            ],

            if (_loading) ...[
              const Center(child: CircularProgressIndicator()),
              const SizedBox(height: 20),
            ] else ...[
              // Payment Method Selection
              const Text(
                'Payment Method',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 12),
              if (_gateways.isEmpty)
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.05),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: const Text(
                    'No payment methods available',
                    style: TextStyle(color: Colors.white70),
                  ),
                )
              else
                Column(
                  children: _gateways.map((gateway) {
                    final gatewayId = gateway['id']?.toString() ?? '';
                    final isSelected = _selectedGateway == gatewayId;
                    return Padding(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: InkWell(
                        onTap: () {
                          setState(() => _selectedGateway = gatewayId);
                        },
                        borderRadius: BorderRadius.circular(8),
                        child: Container(
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            border: Border.all(
                              color: isSelected 
                                  ? Colors.greenAccent 
                                  : Colors.white.withValues(alpha: 0.2),
                            ),
                            borderRadius: BorderRadius.circular(8),
                            color: isSelected 
                                ? Colors.greenAccent.withValues(alpha: 0.1) 
                                : Colors.transparent,
                          ),
                          child: Row(
                            children: [
                              Icon(
                                isSelected 
                                    ? Icons.radio_button_checked 
                                    : Icons.radio_button_unchecked,
                                color: isSelected ? Colors.greenAccent : Colors.white70,
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      gateway['name']?.toString() ?? gatewayId,
                                      style: const TextStyle(color: Colors.white),
                                    ),
                                    if (gateway['description'] != null)
                                      Text(
                                        gateway['description'].toString(),
                                        style: TextStyle(
                                          color: Colors.white.withValues(alpha: 0.6),
                                          fontSize: 12,
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
                  }).toList(),
                ),
              
              const SizedBox(height: 24),

              // Amount Selection
              const Text(
                'Select Amount',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 12),
              
              // Preset Amount Buttons
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: _presetAmounts.map((amount) {
                  final isSelected = _selectedAmount == amount;
                  return ChoiceChip(
                    label: Text('\$${amount.toStringAsFixed(0)}'),
                    selected: isSelected,
                    onSelected: (selected) {
                      if (selected) {
                        setState(() {
                          _selectedAmount = amount;
                          _amountController.clear();
                        });
                      }
                    },
                    backgroundColor: Colors.white.withValues(alpha: 0.1),
                    selectedColor: Colors.greenAccent.withValues(alpha: 0.2),
                    labelStyle: TextStyle(
                      color: isSelected ? Colors.greenAccent : Colors.white70,
                      fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                    ),
                    side: BorderSide(
                      color: isSelected ? Colors.greenAccent : Colors.white.withValues(alpha: 0.2),
                    ),
                  );
                }).toList(),
              ),

              const SizedBox(height: 16),

              // Custom Amount Input
              TextField(
                controller: _amountController,
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                decoration: InputDecoration(
                  labelText: 'Custom Amount',
                  labelStyle: TextStyle(color: Colors.white.withValues(alpha: 0.7)),
                  prefixText: '\$ ',
                  prefixStyle: const TextStyle(color: Colors.white70),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(8),
                    borderSide: BorderSide(color: Colors.white.withValues(alpha: 0.2)),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(8),
                    borderSide: const BorderSide(color: Colors.greenAccent),
                  ),
                ),
                style: const TextStyle(color: Colors.white),
                onChanged: (value) {
                  if (value.isNotEmpty) {
                    final amount = double.tryParse(value);
                    if (amount != null && amount > 0) {
                      setState(() => _selectedAmount = amount);
                    }
                  }
                },
              ),

              const SizedBox(height: 24),

              // Proceed Button
              SizedBox(
                width: double.infinity,
                child: FilledButton(
                  onPressed: _loading ? null : _proceedWithPayment,
                  style: FilledButton.styleFrom(
                    backgroundColor: Colors.greenAccent,
                    foregroundColor: Colors.black,
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                  child: _loading
                      ? const SizedBox(
                          height: 20,
                          width: 20,
                          child: CircularProgressIndicator(strokeWidth: 2, color: Colors.black),
                        )
                      : Text(
                          'Proceed to Payment (\$${_selectedAmount.toStringAsFixed(2)})',
                          style: const TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                ),
              ),
            ],
          ],
        ),
      ),
    ),
  );
}
}
