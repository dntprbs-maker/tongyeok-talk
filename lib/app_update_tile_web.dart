import 'dart:js_interop';

import 'package:flutter/material.dart';

import 'app_language.dart';

@JS('tongyeokInstalledVersion')
external JSArray<JSString>? get _installed;

@JS('tongyeokOpenAppUpdate')
external JSFunction? get _open;

@JS('addEventListener')
external void _listen(JSString type, JSFunction callback);

@JS('removeEventListener')
external void _unlisten(JSString type, JSFunction callback);

class AppUpdateTile extends StatefulWidget {
  const AppUpdateTile({super.key});

  @override
  State<AppUpdateTile> createState() => _AppUpdateTileState();
}

class _AppUpdateTileState extends State<AppUpdateTile> {
  static const _readyEvent = 'tongyeok-app-update-ready';
  late final JSFunction _ready;

  @override
  void initState() {
    super.initState();
    _ready = ((JSAny? _) => setState(() {})).toJS;
    _listen(_readyEvent.toJS, _ready);
  }

  @override
  void dispose() {
    _unlisten(_readyEvent.toJS, _ready);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final installed = _installed?.toDart;
    final open = _open;
    if (installed == null || open == null) return const SizedBox.shrink();
    final mn = LanguageScope.of(context).displayCode == 'mn';
    final version = installed[0].toDart;
    final build = installed[1].toDart;
    final colors = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.only(top: 16),
      child: ListTile(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        tileColor: colors.primaryContainer,
        textColor: colors.onPrimaryContainer,
        title: Text(mn ? 'Апп шинэчлэх' : '앱 업데이트'),
        subtitle: Text(
          mn ? 'Одоогийн $version · Билд $build' : '현재 $version · 빌드 $build',
        ),
        trailing: const Icon(Icons.chevron_right),
        onTap: () => open.callAsFunction(null, mn.toJS),
      ),
    );
  }
}
