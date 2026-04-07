import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../config/app_config.dart';
import '../providers/webrtc_provider.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  // ── controllers ────────────────────────────────────────────
  final _displayNameCtrl = TextEditingController();
  final _usernameCtrl    = TextEditingController();

  // ── state ──────────────────────────────────────────────────
  String _language    = 'english';
  String _country     = 'India';
  String _userType    = 'deaf';
  String _handUsage   = 'one_hand';
  String _voicePref   = 'neutral';
  String _perfMode    = 'fast';
  bool   _personalization = true;
  bool   _notifications   = true;

  bool _isLoading = false;
  bool _isSaving  = false;
  String? _errorMsg;
  String? _successMsg;

  // ── original username (used as the DB key) ─────────────────
  String _originalUsername = '';

  static const _languages = [
    'english', 'hindi', 'spanish', 'french', 'german', 'portuguese',
    'russian', 'chinese', 'japanese', 'korean', 'arabic', 'turkish',
    'indonesian', 'bengali', 'tamil', 'telugu', 'marathi', 'gujarati',
    'kannada', 'malayalam', 'nepali', 'sinhala', 'urdu', 'vietnamese',
    'thai', 'malay', 'polish', 'dutch', 'swedish', 'other',
  ];
  static const _countries = [
    'India', 'United States', 'United Kingdom', 'Australia', 'Canada',
    'Germany', 'France', 'Japan', 'Brazil', 'Mexico', 'South Africa',
    'Nigeria', 'Egypt', 'Saudi Arabia', 'UAE', 'Pakistan', 'Bangladesh',
    'Sri Lanka', 'Nepal', 'Indonesia', 'Philippines', 'Vietnam', 'Thailand',
    'Malaysia', 'Singapore', 'South Korea', 'China', 'Russia', 'Turkey',
    'Iran', 'Iraq', 'Spain', 'Italy', 'Portugal', 'Netherlands', 'Sweden',
    'Norway', 'Denmark', 'Poland', 'Ukraine', 'Argentina', 'Chile',
    'Colombia', 'Peru', 'Kenya', 'Ghana', 'Ethiopia', 'Tanzania', 'Uganda',
    'Other',
  ];

  @override
  void initState() {
    super.initState();
    _loadPrefs();
  }

  @override
  void dispose() {
    _displayNameCtrl.dispose();
    _usernameCtrl.dispose();
    super.dispose();
  }

  Future<void> _loadPrefs() async {
    setState(() => _isLoading = true);
    final prefs = await SharedPreferences.getInstance();

    _originalUsername = prefs.getString('webrtc_username') ?? '';
    _usernameCtrl.text = _originalUsername;
    _displayNameCtrl.text = prefs.getString('display_name') ?? '';
    _language     = prefs.getString('preferred_language') ?? 'english';
    _country      = prefs.getString('user_country') ?? prefs.getString('country') ?? 'India';
    _userType     = prefs.getString('user_role') == 'caller' ? 'hearing'
                  : prefs.getString('user_type') ?? 'deaf';
    _handUsage    = prefs.getString('hand_usage') ?? 'one_hand';
    _voicePref    = prefs.getString('voice_preference') ?? 'neutral';
    _perfMode     = prefs.getString('performance_mode') ?? 'fast';
    _personalization = prefs.getBool('personalization_enabled') ?? true;
    _notifications   = prefs.getBool('notifications_enabled') ?? true;

    setState(() => _isLoading = false);
  }

  Future<void> _save() async {
    final username    = _usernameCtrl.text.trim();
    final displayName = _displayNameCtrl.text.trim();

    if (username.isEmpty) {
      setState(() { _errorMsg = 'Username cannot be empty.'; _successMsg = null; });
      return;
    }
    if (username.contains(' ')) {
      setState(() { _errorMsg = 'Username must not contain spaces.'; _successMsg = null; });
      return;
    }
    if (username.length < 3) {
      setState(() { _errorMsg = 'Username must be at least 3 characters.'; _successMsg = null; });
      return;
    }

    setState(() { _isSaving = true; _errorMsg = null; _successMsg = null; });

    try {
      // ── 1. Update backend ─────────────────────────────────
      final role = (_userType == 'hearing') ? 'caller' : 'deaf';
      final url  = Uri.parse(
          '${AppConfig.webrtcBackendUrl}/users/$_originalUsername');

      final response = await http.put(
        url,
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'displayName': displayName,
          'language':    _language,
          'country':     _country,
          'role':        role,
        }),
      ).timeout(const Duration(seconds: 10));

      if (response.statusCode != 200) {
        final body = jsonDecode(response.body);
        throw Exception(body['error'] ?? 'Server error ${response.statusCode}');
      }

      // ── 2. Save locally ───────────────────────────────────
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('webrtc_username',    username);
      await prefs.setString('display_name',       displayName);
      await prefs.setString('preferred_language', _language);
      await prefs.setString('country',            _country);
      await prefs.setString('user_country',       _country);
      await prefs.setString('user_type',          _userType);
      await prefs.setString('user_role',           role);
      await prefs.setString('hand_usage',         _handUsage);
      await prefs.setString('voice_preference',   _voicePref);
      await prefs.setString('performance_mode',   _perfMode);
      await prefs.setBool('personalization_enabled', _personalization);
      await prefs.setBool('notifications_enabled',   _notifications);

      // ── 3. Re-register on WebRTC server if username/role changed ──
      if (mounted) {
        context.read<WebRtcProvider>().connectWithRole(username, role);
        _originalUsername = username;
      }

      setState(() => _successMsg = 'Settings saved successfully!');
    } catch (e) {
      setState(() => _errorMsg = e.toString().replaceFirst('Exception: ', ''));
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  // ── helpers ─────────────────────────────────────────────────

  Widget _sectionHeader(String title) {
    return Padding(
      padding: const EdgeInsets.only(top: 28, bottom: 10),
      child: Text(
        title,
        style: const TextStyle(
          color: AppConfig.obPrimary,
          fontSize: 13,
          fontWeight: FontWeight.w700,
          letterSpacing: 0.8,
        ),
      ),
    );
  }

  Widget _card({required Widget child}) {
    return Container(
      decoration: BoxDecoration(
        color: AppConfig.obCard,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppConfig.obBorder, width: 1.5),
      ),
      child: child,
    );
  }

  Widget _textField({
    required TextEditingController controller,
    required String label,
    required IconData icon,
    String? hint,
    bool enabled = true,
  }) {
    return TextField(
      controller: controller,
      enabled: enabled,
      style: const TextStyle(
          color: AppConfig.obTextPrimary, fontSize: 15),
      decoration: InputDecoration(
        labelText: label,
        hintText: hint,
        labelStyle: const TextStyle(color: AppConfig.obTextSecondary),
        hintStyle: const TextStyle(color: AppConfig.obTextSecondary),
        prefixIcon: Icon(icon, color: AppConfig.obPrimary, size: 20),
        filled: true,
        fillColor: AppConfig.obBorder,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide.none,
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide:
              const BorderSide(color: AppConfig.obPrimary, width: 2),
        ),
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      ),
    );
  }

  Widget _dropdownField<T>({
    required String label,
    required T value,
    required List<T> items,
    required String Function(T) itemLabel,
    required void Function(T?) onChanged,
    required IconData icon,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      decoration: BoxDecoration(
        color: AppConfig.obBorder,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          Icon(icon, color: AppConfig.obPrimary, size: 20),
          const SizedBox(width: 10),
          Expanded(
            child: DropdownButtonHideUnderline(
              child: DropdownButton<T>(
                value: value,
                isExpanded: true,
                dropdownColor: Colors.white,
                style: const TextStyle(
                    color: AppConfig.obTextPrimary, fontSize: 15),
                hint: Text(label,
                    style: const TextStyle(
                        color: AppConfig.obTextSecondary)),
                items: items
                    .map((i) => DropdownMenuItem<T>(
                          value: i,
                          child: Text(itemLabel(i)),
                        ))
                    .toList(),
                onChanged: onChanged,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _toggle({
    required String label,
    required String subtitle,
    required bool value,
    required void Function(bool) onChanged,
    required IconData icon,
  }) {
    return ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      leading: Container(
        width: 40,
        height: 40,
        decoration: BoxDecoration(
          color: AppConfig.obBorder,
          borderRadius: BorderRadius.circular(10),
        ),
        child: Icon(icon, color: AppConfig.obPrimary, size: 20),
      ),
      title: Text(label,
          style: const TextStyle(
              color: AppConfig.obTextPrimary,
              fontSize: 14,
              fontWeight: FontWeight.w600)),
      subtitle: Text(subtitle,
          style: const TextStyle(
              color: AppConfig.obTextSecondary, fontSize: 12)),
      trailing: Switch(
        value: value,
        onChanged: onChanged,
        thumbColor: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.selected)) {
            return AppConfig.obPrimary;
          }
          return AppConfig.obTextSecondary;
        }),
        trackColor: WidgetStateProperty.resolveWith((states) {
          return AppConfig.obBorder;
        }),
      ),
    );
  }

  // ── build ────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppConfig.obBackground,
      appBar: AppBar(
        backgroundColor: AppConfig.obBackground,
        elevation: 0,
        scrolledUnderElevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new_rounded,
              color: AppConfig.obPrimaryDark, size: 20),
          onPressed: () => Navigator.of(context).pop(),
        ),
        title: const Text(
          'Settings',
          style: TextStyle(
            color: AppConfig.obTextPrimary,
            fontSize: 20,
            fontWeight: FontWeight.bold,
          ),
        ),
        actions: [
          if (_isSaving)
            const Padding(
              padding: EdgeInsets.only(right: 18),
              child: SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(
                    strokeWidth: 2, color: AppConfig.obPrimary),
              ),
            )
          else
            TextButton(
              onPressed: _save,
              child: const Text(
                'Save',
                style: TextStyle(
                    color: AppConfig.obPrimary,
                    fontWeight: FontWeight.w700,
                    fontSize: 15),
              ),
            ),
        ],
      ),
      body: _isLoading
          ? const Center(
              child: CircularProgressIndicator(color: AppConfig.obPrimary))
          : SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(20, 4, 20, 40),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Status messages
                  if (_successMsg != null)
                    _StatusBanner(
                        message: _successMsg!, isError: false,
                        onDismiss: () => setState(() => _successMsg = null)),
                  if (_errorMsg != null)
                    _StatusBanner(
                        message: _errorMsg!, isError: true,
                        onDismiss: () => setState(() => _errorMsg = null)),

                  // ── Profile ──────────────────────────────
                  _sectionHeader('PROFILE'),
                  _card(
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        children: [
                          // Avatar circle
                          Center(
                            child: Stack(
                              children: [
                                CircleAvatar(
                                  radius: 40,
                                  backgroundColor: AppConfig.obPrimary
                                      .withValues(alpha: 0.12),
                                  child: Text(
                                    _usernameCtrl.text.isEmpty
                                        ? '?'
                                        : _usernameCtrl.text[0]
                                            .toUpperCase(),
                                    style: const TextStyle(
                                      color: AppConfig.obPrimary,
                                      fontSize: 32,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                ),
                                Positioned(
                                  bottom: 0,
                                  right: 0,
                                  child: Container(
                                    width: 26,
                                    height: 26,
                                    decoration: BoxDecoration(
                                      color: AppConfig.obPrimary,
                                      shape: BoxShape.circle,
                                      border: Border.all(
                                          color: Colors.white, width: 2),
                                    ),
                                    child: const Icon(
                                        Icons.edit_rounded,
                                        size: 13,
                                        color: Colors.white),
                                  ),
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(height: 20),
                          _textField(
                            controller: _displayNameCtrl,
                            label: 'Display Name',
                            icon: Icons.badge_outlined,
                            hint: 'How others see you',
                          ),
                          const SizedBox(height: 12),
                          _textField(
                            controller: _usernameCtrl,
                            label: 'Username',
                            icon: Icons.alternate_email_rounded,
                            hint: 'Used for calls',
                          ),
                        ],
                      ),
                    ),
                  ),

                  // ── Identity ─────────────────────────────
                  _sectionHeader('IDENTITY'),
                  _card(
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        children: [
                          _dropdownField<String>(
                            label: 'User Type',
                            value: _userType,
                            items: const ['deaf', 'hearing', 'both'],
                            itemLabel: (v) => switch (v) {
                              'deaf'    => '🧏 Deaf / Hard of Hearing',
                              'hearing' => '🗣️ Hearing User',
                              _         => '🤝 Both',
                            },
                            icon: Icons.person_outline_rounded,
                            onChanged: (v) =>
                                setState(() => _userType = v ?? _userType),
                          ),
                          const SizedBox(height: 12),
                          _dropdownField<String>(
                            label: 'Country',
                            value: _countries.contains(_country)
                                ? _country
                                : 'Other',
                            items: _countries,
                            itemLabel: (v) => v,
                            icon: Icons.public_rounded,
                            onChanged: (v) =>
                                setState(() => _country = v ?? _country),
                          ),
                          const SizedBox(height: 12),
                          _dropdownField<String>(
                            label: 'Language',
                            value: _languages.contains(_language) ? _language : 'other',
                            items: _languages,
                            itemLabel: (v) => switch (v) {
                              'english'    => '🇬🇧 English',
                              'hindi'      => '🇮🇳 Hindi',
                              'spanish'    => '🇪🇸 Spanish',
                              'french'     => '🇫🇷 French',
                              'german'     => '🇩🇪 German',
                              'portuguese' => '🇵🇹 Portuguese',
                              'russian'    => '🇷🇺 Russian',
                              'chinese'    => '🇨🇳 Chinese',
                              'japanese'   => '🇯🇵 Japanese',
                              'korean'     => '🇰🇷 Korean',
                              'arabic'     => '🇸🇦 Arabic',
                              'turkish'    => '🇹🇷 Turkish',
                              'indonesian' => '🇮🇩 Indonesian',
                              'bengali'    => '🇧🇩 Bengali',
                              'tamil'      => '🇮🇳 Tamil',
                              'telugu'     => '🇮🇳 Telugu',
                              'marathi'    => '🇮🇳 Marathi',
                              'gujarati'   => '🇮🇳 Gujarati',
                              'kannada'    => '🇮🇳 Kannada',
                              'malayalam'  => '🇮🇳 Malayalam',
                              'nepali'     => '🇳🇵 Nepali',
                              'sinhala'    => '🇱🇰 Sinhala',
                              'urdu'       => '🇵🇰 Urdu',
                              'vietnamese' => '🇻🇳 Vietnamese',
                              'thai'       => '🇹🇭 Thai',
                              'malay'      => '🇲🇾 Malay',
                              'polish'     => '🇵🇱 Polish',
                              'dutch'      => '🇳🇱 Dutch',
                              'swedish'    => '🇸🇪 Swedish',
                              _            => '🌐 Other',
                            },
                            icon: Icons.translate_rounded,
                            onChanged: (v) =>
                                setState(() => _language = v ?? _language),
                          ),
                        ],
                      ),
                    ),
                  ),

                  // ── Detection ────────────────────────────
                  _sectionHeader('DETECTION'),
                  _card(
                    child: Column(
                      children: [
                        Padding(
                          padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
                          child: _dropdownField<String>(
                            label: 'Hand Usage',
                            value: _handUsage,
                            items: const ['one_hand', 'both_hands'],
                            itemLabel: (v) => v == 'one_hand'
                                ? '✋ One Hand'
                                : '🙌 Both Hands',
                            icon: Icons.back_hand_outlined,
                            onChanged: (v) =>
                                setState(() => _handUsage = v ?? _handUsage),
                          ),
                        ),
                        Padding(
                          padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
                          child: _dropdownField<String>(
                            label: 'Performance Mode',
                            value: _perfMode,
                            items: const ['fast', 'accurate'],
                            itemLabel: (v) => v == 'fast'
                                ? '⚡ Faster Performance'
                                : '🎯 Higher Accuracy',
                            icon: Icons.speed_rounded,
                            onChanged: (v) =>
                                setState(() => _perfMode = v ?? _perfMode),
                          ),
                        ),
                      ],
                    ),
                  ),

                  // ── Voice ────────────────────────────────
                  _sectionHeader('VOICE'),
                  _card(
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: _dropdownField<String>(
                        label: 'TTS Voice',
                        value: _voicePref,
                        items: const ['male', 'female', 'neutral'],
                        itemLabel: (v) => switch (v) {
                          'male'    => '👨 Male Voice',
                          'female'  => '👩 Female Voice',
                          _         => '🧑 Neutral',
                        },
                        icon: Icons.record_voice_over_rounded,
                        onChanged: (v) =>
                            setState(() => _voicePref = v ?? _voicePref),
                      ),
                    ),
                  ),

                  // ── Preferences ──────────────────────────
                  _sectionHeader('PREFERENCES'),
                  _card(
                    child: Column(
                      children: [
                        _toggle(
                          label: 'Smart Personalization',
                          subtitle: 'Improves detection accuracy over time',
                          value: _personalization,
                          icon: Icons.auto_awesome_rounded,
                          onChanged: (v) =>
                              setState(() => _personalization = v),
                        ),
                        Divider(
                            height: 1,
                            color: AppConfig.obBorder,
                            indent: 16,
                            endIndent: 16),
                        _toggle(
                          label: 'Notifications',
                          subtitle: 'Incoming calls and important alerts',
                          value: _notifications,
                          icon: Icons.notifications_outlined,
                          onChanged: (v) =>
                              setState(() => _notifications = v),
                        ),
                      ],
                    ),
                  ),

                  // ── Save button (bottom) ─────────────────
                  const SizedBox(height: 32),
                  SizedBox(
                    width: double.infinity,
                    height: 56,
                    child: ElevatedButton(
                      onPressed: _isSaving ? null : _save,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppConfig.obPrimary,
                        disabledBackgroundColor: AppConfig.obBorder,
                        foregroundColor: Colors.white,
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(14)),
                        elevation: 0,
                      ),
                      child: _isSaving
                          ? const SizedBox(
                              width: 22,
                              height: 22,
                              child: CircularProgressIndicator(
                                  strokeWidth: 2, color: Colors.white))
                          : const Text('Save Changes',
                              style: TextStyle(
                                  fontSize: 16, fontWeight: FontWeight.w700)),
                    ),
                  ),
                ],
              ),
            ),
    );
  }
}

// ─────────────────────────────────────────────────────────────
//  Status banner
// ─────────────────────────────────────────────────────────────

class _StatusBanner extends StatelessWidget {
  final String message;
  final bool isError;
  final VoidCallback onDismiss;

  const _StatusBanner({
    required this.message,
    required this.isError,
    required this.onDismiss,
  });

  @override
  Widget build(BuildContext context) {
    final bg    = isError ? const Color(0xFFFFF0F0) : const Color(0xFFF0FFF4);
    final border = isError ? const Color(0xFFFFCDD2) : const Color(0xFFC8E6C9);
    final icon   = isError ? Icons.error_outline_rounded : Icons.check_circle_outline_rounded;
    final color  = isError ? Colors.red.shade700 : Colors.green.shade700;

    return Container(
      margin: const EdgeInsets.only(bottom: 16, top: 4),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: border),
      ),
      child: Row(
        children: [
          Icon(icon, color: color, size: 20),
          const SizedBox(width: 10),
          Expanded(
              child: Text(message,
                  style: TextStyle(color: color, fontSize: 13))),
          GestureDetector(
            onTap: onDismiss,
            child: Icon(Icons.close_rounded, color: color, size: 18),
          ),
        ],
      ),
    );
  }
}
