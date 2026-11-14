import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../cloud/cloud.dart';
import '../core/backup.dart';
import '../core/books.dart';
import '../core/money.dart';
import '../ui/widgets.dart';

// =============================================================================
// Login — Vyapar-style welcome: sign in or create an account to keep the books
// in the cloud, or continue offline. After signing in on a fresh phone the
// app offers to restore the latest cloud backup.
// =============================================================================

const _ink = Color(0xFF0A0E26);
const _muted = Color(0xFF6B7094);

TextStyle _j(double size, FontWeight w, Color c, {double? height, double? spacing}) => TextStyle(
      fontFamily: 'Jakarta',
      fontSize: size,
      fontWeight: w,
      fontVariations: [FontVariation('wght', w.value.toDouble())],
      color: c,
      height: height,
      letterSpacing: spacing,
    );

/// Shows the login screen until the user signs in or chooses offline.
class AuthGate extends StatefulWidget {
  final Widget child;
  const AuthGate({super.key, required this.child});
  @override
  State<AuthGate> createState() => _AuthGateState();
}

class _AuthGateState extends State<AuthGate> {
  bool? pass; // null while loading

  @override
  void initState() {
    super.initState();
    _check();
  }

  Future<void> _check() async {
    try {
      await Cloud.load();
      final s = await Books.settings();
      final ok = Cloud.user != null || s['offline_mode'] == '1';
      if (mounted) setState(() => pass = ok);
    } catch (_) {
      if (mounted) setState(() => pass = true);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (pass == null) return const Scaffold(backgroundColor: Color(0xFF1B2163));
    if (pass!) return widget.child;
    return LoginScreen(onDone: () {
      Accounts.sync();
      setState(() => pass = true);
    });
  }
}

class LoginScreen extends StatefulWidget {
  final VoidCallback onDone;
  final bool fromSettings;
  const LoginScreen({super.key, required this.onDone, this.fromSettings = false});
  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  bool register = false;
  bool busy = false;
  bool hide = true;
  String? error;
  final name = TextEditingController();
  final email = TextEditingController();
  final password = TextEditingController();

  @override
  void dispose() {
    name.dispose();
    email.dispose();
    password.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (busy) return;
    if (!Cloud.configured) {
      await _setup();
      if (!Cloud.configured) return;
    }
    setState(() {
      busy = true;
      error = null;
    });
    try {
      if (register) {
        await Cloud.register(name.text, email.text, password.text);
      } else {
        await Cloud.signIn(email.text, password.text);
      }
      HapticFeedback.mediumImpact();
      await Books.setSetting('offline_mode', '0');
      if (!mounted) return;
      await _offerRestore();
      widget.onDone();
    } catch (e) {
      if (mounted) {
        setState(() {
          busy = false;
          error = '$e';
        });
      }
    }
  }

