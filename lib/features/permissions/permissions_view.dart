import 'package:flutter/material.dart';
import 'package:permission_handler/permission_handler.dart';
import '../../core/theme/app_colors.dart';
import '../../services/biometric_auth.dart';
import '../../services/notification_service.dart';

/// Port of `src/screens/PermissionSettingsScreen.tsx` — lists
/// notification / biometric / camera / mediaLibrary / location statuses
/// with request + open-settings actions.
class PermissionsView extends StatefulWidget {
  const PermissionsView({super.key});
  @override
  State<PermissionsView> createState() => _PermissionsViewState();
}

class _PermissionsViewState extends State<PermissionsView> {
  Map<String, String> _status = {};
  bool _loading = true;
  bool _biometricHw = false;

  @override
  void initState() {
    super.initState();
    _refresh();
  }

  Future<void> _refresh() async {
    if (!mounted) return;
    setState(() => _loading = true);
    final entries = <String, Future<PermissionStatus>>{
      'notifications': Permission.notification.status,
      'camera': Permission.camera.status,
      'photos': Permission.photos.status,
      'location': Permission.locationWhenInUse.status,
      'microphone': Permission.microphone.status,
    };
    final out = <String, String>{};
    for (final e in entries.entries) {
      try {
        final s = await e.value;
        out[e.key] = s.name;
      } catch (_) {
        out[e.key] = 'unknown';
      }
    }
    bool hw = false;
    try {
      hw = await BiometricAuth.isAvailable;
    } catch (_) {}
    if (mounted) {
      setState(() {
        _status = out;
        _biometricHw = hw;
        _loading = false;
      });
    }
  }

  Future<void> _request(String key, Permission p) async {
    try {
      final result = await p.request();
      // A permanently denied permission never shows system UI again; the only
      // recovery path is the app settings screen.
      if (result.isPermanentlyDenied) {
        await openAppSettings();
      }
    } catch (_) {
      try {
        await openAppSettings();
      } catch (_) {}
    }
    await _refresh();
  }

  Future<void> _testNotification() async {
    await NotificationService.immediate(
      id: 999999,
      channel: 'maintenance',
      title: 'RentManager',
      body: 'Notifications are working.',
    );
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        body: SafeArea(
          child: Column(children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(10, 8, 10, 0),
              child: Row(children: [
                IconButton(
                  icon: const Icon(Icons.arrow_back),
                  onPressed: () => Navigator.pop(context),
                ),
                const Expanded(
                  child: Text('Permissions',
                      style: TextStyle(
                          fontSize: 20, fontWeight: FontWeight.w800)),
                ),
                IconButton(
                    icon: Icon(Icons.refresh,
                        color: AppColors.iconSecondary),
                    onPressed: _refresh),
              ]),
            ),
            if (_loading)
              const Expanded(
                  child: Center(child: CircularProgressIndicator()))
            else
              Expanded(
                child: ListView(children: [
                  _row('Notifications', 'notifications',
                      Icons.notifications_outlined, Permission.notification,
                      extra: TextButton(
                          onPressed: _testNotification,
                          child: const Text('Send test'))),
                  _row('Camera', 'camera', Icons.photo_camera_outlined,
                      Permission.camera),
                  _row('Photos / Media', 'photos',
                      Icons.photo_library_outlined, Permission.photos),
                  _row('Location', 'location',
                      Icons.location_on_outlined,
                      Permission.locationWhenInUse),
                  _row('Microphone', 'microphone', Icons.mic_outlined,
                      Permission.microphone),
                  ListTile(
                    leading: Icon(Icons.fingerprint,
                        color: AppColors.iconSecondary),
                    title: const Text('Biometric Authentication'),
                    subtitle: Text(
                        _biometricHw
                            ? 'Hardware available'
                            : 'Not available on this device',
                        style: TextStyle(
                            color: AppColors.textSecondary,
                            fontSize: 12)),
                    trailing: Icon(
                        _biometricHw
                            ? Icons.check_circle
                            : Icons.cancel,
                        color: _biometricHw
                            ? AppColors.success
                            : AppColors.textMuted),
                  ),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 16),
                    child: OutlinedButton.icon(
                      icon: const Icon(Icons.settings_outlined),
                      label: const Text('Open System Settings'),
                      onPressed: openAppSettings,
                    ),
                  ),
                ]),
              ),
          ]),
        ),
      );

  Widget _row(String title, String key, IconData icon, Permission p,
      {Widget? extra}) {
    final st = _status[key] ?? 'unknown';
    final granted = st == 'granted' || st == 'limited';
    return ListTile(
      leading: Icon(icon, color: AppColors.iconSecondary),
      title: Text(title),
      subtitle: Text(st,
          style: TextStyle(
              color: granted
                  ? AppColors.success
                  : AppColors.warning,
              fontSize: 12)),
      trailing: Row(mainAxisSize: MainAxisSize.min, children: [
        ?extra,
        if (!granted)
          TextButton(
              onPressed: () => _request(key, p),
              child: const Text('Allow'))
        else
          const Icon(Icons.check_circle,
              color: AppColors.success),
      ]),
    );
  }
}
