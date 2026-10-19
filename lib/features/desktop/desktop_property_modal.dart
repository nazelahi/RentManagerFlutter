import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:ionicons/ionicons.dart';
import '../../core/models/models.dart';
import '../../core/state/app_data.dart';
import '../../core/theme/app_colors.dart';
import '../../core/widgets/common.dart';

/// Modal for adding a new property or editing an existing property on Desktop.
class DesktopPropertyModal extends ConsumerStatefulWidget {
  final Property? property;

  const DesktopPropertyModal({
    super.key,
    this.property,
  });

  static Future<void> show(
    BuildContext context, {
    Property? property,
  }) {
    return showDialog(
      context: context,
      barrierDismissible: true,
      barrierColor: Colors.black.withValues(alpha: 0.55),
      builder: (_) => DesktopPropertyModal(property: property),
    );
  }

  @override
  ConsumerState<DesktopPropertyModal> createState() =>
      _DesktopPropertyModalState();
}

class _DesktopPropertyModalState extends ConsumerState<DesktopPropertyModal> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _nameController;
  late final TextEditingController _addressController;
  late final TextEditingController _unitsController;
  late final TextEditingController _notesController;
  late String _selectedType;
  bool _isSaving = false;

  static const _propertyTypes = [
    {
      'id': 'residential',
      'label': 'Residential',
      'sub': 'Apartments, condos, multi-family',
      'icon': Ionicons.homeOutline,
    },
    {
      'id': 'commercial',
      'label': 'Commercial',
      'sub': 'Offices, retail, warehouses',
      'icon': Ionicons.briefcaseOutline,
    },
    {
      'id': 'mixed',
      'label': 'Mixed-Use',
      'sub': 'Retail ground floor + residential',
      'icon': Ionicons.businessOutline,
    },
    {
      'id': 'villa',
      'label': 'Villa / House',
      'sub': 'Single family, townhouse, luxury',
      'icon': Ionicons.storefrontOutline,
    },
  ];

  @override
  void initState() {
    super.initState();
    final p = widget.property;
    _nameController = TextEditingController(text: p?.name ?? '');
    _addressController = TextEditingController(text: p?.address ?? '');
    _unitsController =
        TextEditingController(text: (p?.totalUnits ?? 1).toString());
    _notesController = TextEditingController(text: p?.notes ?? '');
    _selectedType = p?.propertyType ?? 'residential';
  }

  @override
  void dispose() {
    _nameController.dispose();
    _addressController.dispose();
    _unitsController.dispose();
    _notesController.dispose();
    super.dispose();
  }

  Future<void> _handleSave() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() => _isSaving = true);
    final notifier = ref.read(appDataProvider.notifier);

    final name = _nameController.text.trim();
    final address = _addressController.text.trim();
    final units = int.tryParse(_unitsController.text.trim()) ?? 1;
    final notes = _notesController.text.trim();

    try {
      if (widget.property != null) {
        final updated = widget.property!.copyWith(
          name: name,
          address: address,
          propertyType: _selectedType,
          totalUnits: units,
          notes: notes.isNotEmpty ? notes : null,
        );
        notifier.updateProperty(updated);
        if (mounted) {
          Navigator.of(context).pop();
          showAppToast(
            context,
            'Property "$name" updated successfully',
            isSuccess: true,
          );
        }
      } else {
        final newProp = Property(
          id: newId(),
          name: name,
          address: address,
          propertyType: _selectedType,
          totalUnits: units,
          notes: notes.isNotEmpty ? notes : null,
          createdAt: DateTime.now(),
        );
        notifier.addProperty(newProp);
        notifier.selectProperty(newProp.id);
        if (mounted) {
          Navigator.of(context).pop();
          showAppToast(
            context,
            'Property "$name" added to portfolio',
            isSuccess: true,
          );
        }
      }
    } catch (e) {
      if (mounted) {
        showAppToast(
          context,
          'Failed to save property: $e',
          isError: true,
        );
      }
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  Future<void> _handleDelete() async {
    final p = widget.property;
    if (p == null) return;

    final s = ref.read(appDataProvider);
    final assignedTenants = s.tenants.where((t) => t.propertyId == p.id).length;

    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) {
        final isDark = AppColors.isDark;
        return AlertDialog(
          backgroundColor:
              isDark ? const Color(0xFF0F2627) : Colors.white,
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          title: Text(
            'Delete "${p.name}"?',
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.bold,
              color: AppColors.heading,
            ),
          ),
          content: Text(
            assignedTenants > 0
                ? 'This property currently has $assignedTenants assigned tenant(s). Deleting it will reassign these records to your default property.'
                : 'Are you sure you want to permanently delete this property?',
            style: TextStyle(
              fontSize: 13,
              color: isDark
                  ? const Color(0xFF94A3B8)
                  : const Color(0xFF64748B),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(false),
              child: const Text('Cancel'),
            ),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFFEF4444),
                foregroundColor: Colors.white,
              ),
              onPressed: () => Navigator.of(ctx).pop(true),
              child: const Text('Delete Property'),
            ),
          ],
        );
      },
    );

    if (confirm != true) return;

    final notifier = ref.read(appDataProvider.notifier);
    notifier.deleteProperty(p.id);

    if (mounted) {
      Navigator.of(context).pop();
      showAppToast(
        context,
        'Property "${p.name}" deleted',
        isSuccess: true,
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = AppColors.isDark;
    final isEdit = widget.property != null;

    final bg = isDark ? const Color(0xFF081C1D) : Colors.white;
    final cardBg = isDark ? const Color(0xFF0B2426) : const Color(0xFFF8FAFC);
    final borderColor = isDark
        ? const Color.fromRGBO(255, 255, 255, 0.08)
        : const Color(0xFFE2E8F0);
    final textPrimary = AppColors.heading;
    final textMuted =
        isDark ? const Color(0xFF94A3B8) : const Color(0xFF64748B);

    final screenWidth = MediaQuery.of(context).size.width;
    final isCompact = screenWidth < 600;

    return Dialog(
      backgroundColor: Colors.transparent,
      elevation: 0,
      insetPadding: EdgeInsets.symmetric(
        horizontal: isCompact ? 16 : 40,
        vertical: isCompact ? 16 : 24,
      ),
      child: Center(
        child: Container(
          width: isCompact ? screenWidth - 32 : 580,
          constraints: BoxConstraints(
            maxHeight: MediaQuery.of(context).size.height * 0.88,
          ),
          decoration: BoxDecoration(
            color: bg,
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: borderColor, width: 1.2),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: isDark ? 0.6 : 0.18),
                blurRadius: 36,
                offset: const Offset(0, 16),
              ),
            ],
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Header
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 24, vertical: 18),
                decoration: BoxDecoration(
                  color: cardBg,
                  borderRadius:
                      const BorderRadius.vertical(top: Radius.circular(20)),
                  border: Border(bottom: BorderSide(color: borderColor)),
                ),
                child: Row(
                  children: [
                    Container(
                      width: 40,
                      height: 40,
                      decoration: BoxDecoration(
                        gradient: const LinearGradient(
                          colors: [Color(0xFF0F766E), Color(0xFF059669)],
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                        ),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Icon(
                        isEdit
                            ? Ionicons.pencilOutline
                            : Ionicons.businessOutline,
                        color: Colors.white,
                        size: 20,
                      ),
                    ),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            isEdit ? 'Edit Property' : 'Add New Property',
                            style: TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w700,
                              color: textPrimary,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            isEdit
                                ? 'Update building details, unit count, and address.'
                                : 'Expand your portfolio with separate building tracking.',
                            style: TextStyle(
                              fontSize: 12,
                              color: textMuted,
                            ),
                          ),
                        ],
                      ),
                    ),
                    IconButton(
                      icon: Icon(Ionicons.close, size: 20, color: textMuted),
                      tooltip: 'Close',
                      onPressed: () => Navigator.of(context).pop(),
                      hoverColor: isDark
                          ? Colors.white.withValues(alpha: 0.08)
                          : Colors.black.withValues(alpha: 0.05),
                    ),
                  ],
                ),
              ),

              // Scrollable Form Content
              Flexible(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 24, vertical: 20),
                  child: Form(
                    key: _formKey,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // Property Name
                        _buildLabel('Property Name', required: true),
                        const SizedBox(height: 6),
                        TextFormField(
                          controller: _nameController,
                          style: TextStyle(color: textPrimary, fontSize: 13.5),
                          decoration: _inputDecoration(
                            hint: 'e.g., Sunset Heights Apartments',
                            icon: Ionicons.businessOutline,
                            isDark: isDark,
                          ),
                          validator: (v) {
                            if (v == null || v.trim().isEmpty) {
                              return 'Please enter a property name';
                            }
                            return null;
                          },
                        ),

                        const SizedBox(height: 18),

                        // Property Type Selector
                        _buildLabel('Property Classification'),
                        const SizedBox(height: 8),
                        Wrap(
                          spacing: 10,
                          runSpacing: 10,
                          children: _propertyTypes.map((type) {
                            final isSelected = _selectedType == type['id'];
                            return InkWell(
                              onTap: () => setState(
                                  () => _selectedType = type['id'] as String),
                              borderRadius: BorderRadius.circular(10),
                              child: Container(
                                width: isCompact ? double.infinity : 250,
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 12, vertical: 10),
                                decoration: BoxDecoration(
                                  color: isSelected
                                      ? (isDark
                                          ? const Color(0xFF0F766E)
                                              .withValues(alpha: 0.22)
                                          : const Color(0xFF0F766E)
                                              .withValues(alpha: 0.08))
                                      : (isDark
                                          ? const Color(0xFF0B2426)
                                          : const Color(0xFFF1F5F9)),
                                  borderRadius: BorderRadius.circular(10),
                                  border: Border.all(
                                    color: isSelected
                                        ? const Color(0xFF0F766E)
                                        : borderColor,
                                    width: isSelected ? 1.5 : 1,
                                  ),
                                ),
                                child: Row(
                                  children: [
                                    Icon(
                                      type['icon'] as IconData,
                                      size: 18,
                                      color: isSelected
                                          ? const Color(0xFF14B8A6)
                                          : textMuted,
                                    ),
                                    const SizedBox(width: 10),
                                    Expanded(
                                      child: Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: [
                                          Text(
                                            type['label'] as String,
                                            style: TextStyle(
                                              fontSize: 12.5,
                                              fontWeight: isSelected
                                                  ? FontWeight.w700
                                                  : FontWeight.w600,
                                              color: isSelected
                                                  ? (isDark
                                                      ? Colors.white
                                                      : const Color(0xFF0F766E))
                                                  : textPrimary,
                                            ),
                                          ),
                                          const SizedBox(height: 2),
                                          Text(
                                            type['sub'] as String,
                                            style: TextStyle(
                                              fontSize: 10.5,
                                              color: textMuted,
                                            ),
                                            maxLines: 1,
                                            overflow: TextOverflow.ellipsis,
                                          ),
                                        ],
                                      ),
                                    ),
                                    if (isSelected)
                                      const Icon(
                                        Ionicons.checkmarkCircle,
                                        size: 16,
                                        color: Color(0xFF14B8A6),
                                      ),
                                  ],
                                ),
                              ),
                            );
                          }).toList(),
                        ),

                        const SizedBox(height: 18),

                        // Address & Total Units
                        if (isCompact) ...[
                          _buildLabel('Street Address'),
                          const SizedBox(height: 6),
                          TextFormField(
                            controller: _addressController,
                            style: TextStyle(
                                color: textPrimary, fontSize: 13.5),
                            decoration: _inputDecoration(
                              hint: 'e.g., 742 Evergreen Terrace',
                              icon: Ionicons.locationOutline,
                              isDark: isDark,
                            ),
                          ),
                          const SizedBox(height: 14),
                          _buildLabel('Total Units'),
                          const SizedBox(height: 6),
                          TextFormField(
                            controller: _unitsController,
                            keyboardType: TextInputType.number,
                            style: TextStyle(
                                color: textPrimary, fontSize: 13.5),
                            decoration: _inputDecoration(
                              hint: '1',
                              icon: Ionicons.layersOutline,
                              isDark: isDark,
                            ),
                            validator: (v) {
                              if (v != null &&
                                  v.isNotEmpty &&
                                  int.tryParse(v) == null) {
                                return 'Enter a valid number';
                              }
                              return null;
                            },
                          ),
                        ] else
                          Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Expanded(
                                flex: 3,
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    _buildLabel('Street Address'),
                                    const SizedBox(height: 6),
                                    TextFormField(
                                      controller: _addressController,
                                      style: TextStyle(
                                          color: textPrimary, fontSize: 13.5),
                                      decoration: _inputDecoration(
                                        hint: 'e.g., 742 Evergreen Terrace',
                                        icon: Ionicons.locationOutline,
                                        isDark: isDark,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              const SizedBox(width: 14),
                              Expanded(
                                flex: 2,
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    _buildLabel('Total Units'),
                                    const SizedBox(height: 6),
                                    TextFormField(
                                      controller: _unitsController,
                                      keyboardType: TextInputType.number,
                                      style: TextStyle(
                                          color: textPrimary, fontSize: 13.5),
                                      decoration: _inputDecoration(
                                        hint: '1',
                                        icon: Ionicons.layersOutline,
                                        isDark: isDark,
                                      ),
                                      validator: (v) {
                                        if (v != null &&
                                            v.isNotEmpty &&
                                            int.tryParse(v) == null) {
                                          return 'Enter a valid number';
                                        }
                                        return null;
                                      },
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),

                        const SizedBox(height: 18),

                        // Notes
                        _buildLabel('Portfolio Notes / Details (Optional)'),
                        const SizedBox(height: 6),
                        TextFormField(
                          controller: _notesController,
                          maxLines: 3,
                          style: TextStyle(color: textPrimary, fontSize: 13.5),
                          decoration: InputDecoration(
                            hintText:
                                'Key codes, building superintendent info, parking rules, or parcel ID...',
                            hintStyle: TextStyle(
                                color: textMuted.withValues(alpha: 0.7),
                                fontSize: 12.5),
                            filled: true,
                            fillColor: isDark
                                ? const Color(0xFF0B2426)
                                : const Color(0xFFF1F5F9),
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(10),
                              borderSide: BorderSide(color: borderColor),
                            ),
                            enabledBorder: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(10),
                              borderSide: BorderSide(color: borderColor),
                            ),
                            focusedBorder: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(10),
                              borderSide: const BorderSide(
                                  color: Color(0xFF0F766E), width: 1.5),
                            ),
                            contentPadding: const EdgeInsets.all(12),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),

              // Bottom Actions
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
                decoration: BoxDecoration(
                  color: cardBg,
                  borderRadius:
                      const BorderRadius.vertical(bottom: Radius.circular(20)),
                  border: Border(top: BorderSide(color: borderColor)),
                ),
                child: Row(
                  children: [
                    if (isEdit && widget.property!.id != 'prop-default') ...[
                      OutlinedButton.icon(
                        style: OutlinedButton.styleFrom(
                          foregroundColor: const Color(0xFFEF4444),
                          side: const BorderSide(
                              color: Color(0xFFEF4444), width: 1),
                          padding: const EdgeInsets.symmetric(
                              horizontal: 14, vertical: 12),
                          shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(8)),
                        ),
                        onPressed: _isSaving ? null : _handleDelete,
                        icon: const Icon(Ionicons.trashOutline, size: 15),
                        label: const Text('Delete',
                            style: TextStyle(
                                fontSize: 12.5, fontWeight: FontWeight.w600)),
                      ),
                    ],
                    const Spacer(),
                    TextButton(
                      style: TextButton.styleFrom(
                        foregroundColor: textMuted,
                        padding: const EdgeInsets.symmetric(
                            horizontal: 16, vertical: 12),
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(8)),
                      ),
                      onPressed: _isSaving
                          ? null
                          : () => Navigator.of(context).pop(),
                      child: const Text('Cancel',
                          style: TextStyle(
                              fontSize: 13, fontWeight: FontWeight.w600)),
                    ),
                    const SizedBox(width: 10),
                    ElevatedButton.icon(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFF0F766E),
                        foregroundColor: Colors.white,
                        elevation: 0,
                        padding: const EdgeInsets.symmetric(
                            horizontal: 20, vertical: 12),
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(8)),
                      ),
                      onPressed: _isSaving ? null : _handleSave,
                      icon: _isSaving
                          ? const SizedBox(
                              width: 14,
                              height: 14,
                              child: CircularProgressIndicator(
                                  strokeWidth: 2, color: Colors.white),
                            )
                          : Icon(
                              isEdit
                                  ? Ionicons.checkmarkOutline
                                  : Ionicons.addOutline,
                              size: 16),
                      label: Text(
                        isEdit ? 'Save Changes' : 'Create Property',
                        style: const TextStyle(
                            fontSize: 13, fontWeight: FontWeight.w700),
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

  Widget _buildLabel(String text, {bool required = false}) {
    final isDark = AppColors.isDark;
    return Row(
      children: [
        Text(
          text,
          style: TextStyle(
            fontSize: 12.5,
            fontWeight: FontWeight.w600,
            color: isDark ? const Color(0xFFCBD5E1) : const Color(0xFF334155),
          ),
        ),
        if (required)
          const Text(
            ' *',
            style: TextStyle(
                color: Color(0xFFEF4444),
                fontWeight: FontWeight.bold,
                fontSize: 12.5),
          ),
      ],
    );
  }

  InputDecoration _inputDecoration({
    required String hint,
    required IconData icon,
    required bool isDark,
  }) {
    final borderColor = isDark
        ? const Color.fromRGBO(255, 255, 255, 0.08)
        : const Color(0xFFE2E8F0);
    final textMuted =
        isDark ? const Color(0xFF94A3B8) : const Color(0xFF64748B);

    return InputDecoration(
      hintText: hint,
      hintStyle:
          TextStyle(color: textMuted.withValues(alpha: 0.7), fontSize: 13),
      prefixIcon: Icon(icon, size: 17, color: textMuted),
      filled: true,
      fillColor: isDark ? const Color(0xFF0B2426) : const Color(0xFFF1F5F9),
      contentPadding:
          const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(10),
        borderSide: BorderSide(color: borderColor),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(10),
        borderSide: BorderSide(color: borderColor),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(10),
        borderSide: const BorderSide(color: Color(0xFF0F766E), width: 1.5),
      ),
      errorBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(10),
        borderSide: const BorderSide(color: Color(0xFFEF4444), width: 1),
      ),
      focusedErrorBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(10),
        borderSide: const BorderSide(color: Color(0xFFEF4444), width: 1.5),
      ),
    );
  }
}
