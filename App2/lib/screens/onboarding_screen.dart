import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../config/app_config.dart';
import '../providers/webrtc_provider.dart';
import '../screens/caller_home_screen.dart';
import '../screens/emergency_contacts_onboarding_screen.dart';

// ── Data ──────────────────────────────────────────────────────────────────────

class _Country {
  final String flag;
  final String name;
  const _Country(this.flag, this.name);
}

class _Language {
  final String flag;
  final String name;
  final String code;
  const _Language(this.flag, this.name, this.code);
}

const List<_Country> _kCountries = [
  _Country('🇮🇳', 'India'),
  _Country('🇺🇸', 'United States'),
  _Country('🇬🇧', 'United Kingdom'),
  _Country('🇦🇺', 'Australia'),
  _Country('🇨🇦', 'Canada'),
  _Country('🇩🇪', 'Germany'),
  _Country('🇫🇷', 'France'),
  _Country('🇯🇵', 'Japan'),
  _Country('🇧🇷', 'Brazil'),
  _Country('🇲🇽', 'Mexico'),
  _Country('🇿🇦', 'South Africa'),
  _Country('🇳🇬', 'Nigeria'),
  _Country('🇪🇬', 'Egypt'),
  _Country('🇸🇦', 'Saudi Arabia'),
  _Country('🇦🇪', 'UAE'),
  _Country('🇵🇰', 'Pakistan'),
  _Country('🇧🇩', 'Bangladesh'),
  _Country('🇱🇰', 'Sri Lanka'),
  _Country('🇳🇵', 'Nepal'),
  _Country('🇮🇩', 'Indonesia'),
  _Country('🇵🇭', 'Philippines'),
  _Country('🇻🇳', 'Vietnam'),
  _Country('🇹🇭', 'Thailand'),
  _Country('🇲🇾', 'Malaysia'),
  _Country('🇸🇬', 'Singapore'),
  _Country('🇰🇷', 'South Korea'),
  _Country('🇨🇳', 'China'),
  _Country('🇷🇺', 'Russia'),
  _Country('🇹🇷', 'Turkey'),
  _Country('🇮🇷', 'Iran'),
  _Country('🇮🇶', 'Iraq'),
  _Country('🇪🇸', 'Spain'),
  _Country('🇮🇹', 'Italy'),
  _Country('🇵🇹', 'Portugal'),
  _Country('🇳🇱', 'Netherlands'),
  _Country('🇸🇪', 'Sweden'),
  _Country('🇳🇴', 'Norway'),
  _Country('🇩🇰', 'Denmark'),
  _Country('🇵🇱', 'Poland'),
  _Country('🇺🇦', 'Ukraine'),
  _Country('🇦🇷', 'Argentina'),
  _Country('🇨🇱', 'Chile'),
  _Country('🇨🇴', 'Colombia'),
  _Country('🇵🇪', 'Peru'),
  _Country('🇰🇪', 'Kenya'),
  _Country('🇬🇭', 'Ghana'),
  _Country('🇪🇹', 'Ethiopia'),
  _Country('🇹🇿', 'Tanzania'),
  _Country('🇺🇬', 'Uganda'),
  _Country('🌍', 'Other'),
];

