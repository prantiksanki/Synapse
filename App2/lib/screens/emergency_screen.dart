import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../config/app_config.dart';
import '../models/emergency_contact.dart';
import '../services/emergency_contact_repository.dart';
import '../services/emergency_sms_service.dart';

class EmergencyScreen extends StatefulWidget {
  const EmergencyScreen({super.key});

  @override
  State<EmergencyScreen> createState() => _EmergencyScreenState();
}

class _EmergencyScreenState extends State<EmergencyScreen> {
  final EmergencyContactRepository _repository = EmergencyContactRepository();
  final EmergencySmsService _smsService = EmergencySmsService();

  List<EmergencyContact> _contacts = const <EmergencyContact>[];
  bool _isLoading = true;
  bool _isSending = false;

  @override
  void initState() {
    super.initState();
    _loadContacts();
  }

  Future<void> _loadContacts() async {
    final contacts = await _repository.loadContacts();
    if (!mounted) return;
    setState(() {
      _contacts = contacts;
      _isLoading = false;
    });
  }

  Future<void> _saveContacts(List<EmergencyContact> contacts) async {
    await _repository.saveContacts(contacts);
    if (!mounted) return;
    setState(() => _contacts = contacts);
  }

  Future<void> _addOrEditContact({EmergencyContact? initial}) async {
    final result = await showDialog<EmergencyContact>(
      context: context,
      builder: (context) => _EmergencyContactDialog(initial: initial),
    );
    if (result == null) return;

    final updated = [..._contacts];
    final index = updated.indexWhere((contact) => contact.id == result.id);
    if (index >= 0) {
      updated[index] = result;
    } else {
      updated.add(result);
    }
    await _saveContacts(updated);
  }

  Future<void> _deleteContact(EmergencyContact contact) async {
    final confirmed = await showDialog<bool>(
          context: context,
          builder: (context) => AlertDialog(
            title: const Text('Delete contact?'),
            content: Text(
              'Remove ${contact.name} from your emergency contact list?',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(context).pop(false),
                child: const Text('Cancel'),
              ),
              FilledButton(
                onPressed: () => Navigator.of(context).pop(true),
                style: FilledButton.styleFrom(
                  backgroundColor: const Color(0xFFB91C1C),
                ),
                child: const Text('Delete'),
              ),
            ],
          ),
        ) ??
        false;
    if (!confirmed) return;

    final updated = _contacts
        .where((existing) => existing.id != contact.id)
        .toList(growable: false);
    await _saveContacts(updated);
  }

  Future<String> _resolveUserName() async {
    final prefs = await SharedPreferences.getInstance();
    final displayName = prefs.getString('display_name') ?? '';
    final username = prefs.getString('webrtc_username') ?? '';
    return displayName.trim().isNotEmpty ? displayName.trim() : username.trim();
  }

  Future<void> _sendSos() async {
    if (_contacts.isEmpty || _isSending) return;

    final confirmed = await showDialog<bool>(
          context: context,
          builder: (context) => AlertDialog(
            title: const Text('Send Emergency Alert?'),
            content: const Text(
              'This will send an emergency SMS to all your saved contacts.',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(context).pop(false),
                child: const Text('Cancel'),
              ),
              FilledButton(
                onPressed: () => Navigator.of(context).pop(true),
                style: FilledButton.styleFrom(
                  backgroundColor: const Color(0xFFDC2626),
                ),
                child: const Text('OK'),
              ),
            ],
          ),
        ) ??
        false;

    if (!confirmed) return;

    setState(() => _isSending = true);
    final userName = await _resolveUserName();
    final result = await _smsService.sendEmergencyAlert(
      userName: userName,
      contacts: _contacts,
    );
    if (!mounted) return;
    setState(() => _isSending = false);

    switch (result) {
      case EmergencySmsResult.sentDirectly:
      case EmergencySmsResult.openedSmsAppFallback:
        await showDialog<void>(
          context: context,
          builder: (context) => AlertDialog(
            title: const Text('Emergency Alert Sent'),
            content: const Text('Emergency message sent to all contacts.'),
            actions: [
              FilledButton(
                onPressed: () => Navigator.of(context).pop(),
                child: const Text('OK'),
              ),
            ],
          ),
        );
        break;
      case EmergencySmsResult.permissionDenied:
        await showDialog<void>(
          context: context,
          builder: (context) => AlertDialog(
            title: const Text('SMS Permission Required'),
            content: const Text(
              'SMS permission is required for the SOS feature. Please allow '
              'SMS access and try again.',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(context).pop(),
                child: const Text('Close'),
              ),
            ],
          ),
        );
        break;
      case EmergencySmsResult.failed:
        await showDialog<void>(
          context: context,
          builder: (context) => AlertDialog(
            title: const Text('Could Not Send Alert'),
            content: const Text(
              'The emergency message could not be sent. Please try again.',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(context).pop(),
                child: const Text('Close'),
              ),
            ],
          ),
        );
        break;
    }
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
          'Emergency',
          style: TextStyle(
            color: AppConfig.obTextPrimary,
            fontWeight: FontWeight.w800,
          ),
        ),
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _addOrEditContact(),
        backgroundColor: const Color(0xFFDC2626),
        foregroundColor: Colors.white,
        icon: const Icon(Icons.person_add_alt_1_rounded),
        label: const Text(
          'Add Contact',
          style: TextStyle(fontWeight: FontWeight.w700),
        ),
      ),
      bottomNavigationBar: SafeArea(
        minimum: const EdgeInsets.fromLTRB(16, 0, 16, 16),
        child: SizedBox(
          height: 64,
          child: ElevatedButton.icon(
            onPressed: _contacts.isEmpty || _isSending ? null : _sendSos,
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFFDC2626),
              disabledBackgroundColor: const Color(0xFF7F1D1D),
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(20),
              ),
            ),
            icon: _isSending
                ? const SizedBox(
                    width: 22,
                    height: 22,
                    child: CircularProgressIndicator(
                      strokeWidth: 2.6,
                      color: Colors.white,
                    ),
                  )
                : const Icon(Icons.warning_rounded, size: 30),
            label: Text(
              _isSending ? 'Sending Alert...' : 'SOS',
              style: const TextStyle(
                fontSize: 22,
                fontWeight: FontWeight.w900,
                letterSpacing: 1,
              ),
            ),
          ),
        ),
      ),
      body: _isLoading
          ? const Center(
              child: CircularProgressIndicator(color: AppConfig.obPrimary),
            )
          : Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: const Color(0xFF2A1012),
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(
                        color: const Color(0xFF7F1D1D),
                        width: 1.4,
                      ),
                    ),
                    child: const Text(
                      'Press SOS to alert every saved emergency contact by SMS.',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                        height: 1.4,
                      ),
                    ),
                  ),
                  const SizedBox(height: 18),
                  Text(
                    'Saved Contacts',
                    style: Theme.of(context).textTheme.titleLarge?.copyWith(
                          color: AppConfig.obTextPrimary,
                          fontWeight: FontWeight.w800,
                        ),
                  ),
                  const SizedBox(height: 12),
                  Expanded(
                    child: _contacts.isEmpty
                        ? const _EmptyEmergencyContacts()
                        : ListView.separated(
                            itemCount: _contacts.length,
                            separatorBuilder: (_, __) =>
                                const SizedBox(height: 12),
                            itemBuilder: (context, index) {
                              final contact = _contacts[index];
                              return _EmergencyContactCard(
                                contact: contact,
                                onEdit: () => _addOrEditContact(initial: contact),
                                onDelete: () => _deleteContact(contact),
                              );
                            },
                          ),
                  ),
                ],
              ),
            ),
    );
  }
}

