import 'package:flutter/material.dart';
import 'auth_service.dart';
import 'utils/languages.dart';

class AuthScreen extends StatefulWidget {
  final bool isSignUp;

  const AuthScreen({Key? key, this.isSignUp = false}) : super(key: key);

  @override
  State<AuthScreen> createState() => _AuthScreenState();
}

class _AuthScreenState extends State<AuthScreen> {
  final AuthService _authService = AuthService();
  final _formKey = GlobalKey<FormState>();
  String _email = '';
  String _password = '';
  String _username = '';
  String _preferredLanguage = 'English';
  bool _isSignUp = false;

  @override
  void initState() {
    super.initState();
    _isSignUp = widget.isSignUp;
  }

  void _toggleForm() {
    setState(() {
      _isSignUp = !_isSignUp;
    });
  }

  Future<void> _submit() async {
    if (_formKey.currentState!.validate()) {
      _formKey.currentState!.save();
      try {
        if (_isSignUp) {
          await _authService.signUp(
            _email,
            _password,
            _username,
            _preferredLanguage,
          );
        } else {
          await _authService.signIn(_email, _password);
        }
        if (!mounted) return;
        Navigator.pushReplacementNamed(context, '/recentConversations');
      } catch (e) {
        if (!mounted) return;
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Error: $e')));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final Size screenSize = MediaQuery.of(context).size;
    final bool isMobile = screenSize.width < 600;

    return Scaffold(
      extendBodyBehindAppBar: true,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        title: Text(_isSignUp ? 'Sign Up' : 'Sign In'),
      ),
      body: Container(
        width: double.infinity,
        height: double.infinity,
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            colors: [Color(0xFF6A82FB), Color(0xFFFC5C7D)],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
        ),
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24.0),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 500),
              child: Card(
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16),
                ),
                elevation: 6,
                child: Padding(
                  padding: const EdgeInsets.all(24.0),
                  child: Form(
                    key: _formKey,
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        ClipRRect(
                          borderRadius: BorderRadius.circular(
                            24,
                          ), // You can adjust the corner radius
                          child: Image.asset(
                            'assets/images/BridgeChat.png',
                            width: isMobile ? 350 : 500,
                            height: isMobile ? 190 : 250,
                            fit: BoxFit.cover,
                          ),
                        ),

                        const SizedBox(height: 16),
                        Text(
                          _isSignUp ? 'Create an Account' : 'Welcome Back',
                          style: Theme.of(context).textTheme.headlineSmall,
                        ),
                        const SizedBox(height: 24),
                        if (_isSignUp)
                          Padding(
                            padding: const EdgeInsets.symmetric(vertical: 8.0),
                            child: TextFormField(
                              style: TextStyle(fontSize: isMobile ? 14 : 16),
                              decoration: const InputDecoration(
                                labelText: 'Username',
                                prefixIcon: Icon(Icons.person),
                              ),
                              onSaved: (value) => _username = value!.trim(),
                              validator:
                                  (value) =>
                                      (value == null || value.isEmpty)
                                          ? 'Enter a username'
                                          : null,
                            ),
                          ),
                        Padding(
                          padding: const EdgeInsets.symmetric(vertical: 8.0),
                          child: TextFormField(
                            style: TextStyle(fontSize: isMobile ? 14 : 16),
                            decoration: const InputDecoration(
                              labelText: 'Email',
                              prefixIcon: Icon(Icons.email),
                            ),
                            onSaved: (value) => _email = value!.trim(),
                            validator:
                                (value) =>
                                    (value == null || value.isEmpty)
                                        ? 'Enter an email'
                                        : null,
                          ),
                        ),
                        Padding(
                          padding: const EdgeInsets.symmetric(vertical: 8.0),
                          child: TextFormField(
                            style: TextStyle(fontSize: isMobile ? 14 : 16),
                            decoration: const InputDecoration(
                              labelText: 'Password',
                              prefixIcon: Icon(Icons.lock),
                            ),
                            obscureText: true,
                            onSaved: (value) => _password = value!.trim(),
                            validator:
                                (value) =>
                                    (value != null && value.length < 6)
                                        ? 'Password too short'
                                        : null,
                          ),
                        ),
                        if (_isSignUp)
                          Padding(
                            padding: const EdgeInsets.symmetric(vertical: 8.0),
                            child: DropdownButtonFormField<String>(
                              value: _preferredLanguage,
                              decoration: const InputDecoration(
                                labelText: 'Preferred Language',
                              ),
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
                          ),
                        const SizedBox(height: 24),
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            ElevatedButton(
                              onPressed: _submit,
                              child: Text(
                                _isSignUp ? 'Sign Up' : 'Sign In',
                                style: TextStyle(fontSize: isMobile ? 14 : 16),
                              ),
                            ),
                            const SizedBox(height: 12),
                            TextButton(
                              onPressed: _toggleForm,
                              child: Text(
                                _isSignUp
                                    ? 'Already have an account? Sign In'
                                    : 'Don’t have an account? Sign Up',
                                style: TextStyle(fontSize: isMobile ? 14 : 16),
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
