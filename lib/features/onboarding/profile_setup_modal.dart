import 'dart:io';
import 'package:flutter/material.dart';
import 'package:ionicons/ionicons.dart';
import '../../core/models/models.dart';
import '../../core/theme/app_colors.dart';
import '../../core/widgets/common.dart';
import '../../core/widgets/media_widgets.dart';
import 'setup_sheet.dart';

/// Port of `src/components/ProfileSetupModal.tsx` — 3-section bottom sheet
/// (Manager Picture → Manager Information → Property Information).
Future<PropertyManager?> showProfileSetupSheet(
  BuildContext context, {
  PropertyManager? initial,
}) async {
  var profile = initial ??
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

  final name = TextEditingController(text: profile.name);
  final email = TextEditingController(text: profile.email);
  final phone = TextEditingController(text: profile.phone);
  final propertyName = TextEditingController(text: profile.propertyName);
  final ownerName = TextEditingController(text: profile.ownerName ?? '');
  final address = TextEditingController(text: profile.address);

  String section = 'avatar';
  final errs = <String, String?>{};
  var submitting = false;

  String? nameErr(String v) => v.trim().isEmpty
      ? 'Property manager name is required'
      : v.trim().length < 2
          ? 'Name must be at least 2 characters'
          : null;
  String? emailErr(String v) => v.trim().isEmpty
      ? 'Email address is required'
      : !RegExp(r'\S+@\S+\.\S+').hasMatch(v.trim())
          ? 'Please enter a valid email address'
          : null;
  String? phoneErr(String v) =>
      v.trim().isEmpty ? 'Phone number is required' : null;
  String? propErr(String v) => v.trim().isEmpty
      ? 'Property name is required'
      : v.trim().length < 2
          ? 'Property name must be at least 2 characters'
          : null;
  String? addrErr(String v) => v.trim().isEmpty
      ? 'Property address is required'
      : v.trim().length < 5
          ? 'Address must be at least 5 characters'
          : null;

  bool personalValid() =>
      profile.name.trim().isNotEmpty &&
      profile.email.trim().isNotEmpty &&
      RegExp(r'\S+@\S+\.\S+').hasMatch(profile.email.trim()) &&
      profile.phone.trim().isNotEmpty;
  bool propertyValid() =>
      (profile.propertyName ?? '').trim().isNotEmpty &&
      profile.address.trim().isNotEmpty;
  bool formValid() =>
      nameErr(profile.name) == null &&
      emailErr(profile.email) == null &&
      phoneErr(profile.phone) == null &&
      propErr(profile.propertyName ?? '') == null &&
      addrErr(profile.address) == null;

  final result = await showSetupSheet<PropertyManager>(
    context: context,
    builder: (ctx, height) => StatefulBuilder(
      builder: (ctx, setS) {
        void change(String field, String value) {
          switch (field) {
            case 'name':
              profile = profile.copyWith(name: value);
              errs['name'] = nameErr(value);
              break;
            case 'email':
              profile = profile.copyWith(email: value);
              errs['email'] = emailErr(value);
              break;
            case 'phone':
              profile = profile.copyWith(phone: value);
              errs['phone'] = phoneErr(value);
              break;
            case 'propertyName':
              profile = profile.copyWith(propertyName: value);
              errs['propertyName'] = propErr(value);
              break;
            case 'ownerName':
              profile = profile.copyWith(ownerName: value);
              break;
            case 'address':
              profile = profile.copyWith(address: value);
              errs['address'] = addrErr(value);
              break;
          }
          setS(() {});
        }

        Future<void> save() async {
          if (submitting) return;
          if (!formValid()) {
            await showDialog<void>(
              context: ctx,
              builder: (_) => AlertDialog(
                backgroundColor: AppColors.cardBackground,
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(16),
                    side: BorderSide(color: AppColors.border)),
                title: Text('Validation Error',
                    style: TextStyle(
                        color: AppColors.text, fontWeight: FontWeight.bold)),
                content: Text(
                    'Please fill in all required fields correctly before saving.',
                    style: TextStyle(color: AppColors.textSecondary)),
                actions: [
                  TextButton(
                      onPressed: () => Navigator.pop(ctx),
                      child: Text('OK',
                          style: TextStyle(
                              color: AppColors.primary,
                              fontWeight: FontWeight.bold))),
                ],
              ),
            );
            return;
          }
          setS(() => submitting = true);
          Navigator.pop(ctx, profile);
        }

        final step = section == 'avatar' ? 1 : section == 'personal' ? 2 : 3;

        return SetupSheet(
          icon: Ionicons.person,
          iconColor: AppColors.primary,
          title: section == 'avatar'
              ? 'Manager Picture'
              : section == 'personal'
                  ? 'Manager Information'
                  : 'Property Information',
          onClose: () => Navigator.pop(ctx),
          body: Column(
            children: [
              // Progress bar.
              Padding(
                padding: const EdgeInsets.fromLTRB(0, 8, 0, 20),
                child: Column(
                  children: [
                    ClipRRect(
                      borderRadius: BorderRadius.circular(2),
                      child: Container(
                        height: 4,
                        color: const Color.fromRGBO(255, 255, 255, 0.2),
                        child: Align(
                          alignment: Alignment.centerLeft,
                          child: FractionallySizedBox(
                            widthFactor: step / 3,
                            child: Container(color: AppColors.primary),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text('Step $step of 3',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                            fontSize: Responsive.font(context, 12),
                            color: AppColors.textSecondary)),
                  ],
                ),
              ),
              Expanded(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.fromLTRB(0, 0, 0, 20),
                  keyboardDismissBehavior:
                      ScrollViewKeyboardDismissBehavior.onDrag,
                  child: SizedBox(
                    width: double.infinity,
                    child: section == 'avatar'
                        ? _avatarSection(context, profile, () async {
                            final p =
                                await MediaPicker.pickImage(context);
                            if (p != null) setS(() => profile = profile.copyWith(avatar: p));
                          }, () => setS(() => section = 'personal'))
                        : section == 'personal'
                            ? _personalSection(
                                context,
                                name,
                                email,
                                phone,
                                (f, v) => change(f, v),
                                errs,
                                personalValid(),
                                () => setS(() => section = 'avatar'),
                                () => setS(() => section = 'property'),
                              )
                            : _propertySection(
                                context,
                                profile,
                                propertyName,
                                ownerName,
                                address,
                                (f, v) => change(f, v),
                                errs,
                                propertyValid(),
                                () async {
                                  final p =
                                      await MediaPicker.pickImage(context);
                                  if (p != null) {
                                    setS(() =>
                                        profile = profile.copyWith(propertyPictures: [p]));
                                  }
                                },
                                submitting,
                                () => setS(() => section = 'personal'),
                                save,
                              ),
                  ),
                ),
              ),
            ],
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

Widget _sectionHeader(BuildContext context, IconData icon, Color color,
        String title, String subtitle) =>
    Column(
      children: [
        Icon(icon, size: Responsive.normalize(context, 32), color: color),
        const SizedBox(height: 12),
        Text(title,
            style: TextStyle(
                fontSize: 24,
                fontWeight: FontWeight.w700,
                color: AppColors.text)),
        const SizedBox(height: 8),
        Text(subtitle,
            textAlign: TextAlign.center,
            style: TextStyle(
                fontSize: 16, color: AppColors.textSecondary)),
      ],
    );

Widget _avatarSection(BuildContext context, PropertyManager profile,
    VoidCallback onPick, VoidCallback onContinue) {
  return Column(
    children: [
      const SizedBox(height: 4),
      _sectionHeader(context, Ionicons.camera, AppColors.primary,
          'Manager Picture', 'Add a photo to personalize your profile'),
      const SizedBox(height: 40),
      GestureDetector(
        onTap: onPick,
        child: Stack(
          clipBehavior: Clip.none,
          children: [
            AvatarView(
              name: profile.name.trim().isEmpty ? 'P' : profile.name,
              uri: profile.avatar,
              radius: Responsive.normalize(context, 60),
              borderColor: AppColors.primary,
              borderWidth: 4,
            ),
            Positioned(
              right: 0,
              bottom: 0,
              child: Container(
                width: Responsive.normalize(context, 40),
                height: Responsive.normalize(context, 40),
                decoration: BoxDecoration(
                  color: AppColors.primary,
                  shape: BoxShape.circle,
                  border: Border.all(color: Colors.white, width: 3),
                ),
                child: Icon(Ionicons.camera,
                    size: Responsive.normalize(context, 24),
                    color: Colors.white),
              ),
            ),
          ],
        ),
      ),
      const SizedBox(height: 36),
      Text(
          Platform.isMacOS || Platform.isWindows || Platform.isLinux
              ? 'Click to add manager picture'
              : 'Tap to add manager picture',
          style: TextStyle(
              fontSize: 16, color: AppColors.text, fontWeight: FontWeight.w600)),
      const SizedBox(height: 8),
      Text('This will be displayed throughout the app',
          textAlign: TextAlign.center,
          style: TextStyle(fontSize: 14, color: AppColors.textSecondary)),
      const SizedBox(height: 8),
      Text('Manager picture is optional - you can add it later',
          textAlign: TextAlign.center,
          style: TextStyle(
              fontSize: 12, color: AppColors.textMuted, fontStyle: FontStyle.italic)),
      const SizedBox(height: 50),
      _primaryButton(
        context,
        label: 'Continue',
        icon: Ionicons.arrowForward,
        iconColor: const Color(0xFF0A1F1F),
        onTap: onContinue,
      ),
    ],
  );
}

Widget _personalSection(
  BuildContext context,
  TextEditingController name,
  TextEditingController email,
  TextEditingController phone,
  void Function(String, String) onChange,
  Map<String, String?> errs,
  bool valid,
  VoidCallback onBack,
  VoidCallback onContinue,
) {
  return Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Center(
        child: _sectionHeader(context, Ionicons.person, AppColors.info,
            'Manager Information', 'Tell us about yourself'),
      ),
      const SizedBox(height: 24),
      _input(context, 'Full Name *', name, 'Enter your full name',
          (v) => onChange('name', v), errs['name'],
          keyboard: TextInputType.text),
      _input(context, 'Email Address *', email, 'Enter your email address',
          (v) => onChange('email', v), errs['email'],
          keyboard: TextInputType.emailAddress),
      _input(context, 'Phone Number *', phone, 'Enter your phone number',
          (v) => onChange('phone', v), errs['phone'],
          keyboard: TextInputType.phone),
      const SizedBox(height: 8),
      Row(
        children: [
          Expanded(
            child: _secondaryButton(
                context, 'Back', Icons.arrow_back, onBack),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: _primaryButton(
              context,
              label: 'Continue',
              icon: Ionicons.arrowForward,
              iconColor: valid ? Colors.white : AppColors.buttonDisabledText,
              onTap: valid ? onContinue : null,
            ),
          ),
        ],
      ),
    ],
  );
}

Widget _propertySection(
  BuildContext context,
  PropertyManager profile,
  TextEditingController propertyName,
  TextEditingController ownerName,
  TextEditingController address,
  void Function(String, String) onChange,
  Map<String, String?> errs,
  bool valid,
  VoidCallback onPick,
  bool submitting,
  VoidCallback onBack,
  VoidCallback onSave,
) {
  final hasPic =
      profile.propertyPictures.isNotEmpty && profile.propertyPictures[0].isNotEmpty;
  return Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      const SizedBox(height: 8),
      Center(
        child: Column(
          children: [
            GestureDetector(
              onTap: onPick,
              child: Stack(
                clipBehavior: Clip.none,
                children: [
                  Container(
                    width: Responsive.normalize(context, 120),
                    height: Responsive.normalize(context, 120),
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      border: Border.all(color: AppColors.primary, width: 4),
                      color: hasPic
                          ? null
                          : const Color.fromRGBO(76, 175, 80, 0.1),
                      image: hasPic
                          ? DecorationImage(
                              image: FileImage(
                                  File(profile.propertyPictures[0])),
                              fit: BoxFit.cover,
                            )
                          : null,
                    ),
                    child: hasPic
                        ? null
                        : Icon(Ionicons.business,
                            size: Responsive.normalize(context, 40),
                            color: AppColors.primary),
                  ),
                  Positioned(
                    right: 0,
                    bottom: 0,
                    child: Container(
                      width: Responsive.normalize(context, 40),
                      height: Responsive.normalize(context, 40),
                      decoration: BoxDecoration(
                        color: AppColors.primary,
                        shape: BoxShape.circle,
                        border: Border.all(color: Colors.white, width: 3),
                      ),
                      child: Icon(Ionicons.camera,
                          size: Responsive.normalize(context, 20),
                          color: Colors.white),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),
            Text(
                Platform.isMacOS || Platform.isWindows || Platform.isLinux
                    ? 'Click to add property picture'
                    : 'Tap to add property picture',
                style: TextStyle(
                    fontSize: 16,
                    color: AppColors.text,
                    fontWeight: FontWeight.w600)),
            const SizedBox(height: 8),
            Text('This will be displayed in property listings',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 14, color: AppColors.textSecondary)),
            const SizedBox(height: 8),
            const Text('Property picture is optional - you can add it later',
                textAlign: TextAlign.center,
                style: TextStyle(
                    fontSize: 12,
                    color: Color(0xFF888888),
                    fontStyle: FontStyle.italic)),
          ],
        ),
      ),
      const SizedBox(height: 24),
      _input(context, 'Property Name *', propertyName, 'Enter property name',
          (v) => onChange('propertyName', v), errs['propertyName']),
      _input(context, 'Property Owner Name', ownerName,
          'Enter property owner name (optional)', (v) => onChange('ownerName', v),
          null),
      _input(context, 'Property Address *', address, 'Enter property address',
          (v) => onChange('address', v), errs['address'],
          maxLines: 4),
      const SizedBox(height: 8),
      Row(
        children: [
          Expanded(
            child: _secondaryButton(
                context, 'Back', Icons.arrow_back, onBack),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: _primaryButton(
              context,
              label: submitting ? 'Saving...' : 'Save Profile',
              icon: submitting ? Ionicons.hourglass : Ionicons.checkmark,
              iconColor: (valid && !submitting)
                  ? Colors.white
                  : AppColors.buttonDisabledText,
              onTap: (valid && !submitting) ? onSave : null,
            ),
          ),
        ],
      ),
    ],
  );
}

Widget _input(
  BuildContext context,
  String label,
  TextEditingController controller,
  String hint,
  ValueChanged<String> onChanged,
  String? error, {
  TextInputType keyboard = TextInputType.text,
  int maxLines = 1,
}) {
  return Padding(
    padding: const EdgeInsets.only(bottom: 16),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label,
            style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w600,
                color: AppColors.textSecondary)),
        const SizedBox(height: 8),
        TextField(
          controller: controller,
          onChanged: onChanged,
          keyboardType: keyboard,
          maxLines: maxLines,
          style: TextStyle(
              fontSize: Responsive.font(context, 16), color: AppColors.text),
          decoration: InputDecoration(
            hintText: hint,
            hintStyle: TextStyle(color: AppColors.textMuted),
            filled: true,
            fillColor: AppColors.surface,
            contentPadding:
                const EdgeInsets.symmetric(horizontal: 12, vertical: 16),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: BorderSide(color: AppColors.border),
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: BorderSide(
                  color: error != null
                      ? AppColors.error
                      : AppColors.border),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: BorderSide(
                  color: error != null
                      ? AppColors.error
                      : const Color.fromRGBO(255, 255, 255, 0.4)),
            ),
          ),
        ),
        if (error != null)
          Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Text(error,
                style: const TextStyle(
                    fontSize: 12, color: Color(0xFFFF6B6B))),
          ),
      ],
    ),
  );
}

