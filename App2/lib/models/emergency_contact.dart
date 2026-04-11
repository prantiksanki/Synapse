class EmergencyContact {
  final String id;
  final String name;
  final String relation;
  final String phoneNumber;

  const EmergencyContact({
    required this.id,
    required this.name,
    required this.relation,
    required this.phoneNumber,
  });

  EmergencyContact copyWith({
    String? id,
    String? name,
    String? relation,
    String? phoneNumber,
  }) {
    return EmergencyContact(
      id: id ?? this.id,
      name: name ?? this.name,
      relation: relation ?? this.relation,
      phoneNumber: phoneNumber ?? this.phoneNumber,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'name': name,
      'relation': relation,
      'phoneNumber': phoneNumber,
    };
  }

  factory EmergencyContact.fromJson(Map<String, dynamic> json) {
    return EmergencyContact(
      id: json['id'] as String? ?? '',
      name: json['name'] as String? ?? '',
      relation: json['relation'] as String? ?? '',
      phoneNumber: json['phoneNumber'] as String? ?? '',
    );
  }
}