const List<_Language> _kLanguages = [
  _Language('🇬🇧', 'English', 'english'),
  _Language('🇮🇳', 'Hindi', 'hindi'),
  _Language('🇪🇸', 'Spanish', 'spanish'),
  _Language('🇫🇷', 'French', 'french'),
  _Language('🇩🇪', 'German', 'german'),
  _Language('🇵🇹', 'Portuguese', 'portuguese'),
  _Language('🇷🇺', 'Russian', 'russian'),
  _Language('🇨🇳', 'Chinese (Mandarin)', 'chinese'),
  _Language('🇯🇵', 'Japanese', 'japanese'),
  _Language('🇰🇷', 'Korean', 'korean'),
  _Language('🇸🇦', 'Arabic', 'arabic'),
  _Language('🇹🇷', 'Turkish', 'turkish'),
  _Language('🇮🇩', 'Indonesian', 'indonesian'),
  _Language('🇮🇳', 'Bengali', 'bengali'),
  _Language('🇮🇳', 'Tamil', 'tamil'),
  _Language('🇮🇳', 'Telugu', 'telugu'),
  _Language('🇮🇳', 'Marathi', 'marathi'),
  _Language('🇮🇳', 'Gujarati', 'gujarati'),
  _Language('🇮🇳', 'Kannada', 'kannada'),
  _Language('🇮🇳', 'Malayalam', 'malayalam'),
  _Language('🇳🇵', 'Nepali', 'nepali'),
  _Language('🇱🇰', 'Sinhala', 'sinhala'),
  _Language('🇵🇰', 'Urdu', 'urdu'),
  _Language('🇻🇳', 'Vietnamese', 'vietnamese'),
  _Language('🇹🇭', 'Thai', 'thai'),
  _Language('🇲🇾', 'Malay', 'malay'),
  _Language('🇵🇱', 'Polish', 'polish'),
  _Language('🇳🇱', 'Dutch', 'dutch'),
  _Language('🇸🇪', 'Swedish', 'swedish'),
  _Language('🌐', 'Other', 'other'),
];

// ── Main screen ───────────────────────────────────────────────────────────────

class OnboardingScreen extends StatefulWidget {
  const OnboardingScreen({super.key});

