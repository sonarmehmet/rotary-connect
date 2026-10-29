import 'package:flutter/material.dart';
import 'package:rotary_shared/shared.dart';

/// Yönetim paneli modülleri ve her birini görmek için gereken izin.
/// (Arayüz filtresi yalnızca kullanım kolaylığıdır; yetki backend'de uygulanır.)
class AdminModule {
  const AdminModule(this.path, this.title, this.icon, this.permission);

  final String path;
  final String title;
  final IconData icon;
  final Permission permission;
}

const List<AdminModule> adminModules = [
  AdminModule('/', 'Genel Bakış', Icons.dashboard_outlined, Permission.viewFinancialReports),
  AdminModule('/members', 'Kullanıcı ve Üyeler', Icons.people_outline, Permission.manageRoles),
  AdminModule('/roles', 'Rol ve İzinler', Icons.admin_panel_settings_outlined, Permission.manageRoles),
  AdminModule('/dues', 'Aidat ve Tahsilatlar', Icons.receipt_long_outlined, Permission.manageDuesAndCollections),
  AdminModule('/campaigns', 'Bağış Kampanyaları', Icons.campaign_outlined, Permission.manageContent),
  AdminModule('/donations', 'Bağış Kayıtları', Icons.volunteer_activism_outlined, Permission.viewFinancialReports),
  AdminModule('/events', 'Etkinlikler', Icons.event_outlined, Permission.manageEvents),
  AdminModule('/registrations', 'Katılımcı Kayıtları', Icons.how_to_reg_outlined, Permission.manageEvents),
  AdminModule('/projects', 'Projeler', Icons.groups_outlined, Permission.manageContent),
  AdminModule('/news', 'Haberler ve Duyurular', Icons.newspaper_outlined, Permission.manageContent),
  AdminModule('/payments', 'Ödeme İşlemleri', Icons.payments_outlined, Permission.viewFinancialReports),
  AdminModule('/refunds', 'İadeler', Icons.undo_outlined, Permission.issueRefund),
  AdminModule('/notifications', 'Bildirimler', Icons.notifications_outlined, Permission.manageContent),
  AdminModule('/reports', 'Raporlar', Icons.assessment_outlined, Permission.viewFinancialReports),
  AdminModule('/audit', 'Denetim Kayıtları', Icons.fact_check_outlined, Permission.viewAuditLogs),
  AdminModule('/settings', 'Uygulama Ayarları', Icons.settings_outlined, Permission.manageSettings),
];
