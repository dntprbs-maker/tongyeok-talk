import 'package:flutter/material.dart';

import 'app_language.dart';

class AccountSwitchMenu extends StatelessWidget {
  const AccountSwitchMenu({
    super.key,
    required this.selected,
    required this.labels,
    required this.tooltip,
    required this.onSelected,
    this.enabled = true,
  });

  final String selected;
  final Map<String, String> labels;
  final String tooltip;
  final ValueChanged<String> onSelected;
  final bool enabled;

  @override
  Widget build(BuildContext context) => PopupMenuButton<String>(
    enabled: enabled,
    tooltip: tooltip,
    onSelected: onSelected,
    itemBuilder:
        (_) => [
          for (final item in labels.entries)
            PopupMenuItem(
              value: item.key,
              child: Row(
                children: [
                  Icon(
                    selected == item.key ? Icons.check : Icons.person_outline,
                    size: 18,
                  ),
                  const SizedBox(width: 8),
                  Text(item.value),
                ],
              ),
            ),
        ],
    child: Material(
      elevation: 3,
      color: Theme.of(context).colorScheme.surface,
      borderRadius: BorderRadius.circular(22),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.swap_horiz, size: 18),
            const SizedBox(width: 4),
            Text(labels[selected] ?? labels.values.last),
            const Icon(Icons.arrow_drop_down, size: 18),
          ],
        ),
      ),
    ),
  );
}

class DisplayLanguageSwitcher extends StatelessWidget {
  const DisplayLanguageSwitcher({super.key, required this.uid});

  final String uid;

  @override
  Widget build(BuildContext context) {
    final language = LanguageScope.of(context);
    return AccountSwitchMenu(
      selected: language.displayCode,
      labels: const {'ko': '한국어', 'mn': 'Монгол хэл'},
      tooltip: tr(context, 'interfaceLanguage'),
      onSelected: (code) => language.selectDisplayLanguage(uid, code),
    );
  }
}
