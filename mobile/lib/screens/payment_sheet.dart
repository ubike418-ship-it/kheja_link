import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';

import '../config/theme.dart';
import '../main.dart';
import '../services/payments.dart';
import '../widgets/states.dart';

/// Kheja_Link's own payment screen.
///
/// The tenant types their M-Pesa number here, approves the prompt on their
/// phone, and watches the status — all inside Kheja_Link. Paystack is the
/// processor behind it: the app never opens Paystack's pages for M-Pesa and
/// never holds a key.
///
/// Money is never taken on this screen's word. The server asks Paystack what
/// happened and records it; this only reflects the answer.
///
/// Cards are the one exception, and deliberately so: taking a card number
/// inside our own app would make Kheja_Link responsible for PCI-DSS
/// compliance. "Pay by card" opens Paystack's secure card page for the same
/// payment instead.
class PaymentSheet extends StatefulWidget {
  const PaymentSheet({
    super.key,
    required this.reference,
    required this.amountLabel,
    required this.title,
    required this.what,
    this.cardCheckoutUrl,
  });

  /// The pending payment, created by the database before this opens.
  final String reference;
  final String amountLabel;
  final String title;

  /// One line saying what is being paid for.
  final String what;

  /// Optional: Paystack's hosted page for the same payment, for cards.
  final Future<String?> Function()? cardCheckoutUrl;

  @override
  State<PaymentSheet> createState() => _PaymentSheetState();
}

enum _Stage { enterPhone, waiting, otp, success, failed }

class _PaymentSheetState extends State<PaymentSheet> with WidgetsBindingObserver {
  final _phone = TextEditingController();
  final _otp = TextEditingController();

  _Stage _stage = _Stage.enterPhone;
  bool _busy = false;
  String? _error;
  String _instruction = '';
  Timer? _poll;
  DateTime? _startedAt;
  int _checks = 0;