  @override
  State<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends State<OnboardingScreen>
    with SingleTickerProviderStateMixin {
  final PageController _pageCtrl = PageController();

  // Step 1 — role + username
  String? _role;
  final TextEditingController _usernameCtrl = TextEditingController();
  String? _usernameError;

  // Step 2 — country
  String? _country;
  String _countrySearch = '';

  // Step 3 — language
  String? _language;
  String _languageSearch = '';

  bool _isLoading = false;
  late final AnimationController _floatController;

  @override
  void initState() {
    super.initState();
    _floatController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 4),
    )..repeat(reverse: true);
  }

  @override
  void dispose() {
    _floatController.dispose();
    _usernameCtrl.dispose();
    _pageCtrl.dispose();
    super.dispose();
  }

  // ── Navigation ────────────────────────────────────────────────────────────

  void _goTo(int page) {
    _pageCtrl.animateToPage(
      page,
      duration: const Duration(milliseconds: 350),
      curve: Curves.easeOutCubic,
    );
  }

  // Page indices: 0=role+username, 1=reaction1, 2=country, 3=reaction2, 4=language
  void _step1Continue() {
    if (_role == null) return;
    final username = _usernameCtrl.text.trim();
    if (username.isEmpty) {
      setState(() => _usernameError = 'Please enter a username.');
      return;
    }
    if (username.contains(' ')) {
      setState(() => _usernameError = 'No spaces allowed.');
      return;
    }
    if (username.length < 3) {
      setState(() => _usernameError = 'At least 3 characters.');
      return;
    }
    HapticFeedback.lightImpact();
    setState(() => _usernameError = null);
    _goTo(1); // → reaction page 1
  }

  void _step2Continue() {
    if (_country == null) return;
    HapticFeedback.lightImpact();
    _goTo(3); // → reaction page 2
  }

  // ── Finish ────────────────────────────────────────────────────────────────

  Future<void> _confirm() async {
    if (_role == null || _isLoading) return;
    HapticFeedback.lightImpact();
    setState(() => _isLoading = true);

    final role     = _role!;
    final username = _usernameCtrl.text.trim();
    final country  = _country ?? 'Other';
    final language = _language ?? 'english';

    if (!mounted) return;
    if (role == 'caller') {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('user_role', role);
      await prefs.setBool('onboarding_done', true);
      await prefs.setString('webrtc_username', username);
      await prefs.setString('user_country', country);
      await prefs.setString('country', country);
      await prefs.setString('preferred_language', language);
      if (!mounted) return;
      context.read<WebRtcProvider>().connectWithRole(username, role);
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(builder: (_) => const CallerHomeScreen()),
      );
      return;
    }

    Navigator.pushReplacement(
      context,
      MaterialPageRoute(
        builder: (_) => EmergencyContactsOnboardingScreen(
          role: role,
          username: username,
          country: country,
          language: language,
        ),
      ),
    );
  }

  // ── Build ─────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      child: Scaffold(
        backgroundColor: AppConfig.obBackground,
        body: SafeArea(
          child: Stack(
            children: [
              const Positioned(
                top: -80,
                right: -60,
                child: _GlowOrb(size: 200, color: Color(0x223AE374)),
              ),
              const Positioned(
                bottom: 100,
                left: -60,
                child: _GlowOrb(size: 160, color: Color(0x1595DE28)),
              ),
              PageView(
                controller: _pageCtrl,
                physics: const NeverScrollableScrollPhysics(),
                children: [
                  // Page 0 — role + username
                  _Step1RoleUsername(
                    floatController: _floatController,
                    role: _role,
                    usernameCtrl: _usernameCtrl,
                    usernameError: _usernameError,
                    onRoleSelect: (r) => setState(() => _role = r),
                    onUsernameChanged: () {
                      if (_usernameError != null) {
                        setState(() => _usernameError = null);
                      }
                    },
                    onContinue: _step1Continue,
                  ),
                  // Page 1 — reaction after step 1
                  _MascotReactionPage(
                    comment: 'Great choice, ${_usernameCtrl.text.trim().isEmpty ? 'friend' : _usernameCtrl.text.trim()}! 🎉\nLet\'s learn a bit more about you.',
                    onContinue: () => _goTo(2),
                  ),
                  // Page 2 — country
                  _Step2Country(
                    selected: _country,
                    search: _countrySearch,
                    onBack: () => _goTo(0),
                    onSearchChanged: (v) => setState(() => _countrySearch = v),
                    onSelect: (c) => setState(() => _country = c),
                    onContinue: _step2Continue,
                  ),
                  // Page 3 — reaction after step 2
                  _MascotReactionPage(
                    comment: 'Awesome! ${_country ?? 'Your country'} — great place! 🌍\nOne last question…',
                    onContinue: () => _goTo(4),
                  ),
                  // Page 4 — language
                  _Step3Language(
                    selected: _language,
                    search: _languageSearch,
                    isLoading: _isLoading,
                    onBack: () => _goTo(2),
                    onSearchChanged: (v) => setState(() => _languageSearch = v),
                    onSelect: (l) => setState(() => _language = l),
                    onConfirm: _confirm,
                  ),
                ],
              ),
              if (_isLoading)
                const ColoredBox(
                  color: Colors.black26,
                  child: Center(
                    child: CircularProgressIndicator(color: AppConfig.obPrimary),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

// ── Step 1: Role + Username ───────────────────────────────────────────────────

class _Step1RoleUsername extends StatelessWidget {
  final AnimationController floatController;
  final String? role;
  final TextEditingController usernameCtrl;
  final String? usernameError;
  final void Function(String) onRoleSelect;
  final VoidCallback onUsernameChanged;
  final VoidCallback onContinue;

  const _Step1RoleUsername({
    required this.floatController,
    required this.role,
    required this.usernameCtrl,
    required this.usernameError,
    required this.onRoleSelect,
    required this.onUsernameChanged,
    required this.onContinue,
  });

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(24, 16, 24, 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _StepBar(current: 0, total: 3),
          const SizedBox(height: 18),

          // Brand
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Container(
                width: 34,
                height: 34,
                decoration: BoxDecoration(
                  color: AppConfig.obPrimary,
                  borderRadius: BorderRadius.circular(11),
                ),
                child: const Icon(Icons.bolt_rounded,
                    color: Color(0xFF13210B), size: 18),
              ),
              const SizedBox(width: 10),
              const Text(
                'VAANI',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 17,
                  fontWeight: FontWeight.w900,
                  letterSpacing: 2.6,
                ),
              ),
            ],
          ),

          const SizedBox(height: 20),

          // Mascot + bubble
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              AnimatedBuilder(
                animation: floatController,
                builder: (_, child) => Transform.translate(
                  offset: Offset(
                      0, math.sin(floatController.value * math.pi * 2) * 7),
                  child: child,
                ),
                child: Container(
                  width: 74,
                  height: 74,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: const Color(0xFF202B30),
                    border:
                        Border.all(color: AppConfig.obPrimary, width: 2.5),
                    boxShadow: [
                      BoxShadow(
                        color: AppConfig.obPrimary.withValues(alpha: 0.22),
                        blurRadius: 18,
                        spreadRadius: 1,
                      ),
                    ],
                  ),
                  child: ClipOval(
                    child: Image.asset('assets/questineers.gif',
                        fit: BoxFit.cover),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              const Expanded(
                  child: _QuestionBubble(message: 'Who are you? 👋')),
            ],
          ),

          const SizedBox(height: 6),
          Text(
            'Choose your role — you only do this once.',
            style: TextStyle(
              color: AppConfig.obTextSecondary.withValues(alpha: 0.8),
              fontSize: 12.5,
              height: 1.5,
              fontWeight: FontWeight.w500,
            ),
          ),

          const SizedBox(height: 18),

          // Role cards
          _RoleCard(
            value: 'deaf',
            selected: role,
            emoji: '🤟',
            title: 'Disabled Person',
            subtitle:
                'Deaf / hard of hearing — sign detection, speech translation & calls',
            accentColor: AppConfig.obPrimary,
            onTap: () => onRoleSelect('deaf'),
          ),
          const SizedBox(height: 10),
          _RoleCard(
            value: 'caller',
            selected: role,
            emoji: '👂',
            title: 'Normal Person',
            subtitle:
                'Hearing user — audio & video calls with automatic sign translation',
            accentColor: const Color(0xFF42C68C),
            onTap: () => onRoleSelect('caller'),
          ),

          const SizedBox(height: 20),

          // Username
          AnimatedOpacity(
            opacity: role != null ? 1.0 : 0.38,
            duration: const Duration(milliseconds: 250),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Choose a username',
                  style: TextStyle(
                    color: AppConfig.obTextPrimary,
                    fontSize: 13.5,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 7),
                Container(
                  decoration: BoxDecoration(
                    color: AppConfig.obCard,
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(
                      color: usernameError != null
                          ? Colors.redAccent
                          : AppConfig.obBorder,
                      width: 1.4,
                    ),
                  ),
                  child: TextField(
                    controller: usernameCtrl,
                    enabled: role != null,
                    onChanged: (_) => onUsernameChanged(),
                    textInputAction: TextInputAction.done,
                    onSubmitted: (_) => onContinue(),
                    style: const TextStyle(
                      color: AppConfig.obTextPrimary,
                      fontSize: 15,
                      fontWeight: FontWeight.w600,
                    ),
                    decoration: InputDecoration(
                      hintText: 'e.g. prantik_1',
                      hintStyle: TextStyle(
                        color: AppConfig.obTextSecondary.withValues(alpha: 0.5),
                        fontSize: 14,
                      ),
                      prefixIcon: const Icon(Icons.person_rounded,
                          color: AppConfig.obTextSecondary, size: 20),
                      border: InputBorder.none,
                      contentPadding: const EdgeInsets.symmetric(
                          horizontal: 16, vertical: 15),
                      errorText: usernameError,
                      errorStyle: const TextStyle(
                          color: Colors.redAccent, fontSize: 11.5),
                    ),
                  ),
                ),
              ],
            ),
          ),

          const SizedBox(height: 24),

          _PillButton(
            label: 'CONTINUE',
            enabled: role != null,
            isLoading: false,
            onPressed: onContinue,
          ),
          const SizedBox(height: 12),
        ],
      ),
    );
  }
}