  /// On a fresh phone, offer the newest cloud backup.
  Future<void> _offerRestore() async {
    try {
      // only a phone with no books at all is offered the cloud copy
      if (!await Backup.phoneIsEmpty()) return;
      final list = await Cloud.listBackups();
      if (list.isEmpty || !mounted) return;
      final b = list.first;
      final ok = await showDialog<bool>(
        context: context,
        builder: (c) => AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(26)),
          icon: const Icon(Icons.cloud_download_rounded, color: Color(0xFF4318D2), size: 44),
          title: const Text('Restore your books?'),
          content: Text('A cloud backup from ${prettyDate(ymd(b.created))} was found — '
              '${b.sales} sales, ${b.products} products, ${b.customers} customers.'),
          actions: [
            TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Start fresh')),
            FilledButton(onPressed: () => Navigator.pop(c, true), child: const Text('Restore')),
          ],
        ),
      );
      if (ok != true) return;
      final f = await Cloud.downloadBackup(b);
      await Backup.restore(f);
      if (mounted) toast(context, 'Your books are restored');
    } catch (e) {
      if (mounted) toast(context, '$e', error: true);
    }
  }

  Future<void> _forgot() async {
    if (email.text.trim().isEmpty) {
      setState(() => error = 'Type your email first, then tap Forgot password');
      return;
    }
    try {
      await Cloud.resetPassword(email.text);
      if (mounted) toast(context, 'Password reset link sent to ${email.text.trim()}');
    } catch (e) {
      if (mounted) setState(() => error = '$e');
    }
  }

  Future<void> _offline() async {
    await Books.setSetting('offline_mode', '1');
    widget.onDone();
  }

  Future<void> _setup() async {
    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => const CloudSetupSheet(),
    );
    if (mounted) setState(() {});
  }

  InputDecoration _deco(String hint, IconData icon, {Widget? suffix}) => InputDecoration(
        hintText: hint,
        hintStyle: _j(14, FontWeight.w500, const Color(0xFF9AA0BF)),
        prefixIcon: Icon(icon, color: const Color(0xFF5B2EE0)),
        suffixIcon: suffix,
        filled: true,
        fillColor: const Color(0xFFF6F5FF),
        contentPadding: const EdgeInsets.symmetric(vertical: 16),
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(18), borderSide: BorderSide.none),
        enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(18), borderSide: BorderSide.none),
        focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(18), borderSide: const BorderSide(color: Color(0xFF8B6CF6), width: 1.6)),
      );

  @override
  Widget build(BuildContext context) {
    final mq = MediaQuery.of(context);
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: SystemUiOverlayStyle.light,
      child: Scaffold(
        resizeToAvoidBottomInset: true,
        body: Container(
          decoration: const BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [Color(0xFF1B2163), Color(0xFF3A2BC9), Color(0xFF6A2FF0)],
            ),
          ),
          child: Stack(children: [
            Positioned(
              right: -90,
              top: -70,
              child: Container(
                width: 280,
                height: 280,
                decoration: const BoxDecoration(
                    shape: BoxShape.circle, gradient: RadialGradient(colors: [Color(0x40FFFFFF), Color(0x00FFFFFF)])),
              ),
            ),
            SafeArea(
              child: ListView(padding: const EdgeInsets.fromLTRB(20, 24, 20, 24), children: [
                if (widget.fromSettings)
                  Align(
                    alignment: Alignment.centerLeft,
                    child: IconButton(
                      onPressed: () => Navigator.of(context).pop(),
                      icon: const Icon(Icons.arrow_back_rounded, color: Colors.white),
                    ),
                  ),
                SizedBox(height: mq.size.height * .03),
                Center(
                  child: Container(
                    width: 84,
                    height: 84,
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(26),
                      border: Border.all(color: const Color(0x66FFFFFF), width: 1.5),
                      boxShadow: const [BoxShadow(color: Color(0x55000000), blurRadius: 26, offset: Offset(0, 12), spreadRadius: -8)],
                    ),
                    clipBehavior: Clip.antiAlias,
                    child: Image.asset('assets/home/logo.png', fit: BoxFit.cover),
                  ),
                ),
                const SizedBox(height: 16),
                Center(child: Text('Hisab AI', style: _j(26, FontWeight.w800, Colors.white))),
                const SizedBox(height: 4),
                Center(
                  child: Text('Billing · Stock · Khata — safe in your cloud',
                      style: _j(13, FontWeight.w600, const Color(0xDDFFFFFF))),
                ),
                const SizedBox(height: 18),
                Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                  for (final f in [
                    (Icons.cloud_done_rounded, 'Auto backup'),
                    (Icons.devices_rounded, 'Any phone'),
                    (Icons.lock_rounded, 'Private'),
                  ])
                    Container(
                      margin: const EdgeInsets.symmetric(horizontal: 4),
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                      decoration: BoxDecoration(color: const Color(0x26FFFFFF), borderRadius: BorderRadius.circular(12)),
                      child: Row(mainAxisSize: MainAxisSize.min, children: [
                        Icon(f.$1, color: Colors.white, size: 14),
                        const SizedBox(width: 5),
                        Text(f.$2, style: _j(11, FontWeight.w700, Colors.white)),
                      ]),
                    ),
                ]),
                const SizedBox(height: 22),
                Container(
                  padding: const EdgeInsets.all(18),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(28),
                    boxShadow: const [BoxShadow(color: Color(0x55000000), blurRadius: 30, offset: Offset(0, 16), spreadRadius: -10)],
                  ),
                  child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                    Container(
                      height: 46,
                      padding: const EdgeInsets.all(4),
                      decoration: BoxDecoration(color: const Color(0xFFF0EEFB), borderRadius: BorderRadius.circular(23)),
                      child: Row(children: [
                        for (final t in [(false, 'Sign in'), (true, 'Create account')])
                          Expanded(
                            child: GestureDetector(
                              onTap: () => setState(() {
                                register = t.$1;
                                error = null;
                              }),
                              child: AnimatedContainer(
                                duration: const Duration(milliseconds: 220),
                                alignment: Alignment.center,
                                decoration: BoxDecoration(
                                  borderRadius: BorderRadius.circular(19),
                                  gradient: register == t.$1
                                      ? const LinearGradient(colors: [Color(0xFF6B35EE), Color(0xFF4318D2)])
                                      : null,
                                ),
                                child: Text(t.$2,
                                    style: _j(13.5, FontWeight.w800, register == t.$1 ? Colors.white : const Color(0xFF3A4155))),
                              ),
                            ),
                          ),
                      ]),
                    ),
                    const SizedBox(height: 16),
                    if (register) ...[
                      TextField(
                        controller: name,
                        textCapitalization: TextCapitalization.words,
                        style: _j(15, FontWeight.w600, _ink),
                        decoration: _deco('Your name / shop name', Icons.storefront_rounded),
                      ),
                      const SizedBox(height: 12),
                    ],
                    TextField(
                      controller: email,
                      keyboardType: TextInputType.emailAddress,
                      autofillHints: const [AutofillHints.email],
                      style: _j(15, FontWeight.w600, _ink),
                      decoration: _deco('Email address', Icons.alternate_email_rounded),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: password,
                      obscureText: hide,
                      autofillHints: const [AutofillHints.password],
                      style: _j(15, FontWeight.w600, _ink),
                      onSubmitted: (_) => _submit(),
                      decoration: _deco(
                        register ? 'Create a password (6+ characters)' : 'Password',
                        Icons.lock_outline_rounded,
                        suffix: IconButton(
                          icon: Icon(hide ? Icons.visibility_rounded : Icons.visibility_off_rounded, color: _muted),
                          onPressed: () => setState(() => hide = !hide),
                        ),
                      ),
                    ),
                    if (!register)
                      Align(
                        alignment: Alignment.centerRight,
                        child: TextButton(onPressed: _forgot, child: const Text('Forgot password?')),
                      ),
                    if (error != null)
                      Container(
                        margin: const EdgeInsets.only(top: 6, bottom: 6),
                        padding: const EdgeInsets.all(10),
                        decoration: BoxDecoration(color: const Color(0xFFFFEEEE), borderRadius: BorderRadius.circular(14)),
                        child: Row(children: [
                          const Icon(Icons.error_outline_rounded, color: Color(0xFFDC4545), size: 18),
                          const SizedBox(width: 8),
                          Expanded(child: Text(error!, style: _j(12.5, FontWeight.w700, const Color(0xFFB42318)))),
                        ]),
                      ),
                    const SizedBox(height: 8),
                    GestureDetector(
                      onTap: _submit,
                      child: Container(
                        height: 56,
                        alignment: Alignment.center,
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(28),
                          gradient: const LinearGradient(colors: [Color(0xFF6B35EE), Color(0xFF4318D2)]),
                          boxShadow: const [BoxShadow(color: Color(0x774A17C9), blurRadius: 20, offset: Offset(0, 10), spreadRadius: -8)],
                        ),
                        child: busy
                            ? const SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2.6, color: Colors.white))
                            : Text(register ? 'Create account' : 'Sign in', style: _j(16, FontWeight.w800, Colors.white)),
                      ),
                    ),
                    if (!Cloud.configured) ...[
                      const SizedBox(height: 12),
                      GestureDetector(
                        onTap: _setup,
                        child: Container(
                          padding: const EdgeInsets.all(10),
                          decoration: BoxDecoration(color: const Color(0xFFFFF6E5), borderRadius: BorderRadius.circular(14)),
                          child: Row(children: [
                            const Icon(Icons.settings_suggest_rounded, color: Color(0xFFB06A00), size: 20),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text('Cloud not set up yet — tap to add your Firebase project',
                                  style: _j(12, FontWeight.w700, const Color(0xFF8A5300))),
                            ),
                          ]),
                        ),
                      ),
                    ],
                  ]),
                ),
                const SizedBox(height: 16),
                if (!widget.fromSettings)
                  Center(
                    child: TextButton(
                      onPressed: _offline,
                      child: Text('Continue without account (offline)',
                          style: _j(13.5, FontWeight.w700, const Color(0xE6FFFFFF))),
                    ),
                  ),
                if (Cloud.configured)
                  Center(
                    child: TextButton(
                      onPressed: _setup,
                      child: Text('Cloud setup', style: _j(12, FontWeight.w600, const Color(0xAAFFFFFF))),
                    ),
                  ),
              ]),
            ),
          ]),
        ),
      ),
    );
  }
}

