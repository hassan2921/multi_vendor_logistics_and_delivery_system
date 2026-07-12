enum UserRole { customer, courier, vendor, admin }

extension UserRoleJson on UserRole {
  String get wireValue => name;

  static UserRole fromWire(String value) => UserRole.values.firstWhere(
        (r) => r.name == value,
        orElse: () => UserRole.customer,
      );
}
