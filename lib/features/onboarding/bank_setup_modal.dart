import 'dart:io';
import 'package:flutter/material.dart';
import 'package:ionicons/ionicons.dart';
import '../../core/models/models.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_theme.dart';
import '../../core/widgets/common.dart';
import '../../core/widgets/media_widgets.dart';
import 'setup_sheet.dart';

/// Port of `src/components/BankSetupModal.tsx` — list + add/edit form with
/// logo, account/routing numbers and default toggle.
Future<List<BankInfo>?> showBankSetupSheet(
  BuildContext context, {
  List<BankInfo> initial = const [],
}) async {
  var banks = [...initial];
  var adding = false;
  BankInfo? editing;
  String? tempLogo;

  final name = TextEditingController();
  final account = TextEditingController();
  final routing = TextEditingController();
  var isDefault = false;
  final errs = <String, String?>{};

  final colors = <List<Color>>[
    [const Color.fromRGBO(76, 175, 80, 0.2), const Color.fromRGBO(76, 175, 80, 0.1)],
    [const Color.fromRGBO(33, 150, 243, 0.2), const Color.fromRGBO(33, 150, 243, 0.1)],
    [const Color.fromRGBO(156, 39, 176, 0.2), const Color.fromRGBO(156, 39, 176, 0.1)],
    [const Color.fromRGBO(255, 152, 0, 0.2), const Color.fromRGBO(255, 152, 0, 0.1)],
    [const Color.fromRGBO(244, 67, 54, 0.2), const Color.fromRGBO(244, 67, 54, 0.1)],
    [const Color.fromRGBO(0, 150, 136, 0.2), const Color.fromRGBO(0, 150, 136, 0.1)],
    [const Color.fromRGBO(103, 58, 183, 0.2), const Color.fromRGBO(103, 58, 183, 0.1)],
    [const Color.fromRGBO(255, 87, 34, 0.2), const Color.fromRGBO(255, 87, 34, 0.1)],
  ];

  List<Color> bankColor(BankInfo b) {
    if (b.logo == null) {
      return [
        const Color.fromRGBO(255, 255, 255, 0.1),
        const Color.fromRGBO(255, 255, 255, 0.05),
      ];
    }
    var hash = 0;
    for (final c in b.name.codeUnits) {
      hash = (hash * 31 + c) % 2147483647;
    }
    return colors[hash.abs() % colors.length];
  }

  bool validate() {
    final e = <String, String?>{};
    if (name.text.trim().isEmpty) e['name'] = 'Bank name is required';
    if (account.text.trim().isEmpty) {
      e['account'] = 'Account number is required';
    } else if (!RegExp(r'^\d+$').hasMatch(account.text.trim())) {
      e['account'] = 'Account number must contain only numbers';
    }
    if (routing.text.trim().isEmpty) {
      e['routing'] = 'Routing number is required';
    } else if (!RegExp(r'^\d{9}$').hasMatch(routing.text.trim())) {
      e['routing'] = 'Routing number must be exactly 9 digits';
    }
    errs
      ..clear()
      ..addAll(e);
    return e.isEmpty;
  }

  final result = await showSetupSheet<List<BankInfo>>(
    context: context,
    builder: (ctx, height) => StatefulBuilder(
      builder: (ctx, setS) {
        void resetForm() {
          name.clear();
          account.clear();
          routing.clear();
          isDefault = false;
          errs.clear();
          tempLogo = null;
        }

        void startAdd() {
          setS(() {
            adding = true;
            editing = null;
            resetForm();
            isDefault = banks.isEmpty;
          });
        }

        void startEdit(BankInfo b) {
          setS(() {
            adding = true;
            editing = b;
            name.text = b.name;
            account.text = b.accountNumber ?? '';
            routing.text = b.routingNumber ?? '';
            isDefault = b.isDefault;
            errs.clear();
            tempLogo = null;
          });
        }

        void cancelEdit() {
          setS(() {
            adding = false;
            editing = null;
            resetForm();
          });
        }

        void saveBank() {
          if (!validate()) {
            setS(() {});
            return;
          }
          final data = BankInfo(
            id: editing?.id ??
                DateTime.now().millisecondsSinceEpoch.toString(),
            name: name.text.trim(),
            accountNumber: account.text.trim(),
            routingNumber: routing.text.trim(),
            isDefault: isDefault,
            logo: editing?.logo ?? tempLogo,
          );
          final updated = editing != null
              ? banks
                  .map((b) => b.id == editing!.id ? data : b)
                  .toList()
              : [...banks, data];
          if (data.isDefault) {
            for (var i = 0; i < updated.length; i++) {
              final b = updated[i];
              updated[i] = BankInfo(
                id: b.id,
                name: b.name,
                logo: b.logo,
                accountNumber: b.accountNumber,
                routingNumber: b.routingNumber,
                isDefault: b.id == data.id,
              );
            }
          }
          setS(() {
            banks = updated;
            adding = false;
            editing = null;
            resetForm();
          });
        }

        Future<void> deleteBank(String id) async {
          final ok = await showDialog<bool>(
            context: ctx,
            builder: (_) => AlertDialog(
              backgroundColor: AppColors.cardBackground,
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16),
                  side: BorderSide(color: AppColors.border)),
              title: Text('Delete Bank',
                  style: TextStyle(
                      color: AppColors.text, fontWeight: FontWeight.bold)),
              content: Text(
                  'Are you sure you want to delete this bank?',
                  style: TextStyle(color: AppColors.textSecondary)),
              actions: [
                TextButton(
                    onPressed: () => Navigator.pop(ctx, false),
                    child: Text('Cancel',
                        style: TextStyle(color: AppColors.textSecondary))),
                TextButton(
                    onPressed: () => Navigator.pop(ctx, true),
                    child: const Text('Delete',
                        style: TextStyle(color: AppColors.error))),
              ],
            ),
          );
          if (ok == true) {
            setS(() => banks = banks.where((b) => b.id != id).toList());
          }
        }

        return SetupSheet(
          icon: Ionicons.business,
          title: 'Set Up Your Banks',
          onClose: () => Navigator.pop(ctx),
          body: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(0, 12, 0, 20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Padding(
                  padding: EdgeInsets.symmetric(horizontal: 12),
                  child: Text(
                    'Add your bank accounts to easily track monthly deposits and financial transactions.',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                        fontSize: 13,
                        color: AppColors.textSecondary,
                        height: 1.4),
                  ),
                ),
                const SizedBox(height: 12),
                if (banks.isNotEmpty) ...[
                  for (final b in banks)
                    Padding(
                      padding:
                          const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(8),
                        child: Container(
                          decoration: BoxDecoration(
                              gradient: LinearGradient(colors: bankColor(b))),
                          padding: const EdgeInsets.all(12),
                          child: Row(children: [
                            _logo(b),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(b.name,
                                      style: TextStyle(fontSize: 14, color: AppColors.text, fontWeight: FontWeight.w600)),
                                  if ((b.accountNumber ?? '').isNotEmpty)
                                    Text(
                                      '****${b.accountNumber!.length > 4 ? b.accountNumber!.substring(b.accountNumber!.length - 4) : b.accountNumber}',
                                      style: TextStyle(
                                          fontSize: 12,
                                          color: AppColors.textSecondary),
                                    ),
                                  if (b.isDefault)
                                    const Padding(
                                      padding: EdgeInsets.only(top: 2),
                                      child: _DefaultBadge(),
                                    ),
                                ],
                              ),
                            ),
                            IconButton(
                              icon: const Icon(Ionicons.pencil,
                                  size: 16, color: AppColors.primary),
                              onPressed: () => startEdit(b),
                            ),
                            IconButton(
                              icon: const Icon(Ionicons.trash,
                                  size: 16, color: AppColors.secondary),
                              onPressed: () => deleteBank(b.id),
                            ),
                          ]),
                        ),
                      ),
                    ),
                  const SizedBox(height: 8),
                ],
                if (adding)
                  Container(
                    margin: const EdgeInsets.symmetric(horizontal: 12),
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: AppColors.surface,
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: AppColors.surfaceBorder),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(editing != null ? 'Edit Bank' : 'Add New Bank',
                            style: TextStyle(fontSize: 16, color: AppColors.text, fontWeight: FontWeight.w600)),
                        const SizedBox(height: 12),
                        Center(
                          child: GestureDetector(
                            onTap: () async {
                              final p =
                                  await MediaPicker.pickImage(context);
                              if (p != null) setS(() => tempLogo = p);
                            },
                            child: Container(
                              width: Responsive.normalize(context, 80),
                              height: Responsive.normalize(context, 80),
                              decoration: BoxDecoration(
                                color: AppColors.surfaceHover,
                                shape: BoxShape.circle,
                                border: Border.all(
                                    color: AppColors.primaryAlpha, width: 2),
                              ),
                              alignment: Alignment.center,
                              child: tempLogo != null
                                  ? ClipOval(
                                      child: Image.file(File(tempLogo!),
                                          width: Responsive.normalize(
                                              context, 76),
                                          height: Responsive.normalize(
                                              context, 76),
                                          fit: BoxFit.cover))
                                  : Column(
                                      mainAxisSize: MainAxisSize.min,
                                      children: const [
                                        Icon(Ionicons.camera,
                                            size: 24,
                                            color: AppColors.primary),
                                        SizedBox(height: 4),
                                        Text('Add Logo',
                                            style: TextStyle(
                                                fontSize: 12,
                                                color: AppColors.primary,
                                                fontWeight: FontWeight.w500)),
                                      ],
                                    ),
                            ),
                          ),
                        ),
                        const SizedBox(height: 12),
                        _bankInput(context, 'Bank Name *', name,
                            'Enter bank name', (v) => setS(() => errs['name'] = null),
                            errs['name']),
                        _bankInput(context, 'Account Number *', account,
                            'Enter account number',
                            (v) => setS(() => errs['account'] = null),
                            errs['account'],
                            keyboard: TextInputType.number),
                        _bankInput(context, 'Routing Number *', routing,
                            'Enter 9-digit routing number',
                            (v) => setS(() => errs['routing'] = null),
                            errs['routing'],
                            keyboard: TextInputType.number, maxLength: 9),
                        Row(children: [
                          const Expanded(
                            child: Text('Set as Default Bank',
                                style: TextStyle(
                                    fontSize: 12,
                                    color: Colors.white,
                                    fontWeight: FontWeight.w500)),
                          ),
                          _toggle(isDefault,
                              () => setS(() => isDefault = !isDefault)),
                        ]),
                        const SizedBox(height: 12),
                        Row(children: [
                          Expanded(
                            child: OutlinedButton(
                              style: OutlinedButton.styleFrom(
                                padding:
                                    const EdgeInsets.symmetric(vertical: 10),
                                side: BorderSide(
                                    color: AppColors.surfaceBorder),
                                shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(6)),
                              ),
                              onPressed: cancelEdit,
                              child: Text('Cancel',
                                  style: TextStyle(
                                      fontSize: 13,
                                      color: AppColors.textSecondary,
                                      fontWeight: FontWeight.w500)),
                            ),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Container(
                              decoration: BoxDecoration(
                                  borderRadius: BorderRadius.circular(6),
                                  gradient: const LinearGradient(colors: [
                                    Color(0xFF4CAF50),
                                    Color(0xFF45A049),
                                  ])),
                              child: Material(
                                color: Colors.transparent,
                                child: InkWell(
                                  borderRadius: BorderRadius.circular(6),
                                  onTap: saveBank,
                                  child: Padding(
                                    padding: const EdgeInsets.symmetric(
                                        vertical: 12),
                                    child: Center(
                                      child: Text(
                                        editing != null
                                            ? 'Update Bank'
                                            : 'Add Bank',
                                        style: const TextStyle(
                                            fontSize: 13,
                                            color: Colors.white,
                                            fontWeight: FontWeight.w600),
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ]),
                      ],
                    ),
                  )
                else
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                    child: OutlinedButton.icon(
                      style: OutlinedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        side: const BorderSide(color: AppColors.primaryAlpha),
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(8)),
                      ),
                      onPressed: startAdd,
                      icon: const Icon(Ionicons.add,
                          size: 20, color: AppColors.primary),
                      label: const Text('Add Bank',
                          style: TextStyle(
                              fontSize: 14,
                              color: AppColors.primary,
                              fontWeight: FontWeight.w600)),
                    ),
                  ),
              ],
            ),
          ),
          footer: Container(
            decoration: BoxDecoration(
              border: Border(
                  top: BorderSide(color: AppColors.border)),
            ),
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 20),
            child: Row(children: [
              Expanded(
                child: SizedBox(
                  height: 44,
                  child: OutlinedButton(
                    style: OutlinedButton.styleFrom(
                      side: const BorderSide(
                          color: Color.fromRGBO(244, 67, 54, 0.3),
                          width: 1.5),
                      backgroundColor:
                          const Color.fromRGBO(244, 67, 54, 0.1),
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12)),
                    ),
                    onPressed: () => Navigator.pop(ctx),
                    child: const Text('Skip',
                        style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w600,
                            color: Color(0xFFF44336))),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Container(
                  height: 44,
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(12),
                    gradient: const LinearGradient(
                        colors: [Color(0xFF4CAF50), Color(0xFF45A049)]),
                  ),
                  child: Material(
                    color: Colors.transparent,
                    child: InkWell(
                      borderRadius: BorderRadius.circular(12),
                      onTap: () => Navigator.pop(ctx, banks),
                      child: const Center(
                        child: Text('Continue',
                            style: TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.w600,
                                color: Colors.white)),
                      ),
                    ),
                  ),
                ),
              ),
            ]),
          ),
        );
      },
    ),
  );

  // Controllers are intentionally NOT disposed here: the sheet's widget tree
  // may still hold inherited dependencies at this moment (esp. with the
  // keyboard open), which trips '_dependents.isEmpty' during teardown.
  return result;
}

