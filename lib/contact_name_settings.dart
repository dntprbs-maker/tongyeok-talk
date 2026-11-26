import 'package:flutter/material.dart';

import 'app_language.dart';
import 'contact_names.dart';

Future<void> showContactNameSettings(
  BuildContext context,
  ContactNames contacts,
) => showDialog<void>(
  context: context,
  barrierDismissible: false,
  builder: (_) => _ContactNameSettings(contacts: contacts),
);

class _ContactNameSettings extends StatefulWidget {
  const _ContactNameSettings({required this.contacts});

  final ContactNames contacts;

  @override
  State<_ContactNameSettings> createState() => _ContactNameSettingsState();
}

class _ContactNameSettingsState extends State<_ContactNameSettings> {
  late final _sharing = widget.contacts.readSharing();
  late bool _useContacts = widget.contacts.automaticEnabled;
  bool? _share;
  bool _busy = false;
  bool _error = false;
  bool _denied = false;

  Future<void> _save(bool initialSharing) async {
    setState(() {
      _busy = true;
      _error = false;
      _denied = false;
    });
    try {
      final share = _share ?? initialSharing;
      if (share != initialSharing) await widget.contacts.setSharing(share);
      if (_useContacts) {
        final allowed = await widget.contacts.enableAutomatic();
        if (allowed) widget.contacts.refresh();
        if (!allowed && mounted) {
          setState(() {
            _share = share;
            _useContacts = false;
            _denied = true;
          });
          await widget.contacts.markSetup();
          return;
        }
      } else {
        await widget.contacts.disableAutomatic();
      }
      await widget.contacts.markSetup();
      if (mounted) Navigator.pop(context);
    } catch (_) {
      if (mounted) setState(() => _error = true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => FutureBuilder<bool>(
    future: _sharing,
    builder: (context, state) {
      final sharing = state.data;
      return PopScope(
        canPop: !_busy,
        child: AlertDialog(
          title: Text(tr(context, 'contactNamesSettings')),
          scrollable: true,
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(tr(context, 'contactNamesOptional')),
              CheckboxListTile(
                contentPadding: EdgeInsets.zero,
                value: _useContacts,
                title: Text(tr(context, 'contactNamesUse')),
                subtitle: Text(tr(context, 'contactNamesUseHelp')),
                onChanged:
                    _busy
                        ? null
                        : (value) =>
                            setState(() => _useContacts = value == true),
              ),
              CheckboxListTile(
                contentPadding: EdgeInsets.zero,
                value: _share ?? sharing ?? false,
                title: Text(tr(context, 'contactNamesShare')),
                subtitle: Text(tr(context, 'contactNamesShareHelp')),
                onChanged:
                    _busy || sharing == null
                        ? null
                        : (value) => setState(() => _share = value == true),
              ),
              if (_denied) Text(tr(context, 'contactNamesDenied')),
              if (_error || state.hasError)
                Text(tr(context, 'contactAliasSaveError')),
            ],
          ),
          actions: [
            TextButton(
              onPressed:
                  _busy
                      ? null
                      : () async {
                        await widget.contacts.markSetup();
                        if (context.mounted) Navigator.pop(context);
                      },
              child: Text(tr(context, 'cancel')),
            ),
            FilledButton(
              onPressed: _busy || sharing == null ? null : () => _save(sharing),
              child: Text(tr(context, 'contactAliasSave')),
            ),
          ],
        ),
      );
    },
  );
}
