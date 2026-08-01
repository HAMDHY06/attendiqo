import 'dart:convert';

import 'package:attendiqo_shared/attendiqo_shared.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import 'package:qr_flutter/qr_flutter.dart';

import '../../../core/widgets/app_components.dart';
import '../../academic_management/application/academic_management_controller.dart';
import '../application/attendance_management_controller.dart';

class AttendanceManagementArea extends StatefulWidget {
  const AttendanceManagementArea({
    super.key,
    required this.academicController,
    this.controller,
  });
  final AcademicManagementController academicController;
  final AttendanceManagementController? controller;
  @override
  State<AttendanceManagementArea> createState() =>
      _AttendanceManagementAreaState();
}

class _AttendanceManagementAreaState extends State<AttendanceManagementArea> {
  late final AttendanceManagementController controller;
  late final bool ownsController;

  @override
  void initState() {
    super.initState();
    ownsController = widget.controller == null;
    if (widget.controller != null) {
      controller = widget.controller!;
      return;
    }
    if (kDebugMode) {
      final qrAdmin = MockQrAdministrationService(
        classes: widget.academicController.classes,
        assignments: widget.academicController.assignments,
      );
      for (final student in widget.academicController.students) {
        qrAdmin.credentials[student.qrToken] = StudentQrCredential(
          studentId: student.studentId,
          instituteId: student.instituteId,
          tokenHash: student.qrToken,
          version: student.qrVersion,
          enabled: student.qrEnabled,
          createdAt: student.createdAt,
        );
      }
      controller = AttendanceManagementController(
        actor: widget.academicController.actor,
        classes: widget.academicController.classes,
        students: widget.academicController.students,
        assignments: widget.academicController.assignments,
        scheduleChanges: widget.academicController.scheduleChanges,
        qrAdministrationService: qrAdmin,
        service: MockAttendanceService(
          qrService: qrAdmin.qrService,
          students: {
            for (final value in widget.academicController.students)
              value.studentId: value,
          },
          credentials: qrAdmin.credentials,
          assignments: widget.academicController.assignments,
          classes: {
            for (final value in widget.academicController.classes)
              value.classId: value,
          },
        ),
      );
    } else {
      controller = AttendanceManagementController(
        actor: widget.academicController.actor,
        classes: widget.academicController.classes,
        students: widget.academicController.students,
        assignments: widget.academicController.assignments,
        scheduleChanges: widget.academicController.scheduleChanges,
        qrAdministrationService: const UnavailableQrAdministrationService(),
        service: const UnavailableAttendanceService(),
        backendAvailable: false,
      );
    }
  }

  @override
  void dispose() {
    if (ownsController) controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) =>
      AttendanceDashboardScreen(controller: controller);
}

