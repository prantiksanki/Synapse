import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:url_launcher/url_launcher.dart';

import '../models/emergency_contact.dart';

enum EmergencySmsResult {
  sentDirectly,
  openedSmsAppFallback,
  permissionDenied,
  failed,
}

class EmergencySmsService {
  static const _smsChannel = MethodChannel('synapse/sms');

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

    // Request SEND_SMS permission
    final status = await Permission.sms.request();

    if (status.isGranted) {
      return await _sendDirectly(numbers: numbers, message: message);
    }

    if (status.isPermanentlyDenied) {
      return EmergencySmsResult.permissionDenied;
    }

    // Permission denied — fall back to opening SMS app
    debugPrint('[EmergencySmsService] SMS permission denied, falling back to SMS app.');
    final opened = await _openSmsApp(numbers: numbers, message: message);
    return opened ? EmergencySmsResult.openedSmsAppFallback : EmergencySmsResult.failed;
  }

  Future<EmergencySmsResult> _sendDirectly({
    required List<String> numbers,
    required String message,
  }) async {
    bool anyFailed = false;
    for (final number in numbers) {
      try {
        await _smsChannel.invokeMethod<bool>('sendSms', {
          'number': number,
          'message': message,
        });
        debugPrint('[EmergencySmsService] SMS sent to $number');
      } catch (e) {
        debugPrint('[EmergencySmsService] Failed to send to $number: $e');
        anyFailed = true;
      }
    }

    if (anyFailed && numbers.length == 1) {
      // Single contact and it failed — fall back to SMS app
      final opened = await _openSmsApp(numbers: numbers, message: message);
      return opened ? EmergencySmsResult.openedSmsAppFallback : EmergencySmsResult.failed;
    }

    return EmergencySmsResult.sentDirectly;
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
