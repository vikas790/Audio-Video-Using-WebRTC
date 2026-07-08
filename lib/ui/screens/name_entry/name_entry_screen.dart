import 'package:flutter/material.dart';

import '../../../config/locator.dart';
import '../../../data/repositories/presence_repository.dart';
import '../../../routing/navigation_service.dart';
import '../../../utils/constant.dart';
import '../../../utils/local_storage.dart';
import '../lobby/lobby_screen.dart';

// First screen — enter display name, no auth
class NameEntryScreen extends StatefulWidget {
  const NameEntryScreen({super.key});

  @override
  State<NameEntryScreen> createState() => _NameEntryScreenState();
}

class _NameEntryScreenState extends State<NameEntryScreen> {
  final _controller = TextEditingController();
  final _formKey = GlobalKey<FormState>();
  bool _isLoading = false;

  static const _textPrimary = Color(0xFF2B2B2B);
  static const _textSecondary = Color(0xFF8A8A8A);
  static const _inputFill = Color(0xFFF4F2F8);

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _onContinue() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() => _isLoading = true);
    final name = _controller.text.trim();
    await LocalStorage.saveIdentity(name);

    try {
      // Write user to Firestore users collection
      final presenceRepo = locator<PresenceRepository>();
      await presenceRepo.setOnline(
        deviceId: LocalStorage.deviceId,
        name: name,
      );
    } catch (e) {
      if (!mounted) return;
      setState(() => _isLoading = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Firebase error: $e')),
      );
      return;
    }

    if (!mounted) return;
    locator<NavigationService>().pushReplacement(const LobbyScreen());
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final primary = theme.colorScheme.primary;

    return Scaffold(
      backgroundColor: const Color(AppConstants.appBackgroundValue),
      body: SafeArea(
        child: Form(
          key: _formKey,
          child: Column(
            children: [
              // Soft purple accent at top
              Container(
                height: 140,
                width: double.infinity,
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [
                      primary.withValues(alpha: 0.18),
                      primary.withValues(alpha: 0.04),
                      Colors.transparent,
                    ],
                  ),
                ),
              ),
              Expanded(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.fromLTRB(28, 0, 28, 32),
                  child: Column(
                    children: [
                      // Hero icon
                      Container(
                        width: 96,
                        height: 96,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          gradient: LinearGradient(
                            begin: Alignment.topLeft,
                            end: Alignment.bottomRight,
                            colors: [
                              primary,
                              primary.withValues(alpha: 0.75),
                            ],
                          ),
                          boxShadow: [
                            BoxShadow(
                              color: primary.withValues(alpha: 0.35),
                              blurRadius: 24,
                              offset: const Offset(0, 10),
                            ),
                          ],
                        ),
                        child: const Icon(
                          Icons.videocam_rounded,
                          color: Colors.white,
                          size: 44,
                        ),
                      ),
                      const SizedBox(height: 32),
                      const Text(
                        'Join the call',
                        style: TextStyle(
                          fontSize: 28,
                          fontWeight: FontWeight.w700,
                          color: _textPrimary,
                          letterSpacing: -0.5,
                        ),
                      ),
                      const SizedBox(height: 10),
                      const Text(
                        'Enter your name to connect\nwith others online',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          fontSize: 16,
                          height: 1.5,
                          color: _textSecondary,
                        ),
                      ),
                      const SizedBox(height: 40),
                      // Name input
                      TextFormField(
                        controller: _controller,
                        textCapitalization: TextCapitalization.words,
                        textInputAction: TextInputAction.done,
                        style: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w500,
                          color: _textPrimary,
                        ),
                        decoration: InputDecoration(
                          hintText: 'Your name',
                          hintStyle: TextStyle(
                            color: _textSecondary.withValues(alpha: 0.7),
                          ),
                          prefixIcon: Icon(
                            Icons.person_outline_rounded,
                            color: primary.withValues(alpha: 0.8),
                          ),
                          filled: true,
                          fillColor: _inputFill,
                          contentPadding: const EdgeInsets.symmetric(
                            horizontal: 20,
                            vertical: 18,
                          ),
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(16),
                            borderSide: BorderSide.none,
                          ),
                          enabledBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(16),
                            borderSide: BorderSide.none,
                          ),
                          focusedBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(16),
                            borderSide: BorderSide(
                              color: primary.withValues(alpha: 0.6),
                              width: 1.5,
                            ),
                          ),
                          errorBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(16),
                            borderSide: const BorderSide(
                              color: Color(0xFFE84C3D),
                            ),
                          ),
                          focusedErrorBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(16),
                            borderSide: const BorderSide(
                              color: Color(0xFFE84C3D),
                              width: 1.5,
                            ),
                          ),
                        ),
                        validator: (value) {
                          if (value == null || value.trim().isEmpty) {
                            return 'Enter a name';
                          }
                          return null;
                        },
                        onFieldSubmitted: (_) => _onContinue(),
                      ),
                      const SizedBox(height: 24),
                      // Continue CTA
                      SizedBox(
                        width: double.infinity,
                        height: 54,
                        child: FilledButton(
                          onPressed: _isLoading ? null : _onContinue,
                          style: FilledButton.styleFrom(
                            backgroundColor: primary,
                            disabledBackgroundColor:
                                primary.withValues(alpha: 0.5),
                            elevation: 0,
                            shadowColor: primary.withValues(alpha: 0.4),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(16),
                            ),
                          ).copyWith(
                            elevation: WidgetStateProperty.resolveWith((states) {
                              if (states.contains(WidgetState.disabled)) {
                                return 0;
                              }
                              return 4;
                            }),
                          ),
                          child: _isLoading
                              ? const SizedBox(
                                  height: 22,
                                  width: 22,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                    color: Colors.white,
                                  ),
                                )
                              : const Row(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: [
                                    Text(
                                      'Continue',
                                      style: TextStyle(
                                        fontSize: 16,
                                        fontWeight: FontWeight.w600,
                                        letterSpacing: 0.3,
                                      ),
                                    ),
                                    SizedBox(width: 8),
                                    Icon(
                                      Icons.arrow_forward_rounded,
                                      size: 20,
                                    ),
                                  ],
                                ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