class AttendanceDashboardScreen extends StatelessWidget {
  const AttendanceDashboardScreen({super.key, required this.controller});
  final AttendanceManagementController controller;

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: controller,
    builder: (_, _) => Scaffold(
      appBar: AppBar(title: const Text('Attendance operations')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          const DashboardHeader(
            title: 'Attendance operations',
            subtitle:
                'Choose an assigned class, then keep the scanner open for continuous Entry or Departure recording.',
            icon: Icons.fact_check_rounded,
            eyebrow: 'Secure class sessions',
          ),
          const SizedBox(height: 18),
          DropdownButtonFormField<AcademicClass>(
            initialValue: controller.selectedClass,
            decoration: const InputDecoration(
              labelText: 'Select assigned class',
              prefixIcon: Icon(Icons.school),
            ),
            items: controller.attendanceClasses
                .map(
                  (e) => DropdownMenuItem(
                    value: e,
                    child: Text('${e.classCode} • ${e.name}'),
                  ),
                )
                .toList(),
            onChanged: controller.selectClass,
          ),
          const SizedBox(height: 12),
          if (controller.selectedClass != null)
            Card(
              child: ListTile(
                title: Text(controller.selectedClass!.scheduleLabel),
                subtitle: Text(
                  '${controller.selectedClassStudents.length} enrolled students',
                ),
                leading: const Icon(Icons.schedule),
              ),
            ),
          if (controller.error != null) ...[
            const SizedBox(height: 12),
            AppStatePanel.error(
              title: 'Action could not be completed',
              message: controller.error!,
            ),
          ],
          const SizedBox(height: 16),
          FilledButton.icon(
            onPressed: controller.busy || !controller.canStartSelectedAttendance
                ? null
                : () async {
                    if (await controller.startSession() && context.mounted) {
                      await Navigator.push(
                        context,
                        MaterialPageRoute<void>(
                          builder: (_) =>
                              ContinuousScannerScreen(controller: controller),
                        ),
                      );
                    }
                  },
            icon: const Icon(Icons.qr_code_scanner),
            label: const Text('Open attendance session'),
          ),
          const SizedBox(height: 12),
          OutlinedButton.icon(
            onPressed: !controller.canManageSelectedClassQr
                ? null
                : () => Navigator.push(
                    context,
                    MaterialPageRoute<void>(
                      builder: (_) =>
                          StudentQrManagementScreen(controller: controller),
                    ),
                  ),
            icon: const Icon(Icons.qr_code_2),
            label: const Text('Student QR cards'),
          ),
          const SizedBox(height: 12),
          OutlinedButton.icon(
            onPressed: controller.canExportSelectedReport
                ? () => Navigator.push(
                    context,
                    MaterialPageRoute<void>(
                      builder: (_) =>
                          AttendanceReportsScreen(controller: controller),
                    ),
                  )
                : null,
            icon: const Icon(Icons.analytics_outlined),
            label: const Text('Attendance reports'),
          ),
          const SizedBox(height: 24),
          AppStatePanel(
            icon: controller.backendAvailable
                ? Icons.shield_outlined
                : Icons.cloud_off_outlined,
            title: controller.backendAvailable
                ? 'Trusted-write boundary active'
                : 'Attendance backend not configured',
            message: controller.backendAvailable
                ? 'This development build uses the local test service. Production writes still require the reviewed trusted backend.'
                : 'Release attendance, QR and correction actions remain unavailable until the reviewed backend is deployed.',
          ),
        ],
      ),
    ),
  );
}

class ContinuousScannerScreen extends StatefulWidget {
  const ContinuousScannerScreen({
    super.key,
    required this.controller,
    this.cameraPreview,
  });
  final AttendanceManagementController controller;
  final Widget? cameraPreview;
  @override
  State<ContinuousScannerScreen> createState() =>
      _ContinuousScannerScreenState();
}

class _ContinuousScannerScreenState extends State<ContinuousScannerScreen> {
  MobileScannerController? cameraController;

  @override
  void initState() {
    super.initState();
    if (widget.cameraPreview == null) {
      cameraController = MobileScannerController(
        formats: const [BarcodeFormat.qrCode],
      );
    }
  }

  @override
  void dispose() {
    cameraController?.dispose();
    super.dispose();
  }