  /// How long we keep asking. An M-Pesa prompt expires well inside this.
  static const _giveUpAfter = Duration(minutes: 3);

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    khejaApi.fetchProfile().then((profile) {
      final phone = profile?.phone;
      if (mounted && phone != null && _phone.text.isEmpty) _phone.text = phone;
    }).catchError((_) {});
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _poll?.cancel();
    _phone.dispose();
    _otp.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // Back from the M-Pesa PIN prompt: check straight away.
    if (state == AppLifecycleState.resumed && _stage == _Stage.waiting) _check();
  }

  void _apply(ChargeResult result) {
    if (!mounted) return;
    setState(() {
      _busy = false;
      switch (result.state) {
        case ChargeState.success:
          _stage = _Stage.success;
          _poll?.cancel();
        case ChargeState.needsOtp:
          _stage = _Stage.otp;
          _instruction = result.instruction;
          _poll?.cancel();
        case ChargeState.failed:
          _stage = _Stage.failed;
          _error = result.message ?? 'The payment did not go through.';
          _poll?.cancel();
        case ChargeState.pending:
          _stage = _Stage.waiting;
          _instruction = result.instruction;
      }
    });
  }

  Future<void> _pay() async {
    final phone = _phone.text.trim();
    if (!RegExp(r'^(\+?254|0)?[17]\d{8}$').hasMatch(phone.replaceAll(RegExp(r'[\s-]'), ''))) {
      setState(() => _error = 'Enter a Safaricom number like 0712 345 678.');
      return;
    }

    setState(() {
      _busy = true;
      _error = null;
      _startedAt = DateTime.now();
      _checks = 0;
    });

    final result = await KhejaCheckout.payWithMpesa(
      reference: widget.reference,
      phone: phone,
    );
    _apply(result);
    if (_stage == _Stage.waiting) _startPolling();
  }

  void _startPolling() {
    _poll?.cancel();
    _poll = Timer.periodic(const Duration(seconds: 4), (_) => _check());
  }

  Future<void> _check() async {
    if (!mounted || _stage == _Stage.success) return;
    final started = _startedAt;
    if (started != null && DateTime.now().difference(started) > _giveUpAfter) {
      _poll?.cancel();
      if (mounted) {
        setState(() {
          _stage = _Stage.failed;
          _error = 'We did not see a payment. If you approved it on your phone, '
              'tap "Check again" — otherwise try once more.';
        });
      }
      return;
    }

    setState(() => _checks++);
    final result = await KhejaCheckout.status(widget.reference);
    // A "pending" answer mid-wait is normal; only act on a decision.
    if (result.state == ChargeState.pending && _stage == _Stage.waiting) {
      if (mounted && result.displayText != null) {
        setState(() => _instruction = result.displayText!);
      }
      return;
    }
    _apply(result);
  }

  Future<void> _submitOtp() async {
    final code = _otp.text.trim();
    if (code.isEmpty) {
      setState(() => _error = 'Enter the code you were sent.');
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    final result = await KhejaCheckout.submitOtp(reference: widget.reference, otp: code);
    _apply(result);
    if (_stage == _Stage.waiting) _startPolling();
  }

  Future<void> _payByCard() async {
    final getUrl = widget.cardCheckoutUrl;
    if (getUrl == null) return;
    setState(() => _busy = true);
    final url = await getUrl();
    if (!mounted) return;
    setState(() => _busy = false);
    if (url == null) {
      setState(() => _error = 'Could not open the card payment page.');
      return;
    }
    setState(() {
      _stage = _Stage.waiting;
      _instruction = 'Finish the card payment in the page that opened, then come back here.';
      _startedAt = DateTime.now();
    });
    _startPolling();
    await launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final media = MediaQuery.of(context);

    return PopScope(
      // Leaving mid-payment would lose the tenant's place in the flow.
      canPop: _stage != _Stage.waiting,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop && mounted) {
          showKhejaSnack(context, 'Finish or cancel the payment first.');
        }
      },
      child: Padding(
        padding: EdgeInsets.only(bottom: media.viewInsets.bottom),
        child: Container(
          constraints: BoxConstraints(maxHeight: media.size.height * 0.9),
          decoration: BoxDecoration(
            color: theme.scaffoldBackgroundColor,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(KhejaRadius.xxl)),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const SizedBox(height: 12),
              Container(
                width: 44,
                height: 5,
                decoration: BoxDecoration(
                  color: KhejaColors.zinc300,
                  borderRadius: BorderRadius.circular(999),
                ),
              ),
              Flexible(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.fromLTRB(24, 20, 24, 24),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _Header(
                        title: widget.title,
                        what: widget.what,
                        amountLabel: widget.amountLabel,
                      ),
                      const SizedBox(height: 22),
                      ...switch (_stage) {
                        _Stage.enterPhone => _phoneStep(theme),
                        _Stage.waiting => _waitingStep(theme),
                        _Stage.otp => _otpStep(theme),
                        _Stage.success => _successStep(theme),
                        _Stage.failed => _failedStep(theme),
                      },
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // Steps
  // ---------------------------------------------------------------------------

  List<Widget> _phoneStep(ThemeData theme) => [
        Row(
          children: [
            Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                color: KhejaColors.emerald.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(KhejaRadius.sm),
              ),
              child: const Icon(Icons.smartphone_rounded, size: 20, color: KhejaColors.emerald),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('M-Pesa', style: theme.textTheme.titleMedium),
                  const Text(
                    'Approve the prompt on your phone',
                    style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: KhejaColors.zinc500),
                  ),
                ],
              ),
            ),
          ],
        ),
        const SizedBox(height: 16),
        TextField(
          controller: _phone,
          keyboardType: TextInputType.phone,
          inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[\d +-]'))],
          decoration: InputDecoration(
            labelText: 'M-Pesa number',
            hintText: '0712 345 678',
            errorText: _error,
            prefixIcon: const Icon(Icons.phone_rounded, size: 20),
          ),
          onSubmitted: (_) => _busy ? null : _pay(),
        ),
        const SizedBox(height: 16),
        SizedBox(
          width: double.infinity,
          child: FilledButton(
            onPressed: _busy ? null : _pay,
            style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(56)),
            child: _busy
                ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                  )
                : Text('Pay ${widget.amountLabel}'),
          ),
        ),
        if (widget.cardCheckoutUrl != null) ...[
          const SizedBox(height: 10),
          SizedBox(
            width: double.infinity,
            child: OutlinedButton.icon(
              onPressed: _busy ? null : _payByCard,
              icon: const Icon(Icons.credit_card_rounded, size: 19),
              label: const Text('Pay by card instead'),
            ),
          ),
          const SizedBox(height: 6),
          const Text(
            'Card payments open a secure bank page, so your card number is never '
            'typed into Kheja_Link.',
            style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.w600, color: KhejaColors.zinc400, height: 1.45),
          ),
        ],
        const SizedBox(height: 12),
        const _SafetyLine(),
      ];

  List<Widget> _waitingStep(ThemeData theme) => [
        Row(
          children: [
            const SizedBox(
              width: 22,
              height: 22,
              child: CircularProgressIndicator(strokeWidth: 2.5, color: KhejaColors.blue),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Text('Waiting for your approval', style: theme.textTheme.titleMedium),
            ),
          ],
        ),
        const SizedBox(height: 10),
        Text(
          _instruction,
          style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600, height: 1.5),
        ),
        const SizedBox(height: 14),
        const _Steps(),
        const SizedBox(height: 16),
        Text(
          _checks > 1 ? 'Checking… (${_checks}x)' : 'Checking…',
          style: kEyebrowStyle.copyWith(color: KhejaColors.zinc400),
        ),
        const SizedBox(height: 12),
        SizedBox(
          width: double.infinity,
          child: OutlinedButton.icon(
            onPressed: _check,
            icon: const Icon(Icons.refresh_rounded, size: 18),
            label: const Text('Check again'),
          ),
        ),
        const SizedBox(height: 8),
        Center(
          child: TextButton(
            onPressed: () {
              _poll?.cancel();
              setState(() {
                _stage = _Stage.enterPhone;
                _error = null;
              });
            },
            child: const Text('Cancel and start over'),
          ),
        ),
      ];

  List<Widget> _otpStep(ThemeData theme) => [
        Text('Enter the code', style: theme.textTheme.titleMedium),
        const SizedBox(height: 6),
        Text(
          _instruction,
          style: const TextStyle(fontSize: 13.5, fontWeight: FontWeight.w600, height: 1.45),
        ),
        const SizedBox(height: 14),
        TextField(
          controller: _otp,
          keyboardType: TextInputType.number,
          inputFormatters: [FilteringTextInputFormatter.digitsOnly],
          decoration: InputDecoration(labelText: 'Code', errorText: _error),
        ),
        const SizedBox(height: 14),
        SizedBox(
          width: double.infinity,
          child: FilledButton(
            onPressed: _busy ? null : _submitOtp,
            style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(56)),
            child: _busy
                ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                  )
                : const Text('Submit code'),
          ),
        ),
      ];

  List<Widget> _successStep(ThemeData theme) => [
        Row(
          children: [
            Container(
              width: 46,
              height: 46,
              decoration: const BoxDecoration(color: KhejaColors.emerald, shape: BoxShape.circle),
              child: const Icon(Icons.check_rounded, color: Colors.white),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Payment received', style: theme.textTheme.titleLarge),
                  Text(
                    '${widget.amountLabel} · ${widget.what}',
                    style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w700, color: KhejaColors.zinc500),
                  ),
                ],
              ),
            ),
          ],
        ),
        const SizedBox(height: 18),
        SizedBox(
          width: double.infinity,
          child: FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            style: FilledButton.styleFrom(
              backgroundColor: KhejaColors.emerald,
              minimumSize: const Size.fromHeight(56),
            ),
            child: const Text('Continue'),
          ),
        ),
      ];

  List<Widget> _failedStep(ThemeData theme) => [
        Row(
          children: [
            const Icon(Icons.error_outline_rounded, color: KhejaColors.red, size: 26),
            const SizedBox(width: 12),
            Expanded(child: Text('Payment not completed', style: theme.textTheme.titleMedium)),
          ],
        ),
        const SizedBox(height: 8),
        Text(
          _error ?? 'The payment did not go through.',
          style: const TextStyle(fontSize: 13.5, fontWeight: FontWeight.w600, height: 1.5),
        ),
        const SizedBox(height: 16),
        SizedBox(
          width: double.infinity,
          child: FilledButton(
            onPressed: () => setState(() {
              _stage = _Stage.enterPhone;
              _error = null;
            }),
            style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(56)),
            child: const Text('Try again'),
          ),
        ),
        const SizedBox(height: 8),
        SizedBox(
          width: double.infinity,
          child: OutlinedButton.icon(
            onPressed: _check,
            icon: const Icon(Icons.refresh_rounded, size: 18),
            label: const Text('I have paid — check again'),
          ),
        ),
        const SizedBox(height: 10),
        const Text(
          'You are not charged twice: if a payment did go through, checking again '
          'finds it.',
          style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.w600, color: KhejaColors.zinc400, height: 1.45),
        ),
      ];
}