// ── Step 2: Country ───────────────────────────────────────────────────────────

class _Step2Country extends StatefulWidget {
  final String? selected;
  final String search;
  final VoidCallback onBack;
  final void Function(String) onSearchChanged;
  final void Function(String) onSelect;
  final VoidCallback onContinue;

  const _Step2Country({
    required this.selected,
    required this.search,
    required this.onBack,
    required this.onSearchChanged,
    required this.onSelect,
    required this.onContinue,
  });

  @override
  State<_Step2Country> createState() => _Step2CountryState();
}

class _Step2CountryState extends State<_Step2Country> {
  final TextEditingController _ctrl = TextEditingController();

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final filtered = widget.search.isEmpty
        ? _kCountries
        : _kCountries
            .where((c) =>
                c.name.toLowerCase().contains(widget.search.toLowerCase()))
            .toList();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // Header
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _StepBar(current: 1, total: 3),
              const SizedBox(height: 16),
              Row(
                children: [
                  _BackButton(onTap: widget.onBack),
                  const SizedBox(width: 14),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text('Where are you from? 🌍',
                          style: TextStyle(
                            color: AppConfig.obTextPrimary,
                            fontSize: 19,
                            fontWeight: FontWeight.w800,
                          )),
                      Text('Select your country',
                          style: TextStyle(
                            color: AppConfig.obTextSecondary
                                .withValues(alpha: 0.8),
                            fontSize: 12.5,
                            fontWeight: FontWeight.w500,
                          )),
                    ],
                  ),
                ],
              ),
              const SizedBox(height: 14),
              _SearchField(
                controller: _ctrl,
                hint: 'Search country…',
                onChanged: widget.onSearchChanged,
              ),
              const SizedBox(height: 8),
              if (widget.selected != null)
                _SelectedBadge(label: widget.selected!),
            ],
          ),
        ),
        const SizedBox(height: 6),
        Expanded(
          child: filtered.isEmpty
              ? const Center(
                  child: Text('No countries found.',
                      style: TextStyle(color: AppConfig.obTextSecondary)))
              : GridView.builder(
                  padding: const EdgeInsets.fromLTRB(14, 2, 14, 8),
                  gridDelegate:
                      const SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: 2,
                    mainAxisSpacing: 8,
                    crossAxisSpacing: 8,
                    childAspectRatio: 2.75,
                  ),
                  itemCount: filtered.length,
                  itemBuilder: (_, i) {
                    final c = filtered[i];
                    return _ItemTile(
                      flag: c.flag,
                      label: c.name,
                      isSelected: widget.selected == c.name,
                      onTap: () => widget.onSelect(c.name),
                    );
                  },
                ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 6, 20, 20),
          child: _PillButton(
            label: 'CONTINUE',
            enabled: widget.selected != null,
            isLoading: false,
            onPressed: widget.onContinue,
          ),
        ),
      ],
    );
  }
}

