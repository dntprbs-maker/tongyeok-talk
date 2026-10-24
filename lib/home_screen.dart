import 'package:flutter/material.dart';
import 'app_language.dart';
import 'brand.dart';

class HomeScreen extends StatelessWidget {
  const HomeScreen({super.key});
  @override
  Widget build(BuildContext context) => Scaffold(
    body: SafeArea(
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 480),
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(28),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  tr(context, 'language'),
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.labelLarge,
                ),
                const SizedBox(height: 10),
                const LanguagePicker(),
                const SizedBox(height: 40),
                const BrandHeader(),
                const SizedBox(height: 28),
                Text(
                  tr(context, 'welcome'),
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.titleLarge,
                ),
                const SizedBox(height: 12),
                Text(
                  tr(context, 'intro'),
                  textAlign: TextAlign.center,
                  style: const TextStyle(height: 1.6, color: Colors.black54),
                ),
                const SizedBox(height: 36),
                FilledButton(
                  onPressed:
                      () => Navigator.pushNamed(
                        context,
                        '/auth',
                        arguments: false,
                      ),
                  child: Text(tr(context, 'signIn')),
                ),
                const SizedBox(height: 12),
                OutlinedButton(
                  onPressed:
                      () => Navigator.pushNamed(
                        context,
                        '/auth',
                        arguments: true,
                      ),
                  child: Text(tr(context, 'signUp')),
                ),
              ],
            ),
          ),
        ),
      ),
    ),
  );
}
