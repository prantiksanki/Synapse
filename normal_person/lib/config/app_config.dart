class AppConfig {
  // Change this to your PC's local IP address (run `ipconfig` on Windows)
  static const String backendUrl = 'http://192.168.0.100:3000';
  static const String userRole = 'caller';

  static const Map<String, dynamic> iceServers = {
    'iceServers': [
      {'urls': 'stun:stun.l.google.com:19302'},
      {'urls': 'stun:stun1.l.google.com:19302'},
    ],
  };

  static const Map<String, dynamic> sdpConstraints = {
    'mandatory': {
      'OfferToReceiveAudio': true,
      'OfferToReceiveVideo': true,
    },
    'optional': [],
  };
}
