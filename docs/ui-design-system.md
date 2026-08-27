# Attendiqo UI design system

Status: implementation guidance for the main app.

- Primary `#4338CA`, secondary `#2563EB`, accent `#06B6D4`
- Background `#F8FAFC`, surface `#FFFFFF`, text `#172033`, muted `#64748B`, border `#E2E8F0`
- Success `#22C55E`, warning `#F59E0B`, error `#EF4444`, information `#3B82F6`
- Page padding: 16; section spacing: 24; card padding: 16
- Cards: 16 radius; buttons and fields: 12 radius; targets: at least 48 × 48

Reusable main-app components include `AttendiqoAppShell`, `RoleDashboardHeader`, `OverviewMetricGrid`, `SectionHeader`, `CurrentOrNextClassCard`, `ActionRequiredCard`, `AppStatePanel`, `LoadingStatePanel`, and `AppStatusChip`.

The approved source asset is `Logos/Admin_Logo.png`, copied to `apps/attendiqo/assets/images/Admin_Logo.png`. It is used without stretching. It has a white background and is therefore not used as an adaptive-icon foreground until a transparent foreground export is provided.
