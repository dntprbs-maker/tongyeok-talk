import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'utils/languages.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({Key? key}) : super(key: key);

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  final _currentUser = FirebaseAuth.instance.currentUser!;
  final _firestore = FirebaseFirestore.instance;
  String _preferredLanguage = 'English';
  bool _isLoading = false;

  @override
  void initState() {
    super.initState();
    _loadUserSettings();
  }

  Future<void> _loadUserSettings() async {
    setState(() => _isLoading = true);
    try {
      final doc =
          await _firestore.collection('users').doc(_currentUser.uid).get();
      if (doc.exists) {
        final data = doc.data();
        if (data != null && data['preferredLanguage'] != null) {
          _preferredLanguage = data['preferredLanguage'];
        }
      }
    } catch (e) {
      // Handle error if needed
    }
    setState(() => _isLoading = false);
  }

  Future<void> _updateSettings() async {
    setState(() => _isLoading = true);
    try {
      await _firestore.collection('users').doc(_currentUser.uid).update({
        'preferredLanguage': _preferredLanguage,
      });
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Settings updated!')));
    } catch (e) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Error updating settings: $e')));
    }
    setState(() => _isLoading = false);
  }

  @override
  Widget build(BuildContext context) {
    final Size screenSize = MediaQuery.of(context).size;
    final bool isMobile = screenSize.width < 600;

    return Scaffold(
      appBar: AppBar(title: const Text('Settings')),
      body:
          _isLoading
              ? const Center(child: CircularProgressIndicator())
              : Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 600),
                  child: Padding(
                    padding: const EdgeInsets.all(16.0),
                    child: Column(
                      children: [
                        const SizedBox(height: 20),
                        Row(
                          children: [
                            const Text('Preferred Language: '),
                            const SizedBox(width: 10),
                            DropdownButton<String>(
                              value: _preferredLanguage,
                              items:
                                  supportedLanguages.keys.map((langName) {
                                    return DropdownMenuItem(
                                      value: langName,
                                      child: Text(langName),
                                    );
                                  }).toList(),
                              onChanged: (val) {
                                setState(() {
                                  _preferredLanguage = val ?? 'English';
                                });
                              },
                            ),
                          ],
                        ),
                        const SizedBox(height: 40),
                        ElevatedButton(
                          onPressed: _updateSettings,
                          style: ElevatedButton.styleFrom(
                            padding: EdgeInsets.symmetric(
                              horizontal: isMobile ? 20 : 30,
                              vertical: isMobile ? 12 : 16,
                            ),
                          ),
                          child: Text(
                            'Save',
                            style: TextStyle(fontSize: isMobile ? 14 : 16),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
    );
  }
}
