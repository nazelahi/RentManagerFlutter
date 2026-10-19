import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:ionicons/ionicons.dart';
import 'package:pdf/pdf.dart';
import 'package:printing/printing.dart';

import '../../core/models/models.dart';
import '../../core/state/app_data.dart';
import '../../core/theme/app_colors.dart';
import '../../core/widgets/common.dart';
import '../../services/report_export_service.dart';

/// Professional Branded Rent Receipt & Invoice Desktop Generator & Previewer.
class DesktopRentReceiptModal extends ConsumerStatefulWidget {
  final Payment? initialPayment;
  final Tenant? initialTenant;

  const DesktopRentReceiptModal({
    super.key,
    this.initialPayment,
    this.initialTenant,
  });

  static Future<void> show(
    BuildContext context, {
    Payment? payment,
    Tenant? tenant,
  }) {
    return showDialog(
      context: context,
      barrierDismissible: true,
      barrierColor: Colors.black.withValues(alpha: 0.55),
      builder: (_) => DesktopRentReceiptModal(
        initialPayment: payment,
        initialTenant: tenant,
      ),
    );
  }

  @override
  ConsumerState<DesktopRentReceiptModal> createState() =>
      _DesktopRentReceiptModalState();
}

class _DesktopRentReceiptModalState
    extends ConsumerState<DesktopRentReceiptModal> {
  Payment? _selectedPayment;
  Tenant? _selectedTenant;
  String _documentType = 'RECEIPT'; // 'RECEIPT' or 'INVOICE'
  late final TextEditingController _receiptNoController;
  late final TextEditingController _customNotesController;

  Uint8List? _cachedPdfBytes;

  @override
  void initState() {
    super.initState();
    _selectedPayment = widget.initialPayment;
    _selectedTenant = widget.initialTenant;

    final initialReceiptNo = _selectedPayment != null
        ? 'REC-${_selectedPayment!.paidForMonth?.replaceAll('-', '') ?? DateTime.now().year.toString()}-${_selectedPayment!.id.length >= 6 ? _selectedPayment!.id.substring(0, 6).toUpperCase() : _selectedPayment!.id.toUpperCase()}'
        : 'REC-${DateTime.now().year}${DateTime.now().month.toString().padLeft(2, '0')}-0001';

    _receiptNoController = TextEditingController(text: initialReceiptNo);
    _customNotesController = TextEditingController(
      text: 'Received with thanks. This official receipt acknowledges payment in full for the stated lease term.',
    );
  }

  @override
  void dispose() {
    _receiptNoController.dispose();
    _customNotesController.dispose();
    super.dispose();
  }

  void _onDataChanged() {
    setState(() {
      _cachedPdfBytes = null;
    });
  }

  Future<Uint8List> _buildPdfDocument(PdfPageFormat format) async {
    if (_cachedPdfBytes != null) return _cachedPdfBytes!;

    final s = ref.read(appDataProvider);
    final payment = _selectedPayment;
    final tenant = _selectedTenant;

    if (payment == null || tenant == null) {
      // Empty placeholder if not yet selected
      final dummyPayment = Payment(
        id: 'DEMO',
        tenantId: 'DEMO',
        amount: 0,
        status: 'paid',
        paidForMonth: '${DateTime.now().year}-${DateTime.now().month.toString().padLeft(2, '0')}',
        displayMonth: 'Current Month',
      );
      final dummyTenant = Tenant(
        id: 'DEMO',
        name: 'Select a Tenant and Payment',
        unit: 'N/A',
        phone: '',
        email: '',
        rentAmount: 0,
        joinDate: '',
      );
      return ReportExportService.generateRentReceiptPdf(
        payment: dummyPayment,
        tenant: dummyTenant,
        propertyManager: s.propertyManager,
        currency: s.selectedCurrency,
        receiptNumber: _receiptNoController.text.trim(),
        customNotes: _customNotesController.text.trim(),
        documentType: _documentType,
      );
    }

    final bytes = await ReportExportService.generateRentReceiptPdf(
      payment: payment,
      tenant: tenant,
      propertyManager: s.propertyManager,
      currency: s.selectedCurrency,
      receiptNumber: _receiptNoController.text.trim(),
      customNotes: _customNotesController.text.trim(),
      documentType: _documentType,
    );
    _cachedPdfBytes = bytes;
    return bytes;
  }

  Future<void> _handlePrint() async {
    final bytes = await _buildPdfDocument(PdfPageFormat.a4);
    if (!mounted) return;
    await ReportExportService.printPdf(
      context: context,
      pdfBytes: bytes,
      documentName: '${_documentType.toLowerCase()}_${_receiptNoController.text.trim()}',
    );
  }

  Future<void> _handleSavePdf() async {
    final bytes = await _buildPdfDocument(PdfPageFormat.a4);
    if (!mounted) return;
    final unit = _selectedTenant?.unit.replaceAll(RegExp(r'[^a-zA-Z0-9]'), '') ?? 'rent';
    final month = _selectedPayment?.paidForMonth ?? 'receipt';
    final fileName = 'Receipt_${unit}_$month.pdf';

    await ReportExportService.exportPdf(
      context: context,
      pdfBytes: bytes,
      fileName: fileName,
    );
  }

  void _handleCopySummary() {
    final payment = _selectedPayment;
    final tenant = _selectedTenant;
    final s = ref.read(appDataProvider);
    final cur = s.selectedCurrency;

    if (payment == null || tenant == null) return;

    final summary = '''
*RENT PAYMENT RECEIPT*
Receipt #: ${_receiptNoController.text.trim()}
Tenant: ${tenant.name} (${tenant.unit.isNotEmpty ? 'Unit ${tenant.unit}' : 'Main'})
Period: ${payment.displayMonth ?? payment.paidForMonth ?? 'Current'}
Amount Paid: $cur${payment.amount.toStringAsFixed(0)}
Status: ${payment.status.toUpperCase()}
Date: ${payment.paidDate ?? 'Recorded'}
Notes: ${_customNotesController.text.trim()}
Property: ${s.propertyManager?.propertyName ?? 'Residential Management'}
''';

    Clipboard.setData(ClipboardData(text: summary.trim()));
    showAppToast(context, 'Receipt summary copied to clipboard!', isSuccess: true);
  }

  @override
  Widget build(BuildContext context) {
    final s = ref.watch(appDataProvider);
    final isDark = AppColors.isDark;
    final bg = isDark ? const Color(0xFF041718) : Colors.white;
    final sidebarBg = isDark ? const Color(0xFF072123) : const Color(0xFFF8FAFC);
    final borderColor = isDark
        ? const Color.fromRGBO(255, 255, 255, 0.09)
        : const Color(0xFFE2E8F0);

    // Auto-resolve tenant if payment provided but tenant was null
    if (_selectedPayment != null && _selectedTenant == null) {
      _selectedTenant = s.scopedTenants
          .cast<Tenant?>()
          .firstWhere((t) => t?.id == _selectedPayment!.tenantId, orElse: () => null);
    }

    // Fallback: if no payment is selected, pick latest paid payment (scoped)
    if (_selectedPayment == null && s.scopedPayments.isNotEmpty) {
      final sortedPayments = [...s.scopedPayments]
        ..sort((a, b) => (b.paidDate ?? '').compareTo(a.paidDate ?? ''));
      _selectedPayment = sortedPayments.firstWhere(
        (p) => p.status == 'paid',
        orElse: () => sortedPayments.first,
      );
      if (_selectedPayment != null) {
        _selectedTenant = s.scopedTenants
            .cast<Tenant?>()
            .firstWhere((t) => t?.id == _selectedPayment!.tenantId, orElse: () => null);
        final newReceiptNo =
            'REC-${_selectedPayment!.paidForMonth?.replaceAll('-', '') ?? DateTime.now().year.toString()}-${_selectedPayment!.id.length >= 6 ? _selectedPayment!.id.substring(0, 6).toUpperCase() : _selectedPayment!.id.toUpperCase()}';
        _receiptNoController.text = newReceiptNo;
      }
    }

    final cur = s.selectedCurrency.isEmpty ? '\$' : s.selectedCurrency;

    return Dialog(
      backgroundColor: Colors.transparent,
      elevation: 0,
      insetPadding: const EdgeInsets.symmetric(horizontal: 40, vertical: 24),
      child: Center(
        child: Container(
          width: 1040,
          height: 720,
          constraints: const BoxConstraints(maxWidth: 1200, minWidth: 800),
          decoration: BoxDecoration(
            color: bg,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: borderColor, width: 1),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: isDark ? 0.65 : 0.20),
                blurRadius: 40,
                offset: const Offset(0, 18),
              ),
            ],
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // 1. Top Modal Header
              _buildTopBar(isDark, borderColor),

              // 2. Main Content Split View (Sidebar Controls + PDF Preview)
              Expanded(
                child: Row(
                  children: [
                    // Left Controls Sidebar
                    Container(
                      width: 340,
                      decoration: BoxDecoration(
                        color: sidebarBg,
                        border: Border(
                          right: BorderSide(color: borderColor, width: 1),
                        ),
                      ),
                      child: _buildControlsSidebar(
                        s: s,
                        isDark: isDark,
                        borderColor: borderColor,
                        currency: cur,
                      ),
                    ),

                    // Right Live PDF Preview Panel
                    Expanded(
                      child: Container(
                        color: isDark ? const Color(0xFF031011) : const Color(0xFFE2E8F0),
                        child: ClipRRect(
                          borderRadius: const BorderRadius.only(
                            bottomRight: Radius.circular(16),
                          ),
                          child: Theme(
                            data: Theme.of(context).copyWith(
                              canvasColor: isDark ? const Color(0xFF072123) : Colors.white,
                            ),
                            child: PdfPreview(
                              build: _buildPdfDocument,
                              canChangeOrientation: false,
                              canChangePageFormat: false,
                              canDebug: false,
                              maxPageWidth: 620,
                              pdfFileName: 'Receipt_${_selectedTenant?.unit ?? 'rent'}.pdf',
                              loadingWidget: const Center(
                                child: CircularProgressIndicator(
                                  strokeWidth: 2.5,
                                  valueColor: AlwaysStoppedAnimation(Color(0xFF0F766E)),
                                ),
                              ),
                              actions: [
                                PdfPrintAction(
                                  icon: const Icon(Ionicons.printOutline),
                                  jobName: 'Receipt_${_selectedTenant?.unit ?? 'rent'}',
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildTopBar(bool isDark, Color borderColor) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
      decoration: BoxDecoration(
        border: Border(bottom: BorderSide(color: borderColor, width: 1)),
      ),
      child: Row(
        children: [
          Container(
            width: 34,
            height: 34,
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                colors: [Color(0xFF0F766E), Color(0xFF0D9488)],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              borderRadius: BorderRadius.circular(8),
              boxShadow: [
                BoxShadow(
                  color: const Color(0xFF0F766E).withValues(alpha: 0.35),
                  blurRadius: 6,
                  offset: const Offset(0, 2),
                ),
              ],
            ),
            child: const Center(
              child: Icon(Ionicons.receiptOutline, size: 18, color: Colors.white),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Branded Rent Receipt & Invoice Generator',
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                    letterSpacing: -0.2,
                    color: AppColors.heading,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  'Official verification document with property branding, breakdown, and signature seals',
                  style: TextStyle(
                    fontSize: 11.5,
                    color: isDark
                        ? const Color(0xFF94A3B8)
                        : const Color(0xFF64748B),
                  ),
                ),
              ],
            ),
          ),

          // Close button
          IconButton(
            icon: Icon(
              Ionicons.close,
              size: 18,
              color: isDark ? const Color(0xFF94A3B8) : const Color(0xFF64748B),
            ),
            splashRadius: 16,
            onPressed: () => Navigator.of(context).pop(),
            tooltip: 'Close (Esc)',
          ),
        ],
      ),
    );
  }

  Widget _buildControlsSidebar({
    required AppDataState s,
    required bool isDark,
    required Color borderColor,
    required String currency,
  }) {
    final paidPayments = s.scopedPayments.where((p) => p.status == 'paid').toList()
      ..sort((a, b) => (b.paidDate ?? '').compareTo(a.paidDate ?? ''));

    final tenantById = {for (final t in s.scopedTenants) t.id: t};

    return ListView(
      padding: const EdgeInsets.all(18),
      children: [
        // 1. Document Format Segmented Switch
        Text(
          'DOCUMENT FORMAT',
          style: TextStyle(
            fontSize: 10,
            fontWeight: FontWeight.w700,
            letterSpacing: 0.6,
            color: isDark ? const Color(0xFF94A3B8) : const Color(0xFF64748B),
          ),
        ),
        const SizedBox(height: 8),
        Container(
          padding: const EdgeInsets.all(3),
          decoration: BoxDecoration(
            color: isDark ? const Color(0xFF091E20) : const Color(0xFFE2E8F0),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Row(
            children: [
              Expanded(
                child: _formatSegmentPill(
                  label: 'Payment Receipt',
                  isSelected: _documentType == 'RECEIPT',
                  isDark: isDark,
                  onTap: () {
                    setState(() {
                      _documentType = 'RECEIPT';
                      _onDataChanged();
                    });
                  },
                ),
              ),
              Expanded(
                child: _formatSegmentPill(
                  label: 'Rent Invoice',
                  isSelected: _documentType == 'INVOICE',
                  isDark: isDark,
                  onTap: () {
                    setState(() {
                      _documentType = 'INVOICE';
                      _onDataChanged();
                    });
                  },
                ),
              ),
            ],
          ),
        ),

        const SizedBox(height: 18),

        // 2. Select Payment Record (if multiple exist)
        Text(
          'TARGET PAYMENT RECORD',
          style: TextStyle(
            fontSize: 10,
            fontWeight: FontWeight.w700,
            letterSpacing: 0.6,
            color: isDark ? const Color(0xFF94A3B8) : const Color(0xFF64748B),
          ),
        ),
        const SizedBox(height: 8),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 10),
          decoration: BoxDecoration(
            color: isDark ? const Color(0xFF091E20) : Colors.white,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: borderColor, width: 0.8),
          ),
          child: DropdownButtonHideUnderline(
            child: DropdownButton<Payment>(
              value: _selectedPayment,
              isExpanded: true,
              dropdownColor: isDark ? const Color(0xFF0B2424) : Colors.white,
              onChanged: (p) {
                if (p != null) {
                  setState(() {
                    _selectedPayment = p;
                    _selectedTenant = tenantById[p.tenantId];
                    _receiptNoController.text =
                        'REC-${p.paidForMonth?.replaceAll('-', '') ?? DateTime.now().year.toString()}-${p.id.length >= 6 ? p.id.substring(0, 6).toUpperCase() : p.id.toUpperCase()}';
                    _onDataChanged();
                  });
                }
              },
              items: paidPayments.map((p) {
                final t = tenantById[p.tenantId];
                final tenantName = t?.name ?? 'Tenant';
                final unit = t?.unit.isNotEmpty == true ? ' • Unit ${t!.unit}' : '';
                final month = p.displayMonth ?? p.paidForMonth ?? '';
                return DropdownMenuItem(
                  value: p,
                  child: Text(
                    '$tenantName$unit • $month ($currency${p.amount.toStringAsFixed(0)})',
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 11.5,
                      fontWeight: FontWeight.w600,
                      color: AppColors.heading,
                    ),
                  ),
                );
              }).toList(),
            ),
          ),
        ),

        const SizedBox(height: 18),

        // 3. Receipt Number Customization
        Text(
          'RECEIPT / INVOICE NUMBER',
          style: TextStyle(
            fontSize: 10,
            fontWeight: FontWeight.w700,
            letterSpacing: 0.6,
            color: isDark ? const Color(0xFF94A3B8) : const Color(0xFF64748B),
          ),
        ),
        const SizedBox(height: 8),
        TextField(
          controller: _receiptNoController,
          style: TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w600,
            color: AppColors.heading,
          ),
          decoration: InputDecoration(
            isDense: true,
            filled: true,
            fillColor: isDark ? const Color(0xFF091E20) : Colors.white,
            contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(8),
              borderSide: BorderSide(color: borderColor, width: 0.8),
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(8),
              borderSide: BorderSide(color: borderColor, width: 0.8),
            ),
          ),
          onChanged: (_) => _onDataChanged(),
        ),

        const SizedBox(height: 18),

        // 4. Custom Remarks / Message
        Text(
          'REMARKS & THANK YOU MESSAGE',
          style: TextStyle(
            fontSize: 10,
            fontWeight: FontWeight.w700,
            letterSpacing: 0.6,
            color: isDark ? const Color(0xFF94A3B8) : const Color(0xFF64748B),
          ),
        ),
        const SizedBox(height: 8),
        TextField(
          controller: _customNotesController,
          maxLines: 3,
          style: TextStyle(
            fontSize: 11.5,
            color: AppColors.heading,
          ),
          decoration: InputDecoration(
            isDense: true,
            filled: true,
            fillColor: isDark ? const Color(0xFF091E20) : Colors.white,
            contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(8),
              borderSide: BorderSide(color: borderColor, width: 0.8),
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(8),
              borderSide: BorderSide(color: borderColor, width: 0.8),
            ),
          ),
          onChanged: (_) => _onDataChanged(),
        ),

        const SizedBox(height: 24),

        // 5. Action Buttons Hub
        ElevatedButton.icon(
          onPressed: _handlePrint,
          icon: const Icon(Ionicons.printOutline, size: 15),
          label: Text(_documentType == 'RECEIPT'
              ? 'Print Receipt (⌘P)'
              : 'Print Invoice (⌘P)'),
          style: ElevatedButton.styleFrom(
            backgroundColor: const Color(0xFF0F766E),
            foregroundColor: Colors.white,
            padding: const EdgeInsets.symmetric(vertical: 12),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(8),
            ),
            elevation: 2,
          ),
        ),
        const SizedBox(height: 8),
        OutlinedButton.icon(
          onPressed: _handleSavePdf,
          icon: const Icon(Ionicons.downloadOutline, size: 15),
          label: Text(_documentType == 'RECEIPT'
              ? 'Save PDF Receipt...'
              : 'Save PDF Invoice...'),
          style: OutlinedButton.styleFrom(
            padding: const EdgeInsets.symmetric(vertical: 12),
            foregroundColor: AppColors.heading,
            side: BorderSide(color: borderColor, width: 1),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(8),
            ),
          ),
        ),
        const SizedBox(height: 8),
        OutlinedButton.icon(
          onPressed: _handleCopySummary,
          icon: const Icon(Ionicons.copyOutline, size: 14),
          label: const Text('Copy WhatsApp / SMS Text'),
          style: OutlinedButton.styleFrom(
            padding: const EdgeInsets.symmetric(vertical: 11),
            foregroundColor: isDark ? const Color(0xFF94A3B8) : const Color(0xFF64748B),
            side: BorderSide(color: borderColor, width: 0.8),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(8),
            ),
          ),
        ),
      ],
    );
  }

  Widget _formatSegmentPill({
    required String label,
    required bool isSelected,
    required bool isDark,
    required VoidCallback onTap,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(6),
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 6),
        decoration: BoxDecoration(
          color: isSelected
              ? (isDark ? const Color(0xFF0F766E) : Colors.white)
              : Colors.transparent,
          borderRadius: BorderRadius.circular(6),
          boxShadow: isSelected
              ? [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.1),
                    blurRadius: 3,
                    offset: const Offset(0, 1),
                  ),
                ]
              : null,
        ),
        child: Center(
          child: Text(
            label,
            style: TextStyle(
              fontSize: 11,
              fontWeight: isSelected ? FontWeight.w700 : FontWeight.w500,
              color: isSelected
                  ? (AppColors.heading)
                  : (isDark ? const Color(0xFF94A3B8) : const Color(0xFF64748B)),
            ),
          ),
        ),
      ),
    );
  }
}
