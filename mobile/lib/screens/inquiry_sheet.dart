import 'package:flutter/material.dart';

import '../config/theme.dart';
import '../main.dart';
import '../models/models.dart';
import '../services/kheja_api.dart';
import '../widgets/states.dart';

/// Contact the landlord. No account required — the database allows an anonymous
/// insert into `inquiries` but never an anonymous read, so the details entered
/// here are only ever visible to the listing's owner and the sender.
class InquirySheet extends StatefulWidget {
  const InquirySheet({super.key, required this.property});

  final Property property;

  @override
  State<InquirySheet> createState() => _InquirySheetState();
}

class _InquirySheetState extends State<InquirySheet> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _name;
  late final TextEditingController _email;
  late final TextEditingController _phone;
  late final TextEditingController _message;

  bool _isSending = false;

  @override
  void initState() {
    super.initState();
    final user = khejaApi.currentUser;
    _name = TextEditingController(
      text: (user?.userMetadata?['full_name'] as String?) ?? '',
    );
    _email = TextEditingController(text: user?.email ?? '');
    _phone = TextEditingController(
      text: (user?.userMetadata?['phone'] as String?) ?? '',
    );
    _message = TextEditingController(
      text: 'Hi, I\'m interested in "${widget.property.title}". '
          'Is it still available?',
    );
  }

  @override
  void dispose() {
    _name.dispose();
    _email.dispose();
    _phone.dispose();
    _message.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!(_formKey.currentState?.validate() ?? false)) return;

    // The database enforces this too, but the message here is friendlier.
    if (_email.text.trim().isEmpty && _phone.text.trim().isEmpty) {
      showKhejaSnack(
        context,
        'Leave an email or a phone number so the landlord can reply.',
        isError: true,
      );
      return;
    }

    setState(() => _isSending = true);

    try {
      await khejaApi.sendInquiry(
        propertyId: widget.property.id,
        name: _name.text.trim(),
        message: _message.text.trim(),
        email: _email.text,
        phone: _phone.text,
      );
      if (mounted) Navigator.of(context).pop(true);
    } catch (error) {
      if (!mounted) return;
      setState(() => _isSending = false);
      showKhejaSnack(context, describeError(error), isError: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final insets = MediaQuery.of(context).viewInsets;

    return Padding(
      padding: EdgeInsets.only(bottom: insets.bottom),
      child: Container(
        constraints: BoxConstraints(
          maxHeight: MediaQuery.of(context).size.height * 0.9,
        ),
        decoration: BoxDecoration(
          color: theme.scaffoldBackgroundColor,
          borderRadius:
              const BorderRadius.vertical(top: Radius.circular(KhejaRadius.xxl)),
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
                padding: const EdgeInsets.fromLTRB(24, 22, 24, 24),
                child: Form(
                  key: _formKey,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Ask about this home',
                          style: theme.textTheme.headlineSmall),
                      const SizedBox(height: 8),
                      const Text(
                        'No account needed — just leave a way to reach you.',
                        style: TextStyle(
                          color: KhejaColors.zinc500,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(height: 24),

                      _Field(
                        label: 'Your name',
                        controller: _name,
                        textCapitalization: TextCapitalization.words,
                        validator: (value) {
                          final text = value?.trim() ?? '';
                          if (text.length < 2) return 'Tell the landlord your name';
                          return null;
                        },
                      ),
                      const SizedBox(height: 18),

                      _Field(
                        label: 'Email',
                        controller: _email,
                        keyboardType: TextInputType.emailAddress,
                        hint: 'you@example.com',
                        validator: (value) {
                          final text = value?.trim() ?? '';
                          if (text.isEmpty) return null;
                          final valid = RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$')
                              .hasMatch(text);
                          return valid ? null : 'Enter a valid email address';
                        },
                      ),
                      const SizedBox(height: 18),

                      _Field(
                        label: 'Phone',
                        controller: _phone,
                        keyboardType: TextInputType.phone,
                        hint: '+254 712 345 678',
                        validator: (value) {
                          final text = value?.trim() ?? '';
                          if (text.isEmpty) return null;
                          final digits = text.replaceAll(RegExp(r'\D'), '');
                          return digits.length >= 7
                              ? null
                              : 'Enter a valid phone number';
                        },
                      ),
                      const SizedBox(height: 18),

                      _Field(
                        label: 'Message',
                        controller: _message,
                        maxLines: 4,
                        validator: (value) {
                          final text = value?.trim() ?? '';
                          if (text.length < 10) {
                            return 'Add a short message so the landlord can help';
                          }
                          if (text.length > 2000) {
                            return 'Keep your message under 2000 characters';
                          }
                          return null;
                        },
                      ),
                      const SizedBox(height: 26),

                      FilledButton.icon(
                        onPressed: _isSending ? null : _submit,
                        icon: _isSending
                            ? const SizedBox(
                                width: 18,
                                height: 18,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  color: Colors.white,
                                ),
                              )
                            : const Icon(Icons.send_rounded, size: 19),
                        label: Text(_isSending ? 'Sending…' : 'Send message'),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Field extends StatelessWidget {
  const _Field({
    required this.label,
    required this.controller,
    this.hint,
    this.validator,
    this.keyboardType,
    this.maxLines = 1,
    this.textCapitalization = TextCapitalization.none,
  });

  final String label;
  final TextEditingController controller;
  final String? hint;
  final String? Function(String?)? validator;
  final TextInputType? keyboardType;
  final int maxLines;
  final TextCapitalization textCapitalization;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label.toUpperCase(),
            style: kEyebrowStyle.copyWith(color: KhejaColors.zinc400)),
        const SizedBox(height: 8),
        TextFormField(
          controller: controller,
          validator: validator,
          keyboardType: keyboardType,
          maxLines: maxLines,
          textCapitalization: textCapitalization,
          decoration: InputDecoration(hintText: hint),
        ),
      ],
    );
  }
}