// ── Step 3: Language ──────────────────────────────────────────────────────────

class _Step3Language extends StatefulWidget {
  final String? selected;
  final String search;
  final bool isLoading;
  final VoidCallback onBack;
  final void Function(String) onSearchChanged;
  final void Function(String) onSelect;
  final VoidCallback onConfirm;

  const _Step3Language({
    required this.selected,
    required this.search,
    required this.isLoading,
    required this.onBack,
    required this.onSearchChanged,
    required this.onSelect,
    required this.onConfirm,
  });

  @override
  State<_Step3Language> createState() => _Step3LanguageState();
}

class _Step3LanguageState extends State<_Step3Language> {
  final TextEditingController _ctrl = TextEditingController();

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final filtered = widget.search.isEmpty
        ? _kLanguages
        : _kLanguages
            .where((l) =>
                l.name.toLowerCase().contains(widget.search.toLowerCase()))
            .toList();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // Header
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _StepBar(current: 2, total: 3),
              const SizedBox(height: 16),
              Row(
                children: [
                  _BackButton(onTap: widget.onBack),
                  const SizedBox(width: 14),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text('What language do you speak? 🗣️',
                          style: TextStyle(
                            color: AppConfig.obTextPrimary,
                            fontSize: 19,
                            fontWeight: FontWeight.w800,
                          )),
                      Text('Select your primary language',
                          style: TextStyle(
                            color: AppConfig.obTextSecondary
                                .withValues(alpha: 0.8),
                            fontSize: 12.5,
                            fontWeight: FontWeight.w500,
                          )),
                    ],
                  ),
                ],
              ),
              const SizedBox(height: 14),
              _SearchField(
                controller: _ctrl,
                hint: 'Search language…',
                onChanged: widget.onSearchChanged,
              ),
              const SizedBox(height: 8),
              if (widget.selected != null)
                _SelectedBadge(
                  label: _kLanguages
                      .firstWhere((l) => l.code == widget.selected,
                          orElse: () => const _Language('🌐', 'Other', 'other'))
                      .name,
                ),
            ],
          ),
        ),
        const SizedBox(height: 6),
        Expanded(
          child: filtered.isEmpty
              ? const Center(
                  child: Text('No languages found.',
                      style: TextStyle(color: AppConfig.obTextSecondary)))
              : GridView.builder(
                  padding: const EdgeInsets.fromLTRB(14, 2, 14, 8),
                  gridDelegate:
                      const SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: 2,
                    mainAxisSpacing: 8,
                    crossAxisSpacing: 8,
                    childAspectRatio: 2.75,
                  ),
                  itemCount: filtered.length,
                  itemBuilder: (_, i) {
                    final l = filtered[i];
                    return _ItemTile(
                      flag: l.flag,
                      label: l.name,
                      isSelected: widget.selected == l.code,
                      onTap: () => widget.onSelect(l.code),
                    );
                  },
                ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 6, 20, 20),
          child: _PillButton(
            label: 'GET STARTED',
            enabled: widget.selected != null && !widget.isLoading,
            isLoading: widget.isLoading,
            onPressed: widget.onConfirm,
          ),
        ),
      ],
    );
  }
}