Widget _logo(BankInfo b) {
  if ((b.logo ?? '').isNotEmpty) {
    return ClipOval(
      child: Image.file(File(b.logo!),
          width: 40, height: 40, fit: BoxFit.cover),
    );
  }
  return Container(
    width: 40,
    height: 40,
    alignment: Alignment.center,
    decoration: BoxDecoration(
        color: AppColors.surfaceHover, shape: BoxShape.circle),
    child: Text(
      b.name.isEmpty ? '?' : b.name[0].toUpperCase(),
      style: TextStyle(
          fontSize: 16, color: AppColors.text, fontWeight: FontWeight.w600),
    ),
  );
}

class _DefaultBadge extends StatelessWidget {
  const _DefaultBadge();
  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
        decoration: BoxDecoration(
            color: AppColors.primaryAlpha,
            borderRadius: BorderRadius.circular(4)),
        child: const Text('Default',
            style: TextStyle(
                fontSize: 10,
                color: AppColors.primary,
                fontWeight: FontWeight.w600)),
      );
}

Widget _bankInput(
  BuildContext context,
  String label,
  TextEditingController controller,
  String hint,
  ValueChanged<String> onChanged,
  String? error, {
  TextInputType keyboard = TextInputType.text,
  int? maxLength,
}) {
  return Padding(
    padding: const EdgeInsets.only(bottom: 8),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label,
            style: TextStyle(fontSize: 12, color: AppColors.textSecondary, fontWeight: FontWeight.w500)),
        const SizedBox(height: 4),
        TextField(
          controller: controller,
          onChanged: onChanged,
          keyboardType: keyboard,
          maxLength: maxLength,
          style: TextStyle(fontSize: 13, color: AppColors.text),
          decoration: InputDecoration(
            hintText: hint,
            counterText: '',
            hintStyle: TextStyle(color: AppColors.textMuted),
            filled: true,
            fillColor: AppColors.surface,
            isDense: true,
            contentPadding:
                const EdgeInsets.symmetric(horizontal: 10, vertical: 12),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(6),
              borderSide: BorderSide(color: AppColors.surfaceBorder),
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(6),
              borderSide: BorderSide(
                  color: error != null
                      ? AppColors.secondary
                      : AppColors.surfaceBorder),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(6),
              borderSide: BorderSide(
                  color: error != null
                      ? AppColors.secondary
                      : AppColors.primary),
            ),
          ),
        ),
        if (error != null)
          Padding(
            padding: const EdgeInsets.only(top: 2),
            child: Text(error,
                style: const TextStyle(
                    fontSize: 10, color: AppColors.secondary)),
          ),
      ],
    ),
  );
}

Widget _toggle(bool value, VoidCallback onTap) {
  return GestureDetector(
    onTap: onTap,
    child: Container(
      width: 44,
      height: 24,
      padding: const EdgeInsets.symmetric(horizontal: 2),
      decoration: BoxDecoration(
        color: value ? AppColors.primary : AppColors.surfaceHover,
        borderRadius: BorderRadius.circular(12),
      ),
      child: AnimatedAlign(
        duration: const Duration(milliseconds: 150),
        alignment: value ? Alignment.centerRight : Alignment.centerLeft,
        child: Container(
          width: 20,
          height: 20,
          decoration: const BoxDecoration(
              color: Colors.white, shape: BoxShape.circle),
        ),
      ),
    ),
  );
}