class _EmergencyContactCard extends StatelessWidget {
  final EmergencyContact contact;
  final VoidCallback onEdit;
  final VoidCallback onDelete;

  const _EmergencyContactCard({
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
        border: Border.all(color: AppConfig.obBorder, width: 1.4),
      ),
      child: Row(
        children: [
          Container(
            width: 54,
            height: 54,
            decoration: BoxDecoration(
              color: const Color(0xFFDC2626).withValues(alpha: 0.14),
              borderRadius: BorderRadius.circular(16),
            ),
            child: const Icon(
              Icons.emergency_share_rounded,
              color: Color(0xFFEF4444),
              size: 28,
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  contact.name,
                  style: const TextStyle(
                    color: AppConfig.obTextPrimary,
                    fontSize: 17,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  '${contact.relation} • ${contact.phoneNumber}',
                  style: const TextStyle(
                    color: AppConfig.obTextSecondary,
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
          IconButton(
            onPressed: onEdit,
            icon: const Icon(Icons.edit_rounded, color: AppConfig.obPrimary),
            tooltip: 'Edit contact',
          ),
          IconButton(
            onPressed: onDelete,
            icon: const Icon(Icons.delete_outline_rounded, color: Colors.redAccent),
            tooltip: 'Delete contact',
          ),
        ],
      ),
    );
  }
}

class _EmptyEmergencyContacts extends StatelessWidget {
  const _EmptyEmergencyContacts();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Container(
        padding: const EdgeInsets.all(24),
        decoration: BoxDecoration(
          color: AppConfig.obCard,
          borderRadius: BorderRadius.circular(24),
          border: Border.all(color: AppConfig.obBorder),
        ),
        child: const Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.contact_phone_rounded,
              size: 52,
              color: Color(0xFFEF4444),
            ),
            SizedBox(height: 14),
            Text(
              'No emergency contacts yet',
              style: TextStyle(
                color: AppConfig.obTextPrimary,
                fontSize: 18,
                fontWeight: FontWeight.w800,
              ),
            ),
            SizedBox(height: 8),
            Text(
              'Add a trusted friend or family member before using SOS.',
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

class _EmergencyContactDialog extends StatefulWidget {
  final EmergencyContact? initial;

  const _EmergencyContactDialog({this.initial});

  @override
  State<_EmergencyContactDialog> createState() => _EmergencyContactDialogState();
}

class _EmergencyContactDialogState extends State<_EmergencyContactDialog> {
  late final TextEditingController _nameController;
  late final TextEditingController _relationController;
  late final TextEditingController _phoneController;
  final _formKey = GlobalKey<FormState>();

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
    final isEditing = widget.initial != null;
    return AlertDialog(
      title: Text(isEditing ? 'Edit Contact' : 'Add Contact'),
      content: Form(
        key: _formKey,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextFormField(
              controller: _nameController,
              textInputAction: TextInputAction.next,
              decoration: const InputDecoration(labelText: 'Contact Name'),
              validator: (value) {
                if (value == null || value.trim().isEmpty) {
                  return 'Enter a contact name';
                }
                return null;
              },
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _relationController,
              textInputAction: TextInputAction.next,
              decoration: const InputDecoration(labelText: 'Relation'),
              validator: (value) {
                if (value == null || value.trim().isEmpty) {
                  return 'Enter the relation';
                }
                return null;
              },
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
          child: Text(isEditing ? 'Save' : 'Add'),
        ),
      ],
    );
  }
}