// ── Shared small widgets ──────────────────────────────────────────────────────

class _StepBar extends StatelessWidget {
  final int current;
  final int total;

  const _StepBar({required this.current, required this.total});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: List.generate(total, (i) {
        final isActive = i == current;
        final isDone = i < current;
        return Expanded(
          child: Padding(
            padding: EdgeInsets.only(right: i < total - 1 ? 6 : 0),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 250),
              height: 4,
              decoration: BoxDecoration(
                color: isDone || isActive
                    ? AppConfig.obPrimary
                    : AppConfig.obBorder,
                borderRadius: BorderRadius.circular(99),
              ),
            ),
          ),
        );
      }),
    );
  }
}

// ── Mascot Reaction Page ──────────────────────────────────────────────────────

class _MascotReactionPage extends StatefulWidget {
  final String comment;
  final VoidCallback onContinue;

  const _MascotReactionPage({
    required this.comment,
    required this.onContinue,
  });

  @override
  State<_MascotReactionPage> createState() => _MascotReactionPageState();
}

class _MascotReactionPageState extends State<_MascotReactionPage> {
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    // Auto-advance after 2.5 seconds
    _timer = Timer(const Duration(milliseconds: 2500), widget.onContinue);
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () {
        _timer?.cancel();
        widget.onContinue();
      },
      child: Container(
        color: AppConfig.obBackground,
        child: SafeArea(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              // Mascot GIF
              Image.asset(
                'assets/after_questineers.gif',
                height: 220,
                fit: BoxFit.contain,
              ),
              const SizedBox(height: 28),
              // Speech bubble with comment
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 36),
                child: Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 22, vertical: 18),
                  decoration: BoxDecoration(
                    color: AppConfig.obCard,
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(
                        color: AppConfig.obPrimary.withValues(alpha: 0.4),
                        width: 1.5),
                  ),
                  child: Text(
                    widget.comment,
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      color: AppConfig.obTextPrimary,
                      fontSize: 17,
                      fontWeight: FontWeight.w700,
                      height: 1.5,
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 24),
              Text(
                'Tap anywhere to continue',
                style: TextStyle(
                  color: AppConfig.obTextSecondary.withValues(alpha: 0.55),
                  fontSize: 12,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _BackButton extends StatelessWidget {
  final VoidCallback onTap;
  const _BackButton({required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 38,
        height: 38,
        decoration: BoxDecoration(
          color: AppConfig.obCard,
          borderRadius: BorderRadius.circular(11),
          border: Border.all(color: AppConfig.obBorder),
        ),
        child: const Icon(Icons.arrow_back_ios_new_rounded,
            color: AppConfig.obPrimary, size: 17),
      ),
    );
  }
}

class _SearchField extends StatelessWidget {
  final TextEditingController controller;
  final String hint;
  final void Function(String) onChanged;

  const _SearchField({
    required this.controller,
    required this.hint,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: AppConfig.obCard,
        borderRadius: BorderRadius.circular(13),
        border: Border.all(color: AppConfig.obBorder),
      ),
      child: TextField(
        controller: controller,
        onChanged: onChanged,
        style: const TextStyle(color: AppConfig.obTextPrimary, fontSize: 14),
        decoration: InputDecoration(
          hintText: hint,
          hintStyle: TextStyle(
              color: AppConfig.obTextSecondary.withValues(alpha: 0.55),
              fontSize: 13.5),
          prefixIcon: const Icon(Icons.search_rounded,
              color: AppConfig.obTextSecondary, size: 19),
          border: InputBorder.none,
          contentPadding:
              const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
        ),
      ),
    );
  }
}

class _SelectedBadge extends StatelessWidget {
  final String label;
  const _SelectedBadge({required this.label});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
      decoration: BoxDecoration(
        color: AppConfig.obPrimary.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(9),
        border: Border.all(color: AppConfig.obPrimary.withValues(alpha: 0.35)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.check_circle_rounded,
              color: AppConfig.obPrimary, size: 14),
          const SizedBox(width: 6),
          Text(
            label,
            style: const TextStyle(
              color: AppConfig.obPrimary,
              fontSize: 12.5,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }
}

class _ItemTile extends StatelessWidget {
  final String flag;
  final String label;
  final bool isSelected;
  final VoidCallback onTap;

  const _ItemTile({
    required this.flag,
    required this.label,
    required this.isSelected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 170),
        curve: Curves.easeOut,
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
        decoration: BoxDecoration(
          color: isSelected
              ? AppConfig.obPrimary.withValues(alpha: 0.13)
              : AppConfig.obCard,
          borderRadius: BorderRadius.circular(13),
          border: Border.all(
            color: isSelected ? AppConfig.obPrimary : AppConfig.obBorder,
            width: isSelected ? 1.7 : 1.2,
          ),
        ),
        child: Row(
          children: [
            Text(flag, style: const TextStyle(fontSize: 18)),
            const SizedBox(width: 7),
            Expanded(
              child: Text(
                label,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: isSelected
                      ? AppConfig.obPrimary
                      : AppConfig.obTextPrimary,
                  fontSize: 12,
                  fontWeight:
                      isSelected ? FontWeight.w700 : FontWeight.w500,
                ),
              ),
            ),
            if (isSelected)
              const Icon(Icons.check_rounded,
                  color: AppConfig.obPrimary, size: 13),
          ],
        ),
      ),
    );
  }
}

