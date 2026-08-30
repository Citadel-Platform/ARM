import 'package:arm_tooling_core/arm_tooling_core.dart';
import 'package:flutter/material.dart';

import 'arm_client.dart';

/// The button an error dialog puts beside "Close".
///
/// The whole point of it: an end user who has just hit a fault can say what
/// they were doing and how to reach them, and that pegs the case log and the
/// fingerprint already captured to a person and a session. Without it, the
/// evidence exists and nobody knows who it happened to.
class ArmOpenTicketButton extends StatelessWidget {
  const ArmOpenTicketButton({
    required this.client,
    this.capture,
    this.title = 'Open support ticket',
    this.onOpened,
    super.key,
  });

  final ArmClient client;

  /// The case log this ticket is about, when the dialog was raised by one.
  final ArmCaptureResult? capture;
  final String title;

  /// What to do with the ticket id — usually showing it, so the person has
  /// something to quote.
  final void Function(String ticketId)? onOpened;

  @override
  Widget build(BuildContext context) {
    return TextButton(
      onPressed: () async {
        final String? ticketId = await showArmSupportTicketDialog(
          context: context,
          client: client,
          capture: capture,
        );
        if (ticketId != null) onOpened?.call(ticketId);
      },
      child: Text(title),
    );
  }
}

/// Asks for a way to reach the person back, and opens the ticket.
///
/// Returns the ticket id, or null if they closed it. The contact field is
/// optional on purpose: somebody who does not want to leave an address should
/// still be able to say what happened, and a required field would mostly
/// collect invented ones.
Future<String?> showArmSupportTicketDialog({
  required BuildContext context,
  required ArmClient client,
  ArmCaptureResult? capture,
  String? initialTitle,
}) {
  return showDialog<String>(
    context: context,
    builder: (BuildContext dialogContext) => _ArmSupportTicketDialog(
      client: client,
      capture: capture,
      initialTitle: initialTitle,
    ),
  );
}

class _ArmSupportTicketDialog extends StatefulWidget {
  const _ArmSupportTicketDialog({
    required this.client,
    this.capture,
    this.initialTitle,
  });

  final ArmClient client;
  final ArmCaptureResult? capture;
  final String? initialTitle;

  @override
  State<_ArmSupportTicketDialog> createState() =>
      _ArmSupportTicketDialogState();
}

class _ArmSupportTicketDialogState extends State<_ArmSupportTicketDialog> {
  late final TextEditingController _title = TextEditingController(
    text: widget.initialTitle ?? '',
  );
  final TextEditingController _description = TextEditingController();
  final TextEditingController _contact = TextEditingController();
  bool _sending = false;
  String? _failure;

  @override
  void dispose() {
    _title.dispose();
    _description.dispose();
    _contact.dispose();
    super.dispose();
  }

  bool get _valid =>
      _title.text.trim().isNotEmpty && _description.text.trim().isNotEmpty;

  Future<void> _send() async {
    setState(() {
      _sending = true;
      _failure = null;
    });
    try {
      final String ticketId = await widget.client.openSupportTicket(
        title: _title.text.trim(),
        description: _description.text.trim(),
        contact: _contact.text.trim().isEmpty ? null : _contact.text.trim(),
        capture: widget.capture,
      );
      if (!mounted) return;
      Navigator.of(context).pop(ticketId);
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _sending = false;
        // Said plainly, and the words are still in the boxes. A dialog that
        // closed on failure would have thrown away what somebody wrote.
        _failure =
            'The ticket could not be opened. Nothing has been sent, and what '
            'you wrote is still here.';
      });
      debugPrint('ARM ticket failed: $error');
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Open support ticket'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            TextField(
              controller: _title,
              enabled: !_sending,
              decoration: const InputDecoration(labelText: 'What went wrong'),
              onChanged: (_) => setState(() {}),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _description,
              enabled: !_sending,
              minLines: 3,
              maxLines: 8,
              decoration: const InputDecoration(
                labelText: 'What were you doing',
              ),
              onChanged: (_) => setState(() {}),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _contact,
              enabled: !_sending,
              decoration: const InputDecoration(
                labelText: 'Email or phone (optional)',
                helperText: 'So somebody can write back about this.',
              ),
            ),
            if (widget.capture case final ArmCaptureResult capture) ...<Widget>[
              const SizedBox(height: 12),
              Text(
                // The technical detail is already captured; the person is told
                // it travels with the ticket rather than being asked for it.
                'The error report already recorded'
                '${capture.caseIdExposed ? ' (${capture.caseId})' : ''} will '
                'be attached to this ticket.',
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ],
            if (_failure case final String failure) ...<Widget>[
              const SizedBox(height: 12),
              Text(
                failure,
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
            ],
          ],
        ),
      ),
      actions: <Widget>[
        TextButton(
          onPressed: _sending ? null : () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: !_valid || _sending ? null : _send,
          child: Text(_sending ? 'Sending…' : 'Open ticket'),
        ),
      ],
    );
  }
}