class _Header extends StatelessWidget {
  const _Header({required this.title, required this.what, required this.amountLabel});

  final String title;
  final String what;
  final String amountLabel;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(title, style: theme.textTheme.headlineSmall),
        const SizedBox(height: 4),
        Text(
          what,
          style: const TextStyle(fontWeight: FontWeight.w600, color: KhejaColors.zinc500, height: 1.45),
        ),
        const SizedBox(height: 16),
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            gradient: const LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [KhejaColors.blue, KhejaColors.blueDark],
            ),
            borderRadius: BorderRadius.circular(KhejaRadius.lg),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('AMOUNT TO PAY',
                  style: kEyebrowStyle.copyWith(color: Colors.white.withValues(alpha: 0.8))),
              const SizedBox(height: 4),
              Text(
                amountLabel,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 30,
                  fontWeight: FontWeight.w900,
                  letterSpacing: -1.2,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _Steps extends StatelessWidget {
  const _Steps();

  static const _steps = [
    'An M-Pesa request is sent to your phone',
    'Enter your M-Pesa PIN to approve it',
    'Kheja_Link confirms the payment here',
  ];

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        for (var i = 0; i < _steps.length; i++)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  width: 20,
                  height: 20,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: KhejaColors.blue.withValues(alpha: 0.12),
                    shape: BoxShape.circle,
                  ),
                  child: Text(
                    '${i + 1}',
                    style: const TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w900,
                      color: KhejaColors.blue,
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    _steps[i],
                    style: const TextStyle(
                      fontSize: 12.5,
                      fontWeight: FontWeight.w600,
                      color: KhejaColors.zinc500,
                      height: 1.4,
                    ),
                  ),
                ),
              ],
            ),
          ),
      ],
    );
  }
}

class _SafetyLine extends StatelessWidget {
  const _SafetyLine();

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Icon(Icons.lock_rounded, size: 14, color: KhejaColors.zinc400),
        const SizedBox(width: 8),
        const Expanded(
          child: Text(
            'Kheja_Link never asks for your M-Pesa PIN. You enter it only on your own '
            'phone, in the M-Pesa prompt.',
            style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.w600, color: KhejaColors.zinc400, height: 1.45),
          ),
        ),
      ],
    );
  }
}