// ── Pill button ───────────────────────────────────────────────────────────────

class _PillButton extends StatelessWidget {
  final String label;
  final bool enabled;
  final bool isLoading;
  final VoidCallback onPressed;

  const _PillButton({
    required this.label,
    required this.enabled,
    required this.isLoading,
    required this.onPressed,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 62,
      child: Stack(
        children: [
          Positioned.fill(
            top: 6,
            child: DecoratedBox(
              decoration: BoxDecoration(
                color: enabled
                    ? const Color(0xFF5BAA1B)
                    : const Color(0xFF2D3941),
                borderRadius: BorderRadius.circular(22),
              ),
            ),
          ),
          Positioned.fill(
            child: ElevatedButton(
              onPressed: enabled ? onPressed : null,
              style: ElevatedButton.styleFrom(
                backgroundColor:
                    enabled ? AppConfig.obPrimary : const Color(0xFF44525B),
                disabledBackgroundColor: const Color(0xFF44525B),
                foregroundColor: const Color(0xFF13210B),
                disabledForegroundColor: const Color(0xFF71818A),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(22)),
                elevation: 0,
              ),
              child: isLoading
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(
                          color: Color(0xFF13210B), strokeWidth: 2.5),
                    )
                  : Text(
                      label,
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w900,
                        letterSpacing: 1.1,
                      ),
                    ),
            ),
          ),
        ],
      ),
    );
  }
}

// ── Question bubble ───────────────────────────────────────────────────────────

class _QuestionBubble extends StatelessWidget {
  final String message;
  const _QuestionBubble({required this.message});

