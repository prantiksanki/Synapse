import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../models/emergency_contact.dart';

class EmergencyContactRepository {
  static const String _contactsKey = 'emergency_contacts_v1';

  Future<List<EmergencyContact>> loadContacts() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getStringList(_contactsKey) ?? <String>[];
    return raw
        .map((entry) => EmergencyContact.fromJson(
              Map<String, dynamic>.from(jsonDecode(entry) as Map),
            ))
        .where((contact) =>
            contact.name.trim().isNotEmpty &&
            contact.phoneNumber.trim().isNotEmpty)
        .toList(growable: false);
  }

  Future<void> saveContacts(List<EmergencyContact> contacts) async {
    final prefs = await SharedPreferences.getInstance();
    final payload = contacts
        .map((contact) => jsonEncode(contact.toJson()))
        .toList(growable: false);
    await prefs.setStringList(_contactsKey, payload);
  }
}
