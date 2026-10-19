import 'dart:io';
import 'package:flutter/material.dart';
import 'package:ionicons/ionicons.dart';
import '../../core/models/models.dart';
import '../../core/theme/app_colors.dart';
import '../../core/widgets/common.dart';
import '../../core/widgets/media_widgets.dart';

enum ProfileSection { manager, property }

/// Inline setup form for a single onboarding step:
/// [ProfileSection.manager] renders manager details, [ProfileSection.property]
/// renders property details. The parent drives progression via [submit].
class ProfileSetupForm extends StatefulWidget {
  final ProfileSection section;
  final PropertyManager? initial;
  final ValueChanged<PropertyManager>? onChanged;
  final bool isDark;

  const ProfileSetupForm({
    super.key,
    required this.section,
    this.initial,
    this.onChanged,
    this.isDark = false,
  });

  @override
  ProfileSetupFormState createState() => ProfileSetupFormState();
}

class ProfileSetupFormState extends State<ProfileSetupForm> {
  static const _managerColor = Color(0xFF3B82F6);

  late PropertyManager _profile;
  late final TextEditingController _name;
  late final TextEditingController _email;
  late final TextEditingController _phone;
  late final TextEditingController _propertyName;
  late final TextEditingController _ownerName;
  late final TextEditingController _address;

  final Set<String> _touched = {};

  bool get _isManager => widget.section == ProfileSection.manager;

  @override
  void initState() {
    super.initState();
    _profile = widget.initial ??
        PropertyManager(
          id: '1',
          name: '',
          email: '',
          phone: '',
          address: '',
          propertyName: '',
          ownerName: '',
          propertyPictures: const [],
        );
    _name = TextEditingController(text: _profile.name);
    _email = TextEditingController(text: _profile.email);
    _phone = TextEditingController(text: _profile.phone);
    _propertyName = TextEditingController(text: _profile.propertyName ?? '');
    _ownerName = TextEditingController(text: _profile.ownerName ?? '');
    _address = TextEditingController(text: _profile.address);
  }

  @override
  void dispose() {
    _name.dispose();
    _email.dispose();
    _phone.dispose();
    _propertyName.dispose();
    _ownerName.dispose();
    _address.dispose();
    super.dispose();
  }

  // --- validation -----------------------------------------------------------
  String? _nameErr(String v) => v.trim().isEmpty
      ? 'Property manager name is required'
      : v.trim().length < 2
          ? 'Name must be at least 2 characters'
          : null;
  String? _emailErr(String v) => v.trim().isEmpty
      ? 'Email address is required'
      : !RegExp(r'\S+@\S+\.\S+').hasMatch(v.trim())
          ? 'Please enter a valid email address'
          : null;
  String? _phoneErr(String v) =>
      v.trim().isEmpty ? 'Phone number is required' : null;
  String? _propErr(String v) => v.trim().isEmpty
      ? 'Property name is required'
      : v.trim().length < 2
          ? 'Property name must be at least 2 characters'
          : null;
  String? _addrErr(String v) => v.trim().isEmpty
      ? 'Property address is required'
      : v.trim().length < 5
          ? 'Address must be at least 5 characters'
          : null;

  bool get _managerValid =>
      _nameErr(_profile.name) == null &&
      _emailErr(_profile.email) == null &&
      _phoneErr(_profile.phone) == null;
  bool get _propertyValid =>
      _propErr(_profile.propertyName ?? '') == null &&
      _addrErr(_profile.address) == null;

  /// Called by the parent's Continue button. Reveals errors and reports
  /// whether this step's fields are valid.
  bool submit() {
    setState(() {
      if (_isManager) {
        _touched.addAll({'name', 'email', 'phone'});
      } else {
        _touched.addAll({'propertyName', 'address'});
      }
    });
    return _isManager ? _managerValid : _propertyValid;
  }

  PropertyManager get value => _profile;

  String? _shown(String field, String? err) =>
      _touched.contains(field) ? err : null;