  @override
  Widget build(BuildContext context) {
    return Stack(
      clipBehavior: Clip.none,
      children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          decoration: BoxDecoration(
            color: const Color(0xFF151E23),
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: const Color(0xFF33434C), width: 2),
          ),
          child: Text(
            message,
            style: const TextStyle(
              color: Color(0xFFF3F7F1),
              fontSize: 17,
              fontWeight: FontWeight.w800,
              height: 1.3,
            ),
          ),
        ),
        Positioned(
          left: -11,
          bottom: 16,
          child: ClipPath(
            clipper: _TailClipper(),
            child: Container(
              width: 22,
              height: 26,
              color: const Color(0xFF33434C),
              padding: const EdgeInsets.only(right: 2),
              child: ClipPath(
                clipper: _TailInnerClipper(),
                child: Container(color: const Color(0xFF151E23)),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _TailClipper extends CustomClipper<Path> {
  @override
  Path getClip(Size size) => Path()
    ..moveTo(0, size.height * 0.5)
    ..lineTo(size.width, 0)
    ..lineTo(size.width, size.height)
    ..close();

  @override
  bool shouldReclip(covariant CustomClipper<Path> _) => false;
}

class _TailInnerClipper extends CustomClipper<Path> {
  @override
  Path getClip(Size size) => Path()
    ..moveTo(0, size.height * 0.5)
    ..lineTo(size.width, size.height * 0.1)
    ..lineTo(size.width, size.height * 0.9)
    ..close();

  @override
  bool shouldReclip(covariant CustomClipper<Path> _) => false;
}

// ── Role card ─────────────────────────────────────────────────────────────────

class _RoleCard extends StatelessWidget {
  final String value;
  final String? selected;
  final String emoji;
  final String title;
  final String subtitle;
  final Color accentColor;
  final VoidCallback onTap;

  const _RoleCard({
    required this.value,
    required this.selected,
    required this.emoji,
    required this.title,
    required this.subtitle,
    required this.accentColor,
    required this.onTap,
  });

  bool get _sel => selected == value;

  @override
  Widget build(BuildContext context) {
    return AnimatedContainer(
      duration: const Duration(milliseconds: 210),
      curve: Curves.easeOut,
      decoration: BoxDecoration(
        color: _sel
            ? accentColor.withValues(alpha: 0.10)
            : const Color(0xFF11181C),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: _sel ? accentColor : const Color(0xFF2A353B),
          width: _sel ? 2.0 : 1.4,
        ),
        boxShadow: _sel
            ? [
                BoxShadow(
                  color: accentColor.withValues(alpha: 0.16),
                  blurRadius: 18,
                  offset: const Offset(0, 4),
                ),
              ]
            : null,
      ),
      child: Material(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(20),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(20),
          child: Padding(
            padding:
                const EdgeInsets.symmetric(horizontal: 14, vertical: 16),
            child: Row(
              children: [
                AnimatedContainer(
                  duration: const Duration(milliseconds: 210),
                  width: 52,
                  height: 52,
                  decoration: BoxDecoration(
                    color: _sel
                        ? accentColor.withValues(alpha: 0.17)
                        : const Color(0xFF1A2227),
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(
                      color: _sel
                          ? accentColor.withValues(alpha: 0.45)
                          : const Color(0xFF2A353B),
                    ),
                  ),
                  child: Center(
                      child:
                          Text(emoji, style: const TextStyle(fontSize: 24))),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        style: TextStyle(
                          color: _sel ? accentColor : AppConfig.obTextPrimary,
                          fontSize: 15,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      const SizedBox(height: 3),
                      Text(
                        subtitle,
                        style: TextStyle(
                          color: _sel
                              ? accentColor.withValues(alpha: 0.72)
                              : AppConfig.obTextSecondary,
                          fontSize: 11.5,
                          fontWeight: FontWeight.w500,
                          height: 1.4,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 6),
                AnimatedOpacity(
                  opacity: _sel ? 1.0 : 0.0,
                  duration: const Duration(milliseconds: 180),
                  child: Icon(Icons.check_circle_rounded,
                      color: accentColor, size: 20),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// ── Glow orb ──────────────────────────────────────────────────────────────────

class _GlowOrb extends StatelessWidget {
  final double size;
  final Color color;
  const _GlowOrb({required this.size, required this.color});

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          gradient:
              RadialGradient(colors: [color, Colors.transparent]),
        ),
      ),
    );
  }
}
