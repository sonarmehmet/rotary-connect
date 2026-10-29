/// Uygulama rolleri. Kaynak doğruluk: Firebase Auth custom claim `role`.
/// Arayüzdeki kontroller yalnızca kullanıcı deneyimi içindir; asıl yetki
/// kontrolü backend (Functions + Firestore kuralları) tarafında yapılır.
enum AppRole {
  visitor('visitor'),
  registeredUser('registered_user'),
  clubMember('club_member'),
  contentManager('content_manager'),
  financeManager('finance_manager'),
  systemAdmin('system_admin');

  const AppRole(this.wireName);
  final String wireName;

  static AppRole fromWire(String? value) {
    for (final r in AppRole.values) {
      if (r.wireName == value) return r;
    }
    return AppRole.visitor;
  }
}

enum Permission {
  viewPublicContent,
  donate,
  viewOwnProfile,
  viewOwnDonations,
  viewOwnEventRegistrations,
  viewOwnDues,
  manageContent,
  manageEvents,
  manageDuesAndCollections,
  recordManualPayment,
  issueRefund,
  viewFinancialReports,
  exportFinancialData,
  manageRoles,
  manageSettings,
  viewAuditLogs,
}

const Set<Permission> _publicPerms = {
  Permission.viewPublicContent,
  Permission.donate,
};

const Set<Permission> _userPerms = {
  ..._publicPerms,
  Permission.viewOwnProfile,
  Permission.viewOwnDonations,
  Permission.viewOwnEventRegistrations,
};

const Set<Permission> _memberPerms = {
  ..._userPerms,
  Permission.viewOwnDues,
};

/// Rol → izin tablosu. Yönetici roller üye sayılmaz: kendi aidatlarını görmek
/// için ayrıca `club_member` doğrulaması gerekir (Aşama 4'te claim modeli netleşir).
final Map<AppRole, Set<Permission>> rolePermissions = {
  AppRole.visitor: _publicPerms,
  AppRole.registeredUser: _userPerms,
  AppRole.clubMember: _memberPerms,
  AppRole.contentManager: {
    ..._userPerms,
    Permission.manageContent,
    Permission.manageEvents,
  },
  AppRole.financeManager: {
    ..._userPerms,
    Permission.manageDuesAndCollections,
    Permission.recordManualPayment,
    Permission.issueRefund,
    Permission.viewFinancialReports,
    Permission.exportFinancialData,
  },
  AppRole.systemAdmin: {
    ..._memberPerms,
    Permission.manageContent,
    Permission.manageEvents,
    Permission.manageDuesAndCollections,
    Permission.viewFinancialReports,
    Permission.manageRoles,
    Permission.manageSettings,
    Permission.viewAuditLogs,
  },
};

extension AppRolePermissions on AppRole {
  bool can(Permission permission) =>
      rolePermissions[this]?.contains(permission) ?? false;
}
