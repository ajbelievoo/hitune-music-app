enum UserRole {
  guest,
  user,
  moderator,
  admin;

  static UserRole fromBackend(dynamic value) {
    final v = (value ?? '').toString().trim().toLowerCase();
    switch (v) {
      case 'admin':
        return UserRole.admin;
      case 'moderator':
        return UserRole.moderator;
      case 'user':
        return UserRole.user;
      case 'guest':
        return UserRole.guest;
      default:
        return UserRole.user;
    }
  }

  String get backendValue {
    switch (this) {
      case UserRole.admin:
        return 'admin';
      case UserRole.moderator:
        return 'moderator';
      case UserRole.guest:
        return 'guest';
      case UserRole.user:
        return 'user';
    }
  }
}
