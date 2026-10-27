import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'app_language.dart';

/// Display only: changing this setting never requests or charges for translation.
class ChatDisplayPreferences extends ChangeNotifier {
  static final instance = ChatDisplayPreferences();
  static const storageKey = 'tongyeok.showOtherLanguage';
  bool _showOtherLanguage = true;
  bool get showOtherLanguage => _showOtherLanguage;

  Future<void> initialize() async {
    _showOtherLanguage =
        (await SharedPreferences.getInstance()).getBool(storageKey) ?? true;
  }

  Future<void> setShowOtherLanguage(bool value) async {
    final saved = await (await SharedPreferences.getInstance()).setBool(
      storageKey,
      value,
    );
    if (!saved) throw StateError('display_preference_not_saved');
    _showOtherLanguage = value;
    notifyListeners();
  }
}

class ChatDisplaySettings extends StatefulWidget {
  const ChatDisplaySettings({super.key});
  @override
  State<ChatDisplaySettings> createState() => _ChatDisplaySettingsState();
}

class _ChatDisplaySettingsState extends State<ChatDisplaySettings> {
  bool _saving = false;
  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: ChatDisplayPreferences.instance,
    builder:
        (context, _) => SwitchListTile(
          contentPadding: EdgeInsets.zero,
          title: Text(tr(context, 'showOtherLanguage')),
          subtitle: Text(tr(context, 'showOtherLanguageHelp')),
          value: ChatDisplayPreferences.instance.showOtherLanguage,
          onChanged:
              _saving
                  ? null
                  : (value) async {
                    setState(() => _saving = true);
                    try {
                      await ChatDisplayPreferences.instance
                          .setShowOtherLanguage(value);
                    } catch (_) {
                      if (context.mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(
                            content: Text(tr(context, 'displaySaveFailed')),
                          ),
                        );
                      }
                    } finally {
                      if (mounted) setState(() => _saving = false);
                    }
                  },
        ),
  );
}