  void _set(String field, String v) {
    switch (field) {
      case 'name':
        _profile = _profile.copyWith(name: v);
        break;
      case 'email':
        _profile = _profile.copyWith(email: v);
        break;
      case 'phone':
        _profile = _profile.copyWith(phone: v);
        break;
      case 'propertyName':
        _profile = _profile.copyWith(propertyName: v);
        break;
      case 'ownerName':
        _profile = _profile.copyWith(ownerName: v);
        break;
      case 'address':
        _profile = _profile.copyWith(address: v);
        break;
    }
    _touched.add(field);
    widget.onChanged?.call(_profile);
    setState(() {});
  }

  void _update(PropertyManager next) {
    _profile = next;
    widget.onChanged?.call(next);
    setState(() {});
  }

  Future<void> _pickAvatar() async {
    final p = await MediaPicker.pickImage(context);
    if (!mounted || p == null) return;
    _update(_profile.copyWith(avatar: p));
  }

  Future<void> _pickPropertyPhoto() async {
    final p = await MediaPicker.pickImage(context);
    if (!mounted || p == null) return;
    _update(_profile.copyWith(propertyPictures: [p]));
  }

  // --- build ----------------------------------------------------------------
  @override
  Widget build(BuildContext context) {
    final accent = _isManager ? _managerColor : AppColors.primary;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: widget.isDark ? const Color(0xFF132228) : const Color(0xFFF8FAFC),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color:
              widget.isDark ? const Color(0x1AFFFFFF) : const Color(0x14000000),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _compactHeader(accent),
          const SizedBox(height: 18),
          _isManager ? _managerSection(accent) : _propertySection(accent),
        ],
      ),
    );
  }

  Widget _compactHeader(Color accent) {
    return Row(
      children: [
        Container(
          width: 42,
          height: 42,
          decoration: BoxDecoration(
            color: accent.withValues(alpha: 0.16),
            borderRadius: BorderRadius.circular(12),
          ),
          alignment: Alignment.center,
          child: Icon(
            _isManager ? Ionicons.personCircleOutline : Ionicons.business,
            size: 22,
            color: accent,
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                _isManager ? 'Set Up Your Profile' : 'Set Up Your Property',
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w800,
                  color: AppColors.heading,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                _isManager
                    ? 'Manager details used on invoices and receipts'
                    : 'Property details shown to tenants and on records',
                style: TextStyle(fontSize: 12.5, color: AppColors.textMuted),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _managerSection(Color accent) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _avatarPicker(accent),
        const SizedBox(height: 16),
        _input(
          'Full Name *',
          _name,
          'Enter your full name',
          (v) => _set('name', v),
          _shown('name', _nameErr(_profile.name)),
        ),
        _input(
          'Email Address *',
          _email,
          'Enter your email address',
          (v) => _set('email', v),
          _shown('email', _emailErr(_profile.email)),
          keyboard: TextInputType.emailAddress,
        ),
        _input(
          'Phone Number *',
          _phone,
          'Enter your phone number',
          (v) => _set('phone', v),
          _shown('phone', _phoneErr(_profile.phone)),
          keyboard: TextInputType.phone,
          bottom: 0,
        ),
      ],
    );
  }

  Widget _propertySection(Color accent) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _propertyPicker(accent),
        const SizedBox(height: 16),
        _input(
          'Property Name *',
          _propertyName,
          'Enter property name',
          (v) => _set('propertyName', v),
          _shown('propertyName', _propErr(_profile.propertyName ?? '')),
        ),
        _input(
          'Property Owner Name',
          _ownerName,
          'Enter property owner name (optional)',
          (v) => _set('ownerName', v),
          null,
        ),
        _input(
          'Property Address *',
          _address,
          'Enter property address',
          (v) => _set('address', v),
          _shown('address', _addrErr(_profile.address)),
          maxLines: 4,
          bottom: 0,
        ),
      ],
    );
  }

  // --- photo pickers --------------------------------------------------------
  Widget _avatarPicker(Color accent) {
    final has = (_profile.avatar ?? '').isNotEmpty;
    return _photoRow(
      onTap: _pickAvatar,
      preview: Stack(
        clipBehavior: Clip.none,
        children: [
          AvatarView(
            name: _profile.name.trim().isEmpty ? 'P' : _profile.name,
            uri: _profile.avatar,
            radius: 26,
            borderColor: accent,
            borderWidth: 2,
          ),
          Positioned(right: -2, bottom: -2, child: _cameraBadge(accent)),
        ],
      ),
      title: 'Manager Photo',
      subtitle: has ? 'Tap to change' : 'Add a photo (optional)',
    );
  }

  Widget _propertyPicker(Color accent) {
    final pics = _profile.propertyPictures;
    final has = pics.isNotEmpty && pics[0].isNotEmpty;
    return _photoRow(
      onTap: _pickPropertyPhoto,
      preview: Stack(
        clipBehavior: Clip.none,
        children: [
          Container(
            width: 52,
            height: 52,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: accent, width: 2),
              color: has ? null : AppColors.primaryLight,
              image: has
                  ? DecorationImage(
                      image: FileImage(File(pics[0])), fit: BoxFit.cover)
                  : null,
            ),
            alignment: Alignment.center,
            child: has ? null : Icon(Ionicons.business, color: accent, size: 24),
          ),
          Positioned(right: -2, bottom: -2, child: _cameraBadge(accent)),
        ],
      ),
      title: 'Property Photo',
      subtitle: has ? 'Tap to change' : 'Add a photo (optional)',
    );
  }

  Widget _cameraBadge(Color color) {
    final bg = widget.isDark ? const Color(0xFF132228) : const Color(0xFFF8FAFC);
    return Container(
      width: 22,
      height: 22,
      decoration: BoxDecoration(
        color: color,
        shape: BoxShape.circle,
        border: Border.all(color: bg, width: 2),
      ),
      alignment: Alignment.center,
      child: const Icon(Ionicons.camera, size: 11, color: Colors.white),
    );
  }

  Widget _photoRow({
    required VoidCallback onTap,
    required Widget preview,
    required String title,
    required String subtitle,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 2),
        child: Row(
          children: [
            preview,
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: TextStyle(
                      fontSize: 14.5,
                      fontWeight: FontWeight.w700,
                      color: AppColors.text,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    subtitle,
                    style: TextStyle(fontSize: 12.5, color: AppColors.textMuted),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  // --- inputs ---------------------------------------------------------------
  Widget _input(
    String label,
    TextEditingController controller,
    String hint,
    ValueChanged<String> onChanged,
    String? error, {
    TextInputType keyboard = TextInputType.text,
    int maxLines = 1,
    double bottom = 16,
  }) {
    return Padding(
      padding: EdgeInsets.only(bottom: bottom),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: TextStyle(
              fontSize: 13.5,
              fontWeight: FontWeight.w600,
              color: AppColors.textSecondary,
            ),
          ),
          const SizedBox(height: 8),
          TextField(
            controller: controller,
            onChanged: onChanged,
            keyboardType: keyboard,
            maxLines: maxLines,
            style: TextStyle(fontSize: 15, color: AppColors.text),
            decoration: InputDecoration(
              hintText: hint,
              hintStyle: TextStyle(color: AppColors.textMuted),
              filled: true,
              fillColor: AppColors.surface,
              contentPadding:
                  const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: BorderSide(color: AppColors.border),
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: BorderSide(
                  color: error != null ? AppColors.error : AppColors.border,
                ),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: BorderSide(
                  color: error != null
                      ? AppColors.error
                      : const Color(0xFF4CAF50),
                ),
              ),
            ),
          ),
          if (error != null)
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Text(
                error,
                style: const TextStyle(fontSize: 12, color: Color(0xFFFF6B6B)),
              ),
            ),
        ],
      ),
    );
  }
}
