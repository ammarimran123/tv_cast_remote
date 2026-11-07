import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../app.dart';

Future<void> showPairingDialog(BuildContext context) => showDialog<void>(
  context: context,
  barrierDismissible: false,
  builder: (_) => const _PairingDialog(),
);

class _PairingDialog extends StatefulWidget {
  const _PairingDialog();

  @override
  State<_PairingDialog> createState() => _PairingDialogState();
}

class _PairingDialogState extends State<_PairingDialog> {
  final _code = TextEditingController();
  String? _error;
  bool _busy = false;

  Future<void> _submit() async {
    final code = _code.text.trim();
    if (code.length != 6) {
      setState(() => _error = 'Enter all 6 characters.');
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    final err = await conn.submitPairingCode(code);
    if (!mounted) return;
    if (err == null) {
      Navigator.of(context).pop();
    } else {
      setState(() {
        _busy = false;
        _error = err;
        _code.clear();
      });
    }
  }

  @override
  void dispose() {
    _code.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return AlertDialog(
      icon: Icon(Icons.pin_outlined, color: cs.primary, size: 36),
      title: const Text('Pair with your TV'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            'A 6-character code is now showing on ${conn.device?.name ?? 'your TV'}. Enter it below.',
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 20),
          TextField(
            controller: _code,
            autofocus: true,
            enabled: !_busy,
            maxLength: 6,
            textAlign: TextAlign.center,
            textCapitalization: TextCapitalization.characters,
            style: const TextStyle(
              fontSize: 28,
              letterSpacing: 10,
              fontWeight: FontWeight.w700,
            ),
            inputFormatters: [
              FilteringTextInputFormatter.allow(RegExp('[0-9a-fA-F]')),
              TextInputFormatter.withFunction(
                (o, n) => n.copyWith(text: n.text.toUpperCase()),
              ),
            ],
            decoration: InputDecoration(
              counterText: '',
              hintText: '••••••',
              errorText: _error,
              errorMaxLines: 3,
            ),
            onChanged: (v) {
              if (v.length == 6) _submit();
            },
            onSubmitted: (_) => _submit(),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: _busy
              ? null
              : () {
                  conn.cancelPairing();
                  Navigator.of(context).pop();
                },
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: _busy ? null : _submit,
          child: _busy
              ? const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Text('Pair'),
        ),
      ],
    );
  }
}
