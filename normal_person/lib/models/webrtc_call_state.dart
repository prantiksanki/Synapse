enum CallStatus { idle, calling, ringing, active, ended }

class CallState {
  final CallStatus status;
  final String? remoteUsername;
  final String? callId;
  final String? callType;

  const CallState({
    this.status = CallStatus.idle,
    this.remoteUsername,
    this.callId,
    this.callType,
  });

  CallState copyWith({
    CallStatus? status,
    String? remoteUsername,
    String? callId,
    String? callType,
  }) =>
      CallState(
        status: status ?? this.status,
        remoteUsername: remoteUsername ?? this.remoteUsername,
        callId: callId ?? this.callId,
        callType: callType ?? this.callType,
      );
}