/// Enter the Firebase project's Web API key and project ID.
class CloudSetupSheet extends StatefulWidget {
  const CloudSetupSheet({super.key});
  @override
  State<CloudSetupSheet> createState() => _CloudSetupSheetState();
}

class _CloudSetupSheetState extends State<CloudSetupSheet> {
  final apiKey = TextEditingController();
  final project = TextEditingController(text: Cloud.projectId);

  @override
  void dispose() {
    apiKey.dispose();
    project.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    Widget step(String n, String t) => Padding(
          padding: const EdgeInsets.only(bottom: 6),
          child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Container(
              width: 20,
              height: 20,
              alignment: Alignment.center,
              decoration: const BoxDecoration(shape: BoxShape.circle, color: Color(0xFFEDE7FF)),
              child: Text(n, style: _j(11, FontWeight.w800, const Color(0xFF4318D2))),
            ),
            const SizedBox(width: 8),
            Expanded(child: Text(t, style: _j(12.5, FontWeight.w600, const Color(0xFF323B60)))),
          ]),
        );
    return Container(
      decoration: const BoxDecoration(color: Colors.white, borderRadius: BorderRadius.vertical(top: Radius.circular(28))),
      padding: EdgeInsets.fromLTRB(18, 14, 18, MediaQuery.of(context).viewInsets.bottom + 22),
      child: SingleChildScrollView(
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Center(
            child: Container(width: 44, height: 5, decoration: BoxDecoration(color: const Color(0xFFD5D8EA), borderRadius: BorderRadius.circular(3))),
          ),
          const SizedBox(height: 14),
          Text('Cloud setup', style: _j(20, FontWeight.w800, const Color(0xFF0B0F5E))),
          const SizedBox(height: 4),
          Text('One time — your books are stored in your own Firebase project (free plan).',
              style: _j(12.5, FontWeight.w500, _muted)),
          const SizedBox(height: 12),
          step('1', 'console.firebase.google.com → Add project'),
          step('2', 'Authentication → Sign-in method → turn on Email/Password'),
          step('3', 'Firestore Database → Create database, then Rules → allow each user only their own data'),
          step('4', 'Project settings → copy the Web API key and Project ID below'),
          const SizedBox(height: 10),
          TextField(controller: apiKey, decoration: const InputDecoration(labelText: 'Web API key')),
          const SizedBox(height: 10),
          TextField(controller: project, decoration: const InputDecoration(labelText: 'Project ID')),
          const SizedBox(height: 16),
          GradientButton(
            label: 'Save',
            expand: true,
            fontSize: 16,
            onTap: () async {
              if (apiKey.text.trim().length < 20 || project.text.trim().isEmpty) {
                toast(context, 'Enter both the Web API key and the Project ID', error: true);
                return;
              }
              await Cloud.configure(apiKey.text, project.text);
              if (!context.mounted) return;
              Navigator.of(context).pop();
              toast(context, 'Cloud connected — now sign in or create your account');
            },
          ),
        ]),
      ),
    );
  }
}
