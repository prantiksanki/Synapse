import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../config/app_config.dart';
import '../models/emergency_contact.dart';
import '../providers/webrtc_provider.dart';
import '../services/emergency_contact_repository.dart';
import '../services/t5_model_downloader.dart';
import 'caller_home_screen.dart';
import 'detection_screen.dart';
import 'model_download_screen.dart';

class EmergencyContactsOnboardingScreen extends StatefulWidget {
  final String role;
  final String username;
  final String country;
  final String language;

  const EmergencyContactsOnboardingScreen({
    super.key,
    required this.role,
    required this.username,
    required this.country,
    required this.language,
  });

  @override
  State<EmergencyContactsOnboardingScreen> createState() =>
      _EmergencyContactsOnboardingScreenState();
}

class _EmergencyContactsOnboardingScreenState
    extends State<EmergencyContactsOnboardingScreen> {
  final EmergencyContactRepository _repository = EmergencyContactRepository();
  List<EmergencyContact> _contacts = <EmergencyContact>[];
  bool _isFinishing = false;

  Future<void> _addOrEditContact({EmergencyContact? initial}) async {
    final result = await showDialog<EmergencyContact>(
      context: context,
      builder: (context) => _OnboardingEmergencyContactDialog(initial: initial),
    );
    if (result == null) return;

    setState(() {
      final index =
          _contacts.indexWhere((contact) => contact.id == result.id);
      if (index >= 0) {
        _contacts[index] = result;
      } else {
        _contacts = [..._contacts, result];
      }
    });
  }

  void _deleteContact(EmergencyContact contact) {
    setState(() {
      _contacts = _contacts
          .where((existing) => existing.id != contact.id)
          .toList(growable: false);
    });
  }

  Future<void> _finishOnboarding() async {
    if (_isFinishing) return;
    setState(() => _isFinishing = true);

    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('user_role', widget.role);
    await prefs.setBool('onboarding_done', true);
    await prefs.setString('webrtc_username', widget.username);
    await prefs.setString('user_country', widget.country);
    await prefs.setString('country', widget.country);
    await prefs.setString('preferred_language', widget.language);
    await _repository.saveContacts(_contacts);

    if (!mounted) return;
    context.read<WebRtcProvider>().connectWithRole(widget.username, widget.role);

    if (widget.role == 'caller') {
      Navigator.pushAndRemoveUntil(
        context,
        MaterialPageRoute(builder: (_) => const CallerHomeScreen()),
        (_) => false,
      );
      return;
    }

    final modelsReady = await T5ModelDownloader().allModelsDownloaded();
    if (!mounted) return;
    Navigator.pushAndRemoveUntil(
      context,
      MaterialPageRoute(
        builder: (_) =>
            modelsReady ? const DetectionScreen() : const ModelDownloadScreen(),
      ),
      (_) => false,
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppConfig.obBackground,
      appBar: AppBar(
        backgroundColor: AppConfig.obBackground,
        elevation: 0,
        scrolledUnderElevation: 0,
        title: const Text(
          'Emergency Contacts',
          style: TextStyle(
            color: AppConfig.obTextPrimary,
            fontWeight: FontWeight.w800,
          ),
        ),
      ),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 8, 20, 20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(18),
                decoration: BoxDecoration(
                  color: AppConfig.obCard,
                  borderRadius: BorderRadius.circular(24),
                  border: Border.all(color: AppConfig.obBorder, width: 1.4),
                ),
                child: const Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Add trusted people for SOS alerts',
                      style: TextStyle(
                        color: AppConfig.obTextPrimary,
                        fontSize: 20,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    SizedBox(height: 8),
                    Text(
                      'You can add multiple contacts now or skip and manage them later from the Emergency section.',
                      style: TextStyle(
                        color: AppConfig.obTextSecondary,
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                        height: 1.5,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 18),
              Expanded(
                child: _contacts.isEmpty
                    ? const _OnboardingEmergencyEmptyState()
                    : ListView.separated(
                        itemCount: _contacts.length,
                        separatorBuilder: (_, __) => const SizedBox(height: 12),
                        itemBuilder: (context, index) {
                          final contact = _contacts[index];
                          return _OnboardingEmergencyContactTile(
                            contact: contact,
                            onEdit: () => _addOrEditContact(initial: contact),
                            onDelete: () => _deleteContact(contact),
                          );
                        },
                      ),
              ),
              const SizedBox(height: 16),
              SizedBox(
                width: double.infinity,
                height: 58,
                child: OutlinedButton.icon(
                  onPressed: () => _addOrEditContact(),
                  icon: const Icon(Icons.person_add_alt_1_rounded),
                  label: const Text(
                    'Add Contact',
                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800),
                  ),
                ),
              ),
              const SizedBox(height: 12),
              SizedBox(
                width: double.infinity,
                height: 58,
                child: ElevatedButton(
                  onPressed: _isFinishing ? null : _finishOnboarding,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFFDC2626),
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(18),
                    ),
                  ),
                  child: _isFinishing
                      ? const SizedBox(
                          width: 22,
                          height: 22,
                          child: CircularProgressIndicator(
                            strokeWidth: 2.4,
                            color: Colors.white,
                          ),
                        )
                      : Text(
                          _contacts.isEmpty ? 'Skip for Now' : 'Continue',
                          style: const TextStyle(
                            fontSize: 17,
                            fontWeight: FontWeight.w900,
                          ),
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

class _OnboardingEmergencyEmptyState extends StatelessWidget {
  const _OnboardingEmergencyEmptyState();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Container(
        padding: const EdgeInsets.all(24),
        decoration: BoxDecoration(
          color: AppConfig.obCard,
          borderRadius: BorderRadius.circular(24),
          border: Border.all(color: AppConfig.obBorder, width: 1.4),
        ),
        child: const Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.health_and_safety_rounded,
              size: 56,
              color: Color(0xFFEF4444),
            ),
            SizedBox(height: 14),
            Text(
              'No contacts added yet',
              style: TextStyle(
                color: AppConfig.obTextPrimary,
                fontSize: 18,
                fontWeight: FontWeight.w800,
              ),
            ),
            SizedBox(height: 8),
            Text(
              'You can skip this step now and add contacts later from Emergency.',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: AppConfig.obTextSecondary,
                fontSize: 14,
                fontWeight: FontWeight.w600,
                height: 1.5,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _OnboardingEmergencyContactTile extends StatelessWidget {
  final EmergencyContact contact;
  final VoidCallback onEdit;
  final VoidCallback onDelete;

  const _OnboardingEmergencyContactTile({
    required this.contact,
    required this.onEdit,
    required this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppConfig.obCard,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: AppConfig.obBorder),
      ),
      child: Row(
        children: [
          const Icon(Icons.contacts_rounded, color: Color(0xFFEF4444), size: 28),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  contact.name,
                  style: const TextStyle(
                    color: AppConfig.obTextPrimary,
                    fontSize: 16,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  '${contact.relation} • ${contact.phoneNumber}',
                  style: const TextStyle(
                    color: AppConfig.obTextSecondary,
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
          IconButton(
            onPressed: onEdit,
            icon: const Icon(Icons.edit_rounded, color: AppConfig.obPrimary),
          ),
          IconButton(
            onPressed: onDelete,
            icon: const Icon(Icons.delete_outline_rounded, color: Colors.redAccent),
          ),
        ],
      ),
    );
  }
}

class _OnboardingEmergencyContactDialog extends StatefulWidget {
  final EmergencyContact? initial;

  const _OnboardingEmergencyContactDialog({this.initial});

  @override
  State<_OnboardingEmergencyContactDialog> createState() =>
      _OnboardingEmergencyContactDialogState();
}

class _OnboardingEmergencyContactDialogState
    extends State<_OnboardingEmergencyContactDialog> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _nameController;
  late final TextEditingController _relationController;
  late final TextEditingController _phoneController;

  @override
  void initState() {
    super.initState();
    _nameController = TextEditingController(text: widget.initial?.name ?? '');
    _relationController =
        TextEditingController(text: widget.initial?.relation ?? '');
    _phoneController =
        TextEditingController(text: widget.initial?.phoneNumber ?? '');
  }

  @override
  void dispose() {
    _nameController.dispose();
    _relationController.dispose();
    _phoneController.dispose();
    super.dispose();
  }

  void _submit() {
    if (!_formKey.currentState!.validate()) return;
    Navigator.of(context).pop(
      EmergencyContact(
        id: widget.initial?.id ?? DateTime.now().microsecondsSinceEpoch.toString(),
        name: _nameController.text.trim(),
        relation: _relationController.text.trim(),
        phoneNumber: _phoneController.text.trim(),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(widget.initial == null ? 'Add Contact' : 'Edit Contact'),
      content: Form(
        key: _formKey,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextFormField(
              controller: _nameController,
              decoration: const InputDecoration(labelText: 'Contact Name'),
              validator: (value) =>
                  (value == null || value.trim().isEmpty) ? 'Enter a name' : null,
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _relationController,
              decoration: const InputDecoration(labelText: 'Relation'),
              validator: (value) => (value == null || value.trim().isEmpty)
                  ? 'Enter the relation'
                  : null,
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _phoneController,
              keyboardType: TextInputType.phone,
              decoration: const InputDecoration(labelText: 'Phone Number'),
              validator: (value) {
                final trimmed = value?.trim() ?? '';
                if (trimmed.isEmpty) return 'Enter a phone number';
                if (trimmed.length < 8) return 'Enter a valid phone number';
                return null;
              },
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: _submit,
          style: FilledButton.styleFrom(
            backgroundColor: const Color(0xFFDC2626),
          ),
          child: const Text('Save'),
        ),
      ],
    );
  }
}