  Future<void> _detected(String payload) async {
    if (widget.controller.busy || !widget.controller.scannerActive) return;
    final result = await widget.controller.processPayload(payload);
    if (result.accepted) await HapticFeedback.mediumImpact();
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: widget.controller,
    builder: (_, _) {
      final session = widget.controller.session!;
      final academicClass = widget.controller.selectedClass!;
      final latest = widget.controller.latest;
      return Scaffold(
        appBar: AppBar(
          title: Text('${academicClass.name} • ${widget.controller.mode.name}'),
        ),
        body: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                Chip(
                  avatar: const Icon(Icons.calendar_today, size: 18),
                  label: Text(
                    session.date.toLocal().toString().split(' ').first,
                  ),
                ),
                Chip(
                  avatar: const Icon(Icons.schedule, size: 18),
                  label: Text(
                    '${session.effectiveStartTime.wireValue}–${session.effectiveEndTime.wireValue}',
                  ),
                ),
                Chip(
                  avatar: Icon(
                    widget.controller.online
                        ? Icons.cloud_done
                        : Icons.cloud_off,
                    size: 18,
                  ),
                  label: Text(
                    widget.controller.online
                        ? 'Online • confirmed writes'
                        : 'Offline • not confirmed',
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            SegmentedButton<AttendanceScanMode>(
              segments: const [
                ButtonSegment(
                  value: AttendanceScanMode.entry,
                  icon: Icon(Icons.login),
                  label: Text('Entry'),
                ),
                ButtonSegment(
                  value: AttendanceScanMode.departure,
                  icon: Icon(Icons.logout),
                  label: Text('Departure'),
                ),
              ],
              selected: {widget.controller.mode},
              onSelectionChanged: (value) =>
                  widget.controller.setMode(value.first),
            ),
            const SizedBox(height: 12),
            AspectRatio(
              aspectRatio: 4 / 3,
              child: ClipRRect(
                borderRadius: BorderRadius.circular(20),
                child: ColoredBox(
                  color: Colors.black,
                  child:
                      widget.cameraPreview ??
                      MobileScanner(
                        controller: cameraController,
                        onDetect: (capture) {
                          final raw = capture.barcodes.firstOrNull?.rawValue;
                          if (raw != null) _detected(raw);
                        },
                      ),
                ),
              ),
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: _ScannerMetric(
                    label: 'Scanned',
                    value: '${widget.controller.scannedCount}',
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: _ScannerMetric(
                    label: 'Class total',
                    value: '${session.totalStudents}',
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            if (latest != null)
              _LatestScanCard(result: latest, className: academicClass.name),
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                OutlinedButton.icon(
                  onPressed: () async {
                    widget.controller.togglePause();
                    if (widget.controller.paused) {
                      await cameraController?.stop();
                    } else {
                      await cameraController?.start();
                    }
                  },
                  icon: Icon(
                    widget.controller.paused ? Icons.play_arrow : Icons.pause,
                  ),
                  label: Text(
                    widget.controller.paused
                        ? 'Resume scanner'
                        : 'Pause scanner',
                  ),
                ),
                OutlinedButton.icon(
                  onPressed: () => Navigator.push(
                    context,
                    MaterialPageRoute<void>(
                      builder: (_) =>
                          ManualAttendanceScreen(controller: widget.controller),
                    ),
                  ),
                  icon: const Icon(Icons.edit_note),
                  label: const Text('Manual attendance'),
                ),
                FilledButton.icon(
                  onPressed: () => _finish(context),
                  icon: const Icon(Icons.stop_circle_outlined),
                  label: const Text('Finish session'),
                ),
              ],
            ),
            const SizedBox(height: 8),
            const Text(
              'The scanner stays active after every result. No per-student confirmation is required.',
            ),
          ],
        ),
      );
    },
  );

  Future<void> _finish(BuildContext context) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Finish attendance session?'),
        content: const Text('The closed session will reject further scans.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Keep scanning'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Finish'),
          ),
        ],
      ),
    );
    if (confirmed == true &&
        await widget.controller.finishSession() &&
        context.mounted) {
      Navigator.pop(context);
    }
  }
}

class _ScannerMetric extends StatelessWidget {
  const _ScannerMetric({required this.label, required this.value});
  final String label;
  final String value;
  @override
  Widget build(BuildContext context) => Card(
    child: Padding(
      padding: const EdgeInsets.all(12),
      child: Column(
        children: [
          Text(value, style: Theme.of(context).textTheme.headlineMedium),
          Text(label),
        ],
      ),
    ),
  );
}

