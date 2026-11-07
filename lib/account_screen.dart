import 'package:flutter/material.dart';
import 'auth_store.dart';
import 'cloud_sync.dart';
import 'design.dart';

class AccountScreen extends StatefulWidget {
  const AccountScreen({super.key, required this.auth, required this.sync});
  final AuthStore auth;
  final CloudSync sync;
  @override
  State<AccountScreen> createState() => _AccountScreenState();
}

class _AccountScreenState extends State<AccountScreen> {
  final _form = GlobalKey<FormState>();
  final _email = TextEditingController();
  final _password = TextEditingController();
  final _confirmation = TextEditingController();
  bool _register = false;
  bool _obscure = true;
  @override
  void initState() {
    super.initState();
    widget.auth.addListener(_refresh);
    widget.sync.addListener(_refresh);
  }

  void _refresh() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    widget.auth.removeListener(_refresh);
    widget.sync.removeListener(_refresh);
    _email.dispose();
    _password.dispose();
    _confirmation.dispose();
    super.dispose();
  }

  Future<void> _emailSignIn() async {
    if (!_form.currentState!.validate()) return;
    if (await widget.auth.emailSignIn(
      _email.text,
      _password.text,
      register: _register,
    )) {
      _password.clear();
      _confirmation.clear();
    } else {
      _showSignInError();
    }
  }

  Future<void> _googleSignIn() async {
    ScaffoldMessenger.of(context).hideCurrentSnackBar();
    if (!await widget.auth.googleSignIn()) _showSignInError();
  }

  void _showSignInError() {
    if (!mounted || widget.auth.error == null) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text(widget.auth.error!),
          duration: const Duration(seconds: 8),
        ),
      );
  }

  @override
  Widget build(BuildContext context) {
    final auth = widget.auth;
    final sync = widget.sync;
    return Scaffold(
      appBar: AppBar(title: const Text('Reader account')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(20, 16, 20, 32),
        children: [
          MotionEntry(
            child: ReaderPanel(
              accent: true,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Image.asset(
                        'assets/brand/seer.webp',
                        width: 48,
                        height: 48,
                      ),
                      const SizedBox(width: 14),
                      Expanded(
                        child: Text(
                          auth.user == null
                              ? 'Your story, everywhere.'
                              : 'Welcome back.',
                          style: const TextStyle(
                            fontSize: 25,
                            fontWeight: FontWeight.w500,
                            letterSpacing: -.8,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 18),
                  Text(
                    auth.email ??
                        'Sign in with your LOTM Reader account to sync your last chapter, reading activity, streaks, XP and achievements with the website.',
                    style: const TextStyle(color: muted, height: 1.5),
                  ),
                ],
              ),
            ),
          ),
          if (auth.user != null) ...[
            MotionEntry(
              delay: 70,
              child: ReaderPanel(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const SectionLabel('Reading activity'),
                    Row(
                      children: [
                        Expanded(
                          child: _stat('${sync.todayPages}', 'Pages today'),
                        ),
                        Expanded(
                          child: _stat(
                            '${sync.chapters.values.fold<int>(0, (a, b) => a + (b as num).toInt())}',
                            'Chapters reached',
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 24),
                    Row(
                      children: [
                        Icon(
                          sync.error != null
                              ? Icons.cloud_off_outlined
                              : Icons.cloud_done_outlined,
                          color: gold,
                          size: 20,
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Text(
                            sync.syncing
                                ? 'Syncing your reading…'
                                : sync.error ??
                                      (sync.pending > 0
                                          ? '${sync.pending} pages waiting to sync'
                                          : 'Your reading is synced'),
                            style: const TextStyle(fontSize: 13, color: muted),
                          ),
                        ),
                      ],
                    ),
                    if (sync.syncing)
                      const Padding(
                        padding: EdgeInsets.only(top: 12),
                        child: LinearProgressIndicator(),
                      ),
                    const SizedBox(height: 12),
                    OutlinedButton.icon(
                      onPressed: sync.syncing ? null : () => sync.synchronize(),
                      icon: const Icon(Icons.sync, size: 18),
                      label: const Text('Sync now'),
                    ),
                  ],
                ),
              ),
            ),
            if (sync.daily.isNotEmpty)
              MotionEntry(
                delay: 120,
                child: ReaderPanel(
                  child: Column(
                    children: [
                      const SectionLabel('Recent days'),
                      for (final day
                          in (sync.daily.keys.toList()
                                ..sort((a, b) => b.compareTo(a)))
                              .take(7))
                        Padding(
                          padding: const EdgeInsets.symmetric(vertical: 7),
                          child: Row(
                            children: [
                              Expanded(
                                child: Text(
                                  day,
                                  style: const TextStyle(color: muted),
                                ),
                              ),
                              Text('${sync.daily[day]} pages'),
                            ],
                          ),
                        ),
                    ],
                  ),
                ),
              ),
            OutlinedButton.icon(
              onPressed: auth.busy ? null : auth.signOut,
              icon: const Icon(Icons.logout, size: 18),
              label: const Text('Sign out'),
            ),
          ] else ...[
            MotionEntry(
              delay: 70,
              child: ReaderPanel(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    if (auth.error != null)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 16),
                        child: Semantics(
                          liveRegion: true,
                          child: Text(
                            auth.error!,
                            style: TextStyle(
                              color: Theme.of(context).colorScheme.error,
                              height: 1.5,
                            ),
                          ),
                        ),
                      ),
                    if (auth.busy)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 16),
                        child: Semantics(
                          liveRegion: true,
                          child: Column(
                            children: [
                              const LinearProgressIndicator(),
                              const SizedBox(height: 8),
                              Text(auth.busyMessage ?? 'Signing in…'),
                            ],
                          ),
                        ),
                      ),
                    SizedBox(
                      height: 52,
                      child: FilledButton.icon(
                        onPressed: auth.busy ? null : _googleSignIn,
                        style: FilledButton.styleFrom(
                          backgroundColor: const Color(0xffedf1f5),
                          foregroundColor: const Color(0xff202730),
                        ),
                        icon: Image.asset(
                          'assets/brand/google_g.png',
                          width: 22,
                          height: 22,
                        ),
                        label: const Text('Continue with Google'),
                      ),
                    ),
                    const Padding(
                      padding: EdgeInsets.symmetric(vertical: 22),
                      child: Row(
                        children: [
                          Expanded(child: Divider()),
                          Padding(
                            padding: EdgeInsets.symmetric(horizontal: 14),
                            child: Text(
                              'or use email',
                              style: TextStyle(color: muted, fontSize: 12),
                            ),
                          ),
                          Expanded(child: Divider()),
                        ],
                      ),
                    ),
                    SegmentedButton<bool>(
                      segments: const [
                        ButtonSegment(value: false, label: Text('Sign in')),
                        ButtonSegment(
                          value: true,
                          label: Text('Create account'),
                        ),
                      ],
                      selected: {_register},
                      onSelectionChanged: auth.busy
                          ? null
                          : (value) => setState(() => _register = value.first),
                    ),
                    const SizedBox(height: 20),
                    AutofillGroup(
                      child: Form(
                        key: _form,
                        child: Column(
                          children: [
                            TextFormField(
                              controller: _email,
                              enabled: !auth.busy,
                              keyboardType: TextInputType.emailAddress,
                              autofillHints: const [AutofillHints.email],
                              textInputAction: TextInputAction.next,
                              decoration: const InputDecoration(
                                labelText: 'Email',
                                prefixIcon: Icon(
                                  Icons.alternate_email,
                                  size: 20,
                                ),
                              ),
                              validator: (v) =>
                                  v != null &&
                                      RegExp(
                                        r'^[^\s@]+@[^\s@]+\.[^\s@]+$',
                                      ).hasMatch(v.trim())
                                  ? null
                                  : 'Enter your email address',
                            ),
                            const SizedBox(height: 14),
                            TextFormField(
                              controller: _password,
                              enabled: !auth.busy,
                              obscureText: _obscure,
                              maxLength: 256,
                              autofillHints: [
                                _register
                                    ? AutofillHints.newPassword
                                    : AutofillHints.password,
                              ],
                              decoration: InputDecoration(
                                labelText: 'Password',
                                counterText: '',
                                prefixIcon: const Icon(
                                  Icons.lock_outline,
                                  size: 20,
                                ),
                                suffixIcon: IconButton(
                                  tooltip: _obscure
                                      ? 'Show password'
                                      : 'Hide password',
                                  onPressed: () =>
                                      setState(() => _obscure = !_obscure),
                                  icon: Icon(
                                    _obscure
                                        ? Icons.visibility_outlined
                                        : Icons.visibility_off_outlined,
                                    size: 20,
                                  ),
                                ),
                              ),
                              validator: (v) => (v?.length ?? 0) >= 8
                                  ? null
                                  : 'Use at least 8 characters',
                            ),
                            AnimatedSize(
                              duration: MediaQuery.disableAnimationsOf(context)
                                  ? Duration.zero
                                  : const Duration(milliseconds: 220),
                              child: _register
                                  ? Padding(
                                      padding: const EdgeInsets.only(top: 14),
                                      child: TextFormField(
                                        controller: _confirmation,
                                        enabled: !auth.busy,
                                        obscureText: true,
                                        maxLength: 256,
                                        decoration: const InputDecoration(
                                          labelText: 'Confirm password',
                                          counterText: '',
                                        ),
                                        validator: (v) => v == _password.text
                                            ? null
                                            : 'The passwords do not match',
                                      ),
                                    )
                                  : const SizedBox.shrink(),
                            ),
                            const SizedBox(height: 20),
                            SizedBox(
                              width: double.infinity,
                              height: 50,
                              child: FilledButton(
                                onPressed: auth.busy ? null : _emailSignIn,
                                child: Text(
                                  _register ? 'Create account' : 'Sign in',
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
          ],
          const Padding(
            padding: EdgeInsets.symmetric(horizontal: 8, vertical: 12),
            child: Text(
              'Reading works without an account. Offline activity, streaks and XP are saved and sync when you reconnect. Downloads, bookmarks, notes, reminders and appearance settings stay on this device; export a backup to move them.',
              style: TextStyle(color: muted, fontSize: 12, height: 1.6),
            ),
          ),
        ],
      ),
    );
  }

  Widget _stat(String value, String label) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text(
        value,
        style: const TextStyle(
          fontSize: 36,
          fontWeight: FontWeight.w300,
          color: gold,
        ),
      ),
      Text(label, style: const TextStyle(color: muted, fontSize: 12)),
    ],
  );
}
