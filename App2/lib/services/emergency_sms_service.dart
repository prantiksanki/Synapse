import 'package:flutter/foundation.dart';
import 'package:url_launcher/url_launcher.dart';

import '../models/emergency_contact.dart';

enum EmergencySmsResult {
  sentDirectly,
  openedSmsAppFallback,
  permissionDenied,
  failed,
}

class EmergencySmsService {
  Future<EmergencySmsResult> sendEmergencyAlert({
    required String userName,
    required List<EmergencyContact> contacts,
  }) async {
    final numbers = contacts
        .map((contact) => _normalizeNumber(contact.phoneNumber))
        .where((number) => number.isNotEmpty)
        .toList(growable: false);

    if (numbers.isEmpty) {
      return EmergencySmsResult.failed;
    }

    final message = _buildEmergencyMessage(userName);
    final openedSmsApp = await _openSmsApp(
      numbers: numbers,
      message: message,
    );
    if (openedSmsApp) {
      return EmergencySmsResult.openedSmsAppFallback;
    }
    debugPrint('[EmergencySmsService] Unable to open SMS app for emergency.');
    return EmergencySmsResult.failed;
  }

  String _buildEmergencyMessage(String userName) {
    final safeName = userName.trim().isEmpty ? 'The user' : userName.trim();
    return '$safeName is in danger and needs help immediately. '
        'Please contact them as soon as possible.';
  }

  String _normalizeNumber(String phoneNumber) {
    return phoneNumber.replaceAll(RegExp(r'[^0-9+]'), '');
  }

  Future<bool> _openSmsApp({
    required List<String> numbers,
    required String message,
  }) async {
    if (numbers.isEmpty) return false;
    final uri = Uri.parse(
      'sms:${numbers.join(",")}?body=${Uri.encodeComponent(message)}',
    );
    return launchUrl(uri, mode: LaunchMode.externalApplication);
  }
}
