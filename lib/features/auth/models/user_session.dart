class UserSession {
  final String sessId;
  final String sessKey;

  const UserSession({required this.sessId, required this.sessKey});

  factory UserSession.fromJson(Map<String, dynamic> json) {
    final message = (json['messages'] is List && (json['messages'] as List).isNotEmpty)
        ? (json['messages'] as List).first
        : null;

    final sessId = (json['sess_id'] ?? json['sessId'] ?? json['session_id'] ?? '').toString();
    final sessKey = (json['sess_key'] ?? json['sessKey'] ?? json['session_key'] ?? '').toString();

    if (sessId.isNotEmpty && sessKey.isNotEmpty) {
      return UserSession(sessId: sessId, sessKey: sessKey);
    }

    if (message is Map<String, dynamic>) {
      final mid = (message['sess_id'] ?? message['sessId'] ?? message['session_id'] ?? '').toString();
      final mkey = (message['sess_key'] ?? message['sessKey'] ?? message['session_key'] ?? '').toString();
      return UserSession(sessId: mid, sessKey: mkey);
    }

    return const UserSession(sessId: '', sessKey: '');
  }
}