class _LatestScanCard extends StatelessWidget {
  const _LatestScanCard({required this.result, required this.className});
  final AttendanceScanResult result;
  final String className;
  @override
  Widget build(BuildContext context) {
    final success = result.accepted;
    final student = result.student;
    return Card(
      color: success
          ? const Color(0xFFE8F8EE)
          : Theme.of(context).colorScheme.errorContainer,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(
              success ? Icons.check_circle : Icons.error,
              color: success
                  ? const Color(0xFF22C55E)
                  : Theme.of(context).colorScheme.error,
              size: 34,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    result.message,
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                  if (student != null)
                    Text('${student.fullName} • ${student.studentNumber}'),
                  Text(className),
                  if (result.record != null)
                    Text(
                      'Recorded: ${result.record!.updatedAt.toLocal()} • ${result.record!.syncState.name}',
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class ManualAttendanceScreen extends StatelessWidget {
  const ManualAttendanceScreen({super.key, required this.controller});
  final AttendanceManagementController controller;
  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: controller,
    builder: (_, _) => Scaffold(
      appBar: AppBar(title: const Text('Manual attendance & corrections')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          const Text(
            'Every manual change requires a reason and preserves correction metadata.',
          ),
          for (final student in controller.selectedClassStudents)
            Card(
              child: ListTile(
                title: Text(student.fullName),
                subtitle: Text(student.studentNumber),
                trailing: PopupMenuButton<AttendanceStatus>(
                  onSelected: (status) => _mark(context, student, status),
                  itemBuilder: (_) => AttendanceStatus.values
                      .map((e) => PopupMenuItem(value: e, child: Text(e.name)))
                      .toList(),
                ),
              ),
            ),
          if (controller.records.isNotEmpty) ...[
            const Divider(),
            Text(
              'Recorded attendance',
              style: Theme.of(context).textTheme.titleLarge,
            ),
            for (final record in controller.records)
              ListTile(
                title: Text(
                  controller.students
                          .where((e) => e.studentId == record.studentId)
                          .firstOrNull
                          ?.fullName ??
                      record.studentId,
                ),
                subtitle: Text(
                  '${record.status.name} • ${record.entryTime?.toLocal() ?? 'No entry'}',
                ),
                trailing: IconButton(
                  icon: const Icon(Icons.edit),
                  tooltip: 'Correct attendance',
                  onPressed: () => _correct(context, record),
                ),
              ),
          ],
        ],
      ),
    ),
  );

  Future<void> _mark(
    BuildContext context,
    Student student,
    AttendanceStatus status,
  ) async {
    final reason = await _reasonDialog(
      context,
      'Reason for manual ${status.name}',
    );
    if (reason != null) await controller.markManual(student, status, reason);
  }

  Future<void> _correct(BuildContext context, AttendanceRecord record) async {
    final reason = await _reasonDialog(context, 'Correction reason');
    if (reason != null) await controller.correct(record, record.status, reason);
  }

  Future<String?> _reasonDialog(BuildContext context, String title) async {
    final text = TextEditingController();
    final result = await showDialog<String>(
      context: context,
      builder: (_) => AlertDialog(
        title: Text(title),
        content: TextField(
          controller: text,
          autofocus: true,
          decoration: const InputDecoration(labelText: 'Required reason'),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () {
              if (text.text.trim().isNotEmpty) {
                Navigator.pop(context, text.text.trim());
              }
            },
            child: const Text('Save'),
          ),
        ],
      ),
    );
    text.dispose();
    return result;
  }
}

class StudentQrManagementScreen extends StatelessWidget {
  const StudentQrManagementScreen({super.key, required this.controller});
  final AttendanceManagementController controller;
  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: controller,
    builder: (_, _) => Scaffold(
      appBar: AppBar(title: const Text('Student QR cards')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          const Text(
            'QR values are opaque, revocable, and never include parent contact details.',
          ),
          const SizedBox(height: 12),
          FilledButton.icon(
            onPressed:
                controller.busy || controller.selectedClassStudents.isEmpty
                ? null
                : () => _exportClassCards(context),
            icon: const Icon(Icons.picture_as_pdf),
            label: const Text('Regenerate and export class QR cards'),
          ),
          for (final student in controller.selectedClassStudents)
            Card(
              child: ListTile(
                leading: const Icon(Icons.qr_code_2),
                title: Text(student.fullName),
                subtitle: Text(
                  '${student.studentNumber} • QR v${student.qrVersion} • ${student.qrEnabled ? 'enabled' : 'disabled'}',
                ),
                onTap: () => Navigator.push(
                  context,
                  MaterialPageRoute<void>(
                    builder: (_) => StudentQrCardScreen(
                      controller: controller,
                      student: student,
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    ),
  );

  Future<void> _exportClassCards(BuildContext context) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Regenerate all class QR cards?'),
        content: const Text(
          'Every previous QR for these students will stop working. New secrets are returned only for this PDF export.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Regenerate and export'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    final cards = <(Student, String)>[];
    for (final student in List<Student>.of(controller.selectedClassStudents)) {
      final result = await controller.regenerateQr(student);
      if (result == null) return;
      cards.add((student, result.payload));
    }
    await QrPdfExporter.shareMultiple(cards);
  }
}

class StudentQrCardScreen extends StatefulWidget {
  const StudentQrCardScreen({
    super.key,
    required this.controller,
    required this.student,
  });
  final AttendanceManagementController controller;
  final Student student;
  @override
  State<StudentQrCardScreen> createState() => _StudentQrCardScreenState();
}

class _StudentQrCardScreenState extends State<StudentQrCardScreen> {
  String? payload;
  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: widget.controller,
    builder: (_, _) => Scaffold(
      appBar: AppBar(title: const Text('Secure QR card')),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          Text(
            widget.student.fullName,
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.headlineSmall,
          ),
          Text(widget.student.studentNumber, textAlign: TextAlign.center),
          const SizedBox(height: 20),
          if (payload == null)
            const Card(
              child: Padding(
                padding: EdgeInsets.all(20),
                child: Text(
                  'The raw QR secret is not stored for later retrieval. Regenerate to issue a new one-time card.',
                ),
              ),
            )
          else
            Center(
              child: Semantics(
                label: 'Student QR code',
                child: QrImageView(data: payload!, size: 260),
              ),
            ),
          const SizedBox(height: 16),
          FilledButton.icon(
            onPressed: widget.controller.busy
                ? null
                : () async {
                    final result = await widget.controller.regenerateQr(
                      widget.student,
                    );
                    if (result != null) {
                      setState(() => payload = result.payload);
                    }
                  },
            icon: const Icon(Icons.refresh),
            label: Text(
              payload == null
                  ? 'Generate / regenerate QR'
                  : 'Regenerate and revoke old QR',
            ),
          ),
          OutlinedButton.icon(
            onPressed: payload == null
                ? null
                : () => QrPdfExporter.shareSingle(
                    student: widget.student,
                    payload: payload!,
                  ),
            icon: const Icon(Icons.picture_as_pdf),
            label: const Text('Share / print PDF card'),
          ),
          OutlinedButton.icon(
            onPressed: () async {
              await widget.controller.setQrEnabled(
                widget.student,
                !widget.student.qrEnabled,
              );
            },
            icon: Icon(
              widget.student.qrEnabled ? Icons.block : Icons.check_circle,
            ),
            label: Text(widget.student.qrEnabled ? 'Disable QR' : 'Enable QR'),
          ),
          const SizedBox(height: 12),
          const Text(
            'No parent mobile number, address, password, or attendance history is encoded or printed.',
          ),
        ],
      ),
    ),
  );
}

abstract final class QrPdfExporter {
  static Future<Uint8List> buildSingle({
    required Student student,
    required String payload,
    String instituteName = 'Attendiqo Institute',
  }) async {
    final document = pw.Document();
    document.addPage(
      pw.Page(
        build: (_) => pw.Center(
          child: pw.Container(
            width: 320,
            padding: const pw.EdgeInsets.all(24),
            decoration: pw.BoxDecoration(border: pw.Border.all()),
            child: pw.Column(
              mainAxisSize: pw.MainAxisSize.min,
              children: [
                pw.Text(
                  instituteName,
                  style: pw.TextStyle(
                    fontSize: 18,
                    fontWeight: pw.FontWeight.bold,
                  ),
                ),
                pw.SizedBox(height: 12),
                pw.Text(student.fullName),
                pw.Text(student.studentNumber),
                pw.SizedBox(height: 16),
                pw.BarcodeWidget(
                  barcode: pw.Barcode.qrCode(),
                  data: payload,
                  width: 210,
                  height: 210,
                ),
                pw.SizedBox(height: 10),
                pw.Text(
                  'Secure Attendiqo attendance QR - version ${student.qrVersion + 1}',
                  style: const pw.TextStyle(fontSize: 9),
                ),
              ],
            ),
          ),
        ),
      ),
    );
    return document.save();
  }

  static Future<void> shareSingle({
    required Student student,
    required String payload,
  }) async {
    final bytes = await buildSingle(student: student, payload: payload);
    await Printing.sharePdf(
      bytes: bytes,
      filename: '${student.studentNumber}_attendiqo_qr.pdf',
    );
  }

  static Future<void> shareMultiple(List<(Student, String)> cards) async {
    final document = pw.Document();
    for (final card in cards) {
      document.addPage(
        pw.Page(
          build: (_) => pw.Center(
            child: pw.Column(
              mainAxisSize: pw.MainAxisSize.min,
              children: [
                pw.Text(
                  'Attendiqo Institute',
                  style: pw.TextStyle(
                    fontSize: 18,
                    fontWeight: pw.FontWeight.bold,
                  ),
                ),
                pw.SizedBox(height: 10),
                pw.Text(card.$1.fullName),
                pw.Text(card.$1.studentNumber),
                pw.SizedBox(height: 14),
                pw.BarcodeWidget(
                  barcode: pw.Barcode.qrCode(),
                  data: card.$2,
                  width: 220,
                  height: 220,
                ),
                pw.SizedBox(height: 8),
                pw.Text(
                  'Secure Attendiqo attendance QR - version ${card.$1.qrVersion + 1}',
                  style: const pw.TextStyle(fontSize: 9),
                ),
              ],
            ),
          ),
        ),
      );
    }
    await Printing.sharePdf(
      bytes: await document.save(),
      filename: 'attendiqo_class_qr_cards.pdf',
    );
  }
}

class AttendanceReportsScreen extends StatelessWidget {
  const AttendanceReportsScreen({super.key, required this.controller});
  final AttendanceManagementController controller;
  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: controller,
    builder: (_, _) {
      final summary = AttendanceSummary.from(controller.records);
      return Scaffold(
        appBar: AppBar(title: const Text('Attendance reports')),
        body: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            Wrap(
              spacing: 10,
              runSpacing: 10,
              children: [
                _ReportMetric(label: 'Records', value: '${summary.total}'),
                _ReportMetric(label: 'Present', value: '${summary.present}'),
                _ReportMetric(label: 'Late', value: '${summary.late}'),
                _ReportMetric(label: 'Absent', value: '${summary.absent}'),
                _ReportMetric(
                  label: 'Attendance',
                  value: '${summary.attendancePercentage.toStringAsFixed(1)}%',
                ),
              ],
            ),
            const SizedBox(height: 16),
            Wrap(
              spacing: 8,
              children: [
                FilledButton.icon(
                  onPressed: controller.canExportSelectedReport
                      ? () => _shareCsv()
                      : null,
                  icon: const Icon(Icons.table_view),
                  label: const Text('Export CSV'),
                ),
                OutlinedButton.icon(
                  onPressed: controller.canExportSelectedReport
                      ? () => _sharePdf()
                      : null,
                  icon: const Icon(Icons.picture_as_pdf),
                  label: const Text('Export PDF'),
                ),
              ],
            ),
            const SizedBox(height: 16),
            for (final record in controller.records)
              Card(
                child: ListTile(
                  title: Text(
                    controller.students
                            .where((e) => e.studentId == record.studentId)
                            .firstOrNull
                            ?.fullName ??
                        record.studentId,
                  ),
                  subtitle: Text(
                    '${record.attendanceDate.toLocal().toString().split(' ').first} • ${record.entryTime?.toLocal() ?? 'No entry'} • ${record.departureTime?.toLocal() ?? 'No departure'}',
                  ),
                  trailing: Chip(label: Text(record.status.name)),
                ),
              ),
            if (controller.records.isEmpty)
              const Padding(
                padding: EdgeInsets.all(32),
                child: Center(
                  child: Text(
                    'No attendance records match the current session.',
                  ),
                ),
              ),
            const SizedBox(height: 16),
            const Text(
              'Date-range, class, and student repository filters are prepared at the service boundary; current debug reports use the active in-memory session.',
            ),
          ],
        ),
      );
    },
  );

  Future<void> _shareCsv() async {
    final csv = AttendanceCsvExporter.build(controller.records);
    await Printing.sharePdf(
      bytes: Uint8List.fromList(utf8.encode(csv)),
      filename: 'attendiqo_attendance.csv',
    );
  }

  Future<void> _sharePdf() async {
    final document = pw.Document();
    document.addPage(
      pw.MultiPage(
        build: (_) => [
          pw.Header(level: 0, child: pw.Text('Attendiqo Attendance Report')),
          pw.TableHelper.fromTextArray(
            headers: const ['Date', 'Student', 'Status', 'Entry', 'Departure'],
            data: controller.records
                .map(
                  (record) => [
                    record.attendanceDate.toIso8601String().split('T').first,
                    record.studentId,
                    record.status.name,
                    record.entryTime?.toIso8601String() ?? '',
                    record.departureTime?.toIso8601String() ?? '',
                  ],
                )
                .toList(),
          ),
        ],
      ),
    );
    await Printing.sharePdf(
      bytes: await document.save(),
      filename: 'attendiqo_attendance.pdf',
    );
  }
}

class _ReportMetric extends StatelessWidget {
  const _ReportMetric({required this.label, required this.value});
  final String label;
  final String value;
  @override
  Widget build(BuildContext context) => SizedBox(
    width: 150,
    child: Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          children: [
            Text(value, style: Theme.of(context).textTheme.headlineSmall),
            Text(label),
          ],
        ),
      ),
    ),
  );
}