Widget _primaryButton(
  BuildContext context, {
  required String label,
  required IconData icon,
  required Color iconColor,
  required VoidCallback? onTap,
}) {
  final enabled = onTap != null;
  return Opacity(
    opacity: enabled ? 1 : 0.6,
    child: Container(
      height: 44,
      decoration: BoxDecoration(
        color: enabled ? AppColors.primary : AppColors.buttonDisabled,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(12),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Flexible(
                    child: Text(label,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w600,
                            letterSpacing: 0.2,
                            color: AppColors.buttonPrimaryText))),
                const SizedBox(width: 8),
                Icon(icon, size: Responsive.normalize(context, 20), color: iconColor),
              ],
            ),
          ),
        ),
      ),
    ),
  );
}

Widget _secondaryButton(BuildContext context, String label, IconData icon,
    VoidCallback onTap) {
  return SizedBox(
    height: 44,
    child: OutlinedButton.icon(
      style: OutlinedButton.styleFrom(
        backgroundColor: AppColors.buttonSecondary,
        side: BorderSide(color: AppColors.border),
        foregroundColor: AppColors.buttonSecondaryText,
        padding: const EdgeInsets.symmetric(horizontal: 16),
        shape:
            RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
      icon: Icon(icon, size: Responsive.normalize(context, 20)),
      label: Text(label,
          style: const TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w600,
              letterSpacing: 0.2)),
      onPressed: onTap,
    ),
  );
}
