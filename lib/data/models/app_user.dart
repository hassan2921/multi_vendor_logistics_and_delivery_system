import 'user_role.dart';

class AppUser {
  final String id;
  final String authUserId;
  final String email;
  final UserRole role;
  final String? fullName;

  const AppUser({
    required this.id,
    required this.authUserId,
    required this.email,
    required this.role,
    this.fullName,
  });

  factory AppUser.fromJson(Map<String, dynamic> json) => AppUser(
        id: json['id'] as String,
        authUserId: json['auth_user_id'] as String,
        email: json['email'] as String,
        role: UserRoleJson.fromWire(json['role'] as String),
        fullName: json['full_name'] as String?,
      );
}
