import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/auth_service.dart';
import '../../domain/models/app_user.dart';
import '../../domain/models/store_profile.dart';
import '../../state/providers.dart';
import '../theme.dart';
import '../widgets/common.dart';

class SettingsScreen extends ConsumerWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final user = ref.watch(currentUserProvider);
    final store = ref.watch(storeProvider);
    final auth = ref.watch(authServiceProvider);
    final cloud = ref.watch(cloudModeProvider);
    final text = Theme.of(context).textTheme;
    if (user == null) return const SizedBox.shrink();

    return Scaffold(
      appBar: AppBar(title: const Text('Settings')),
      body: Align(
        alignment: Alignment.topCenter,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 720),
          child: ListView(
            padding: const EdgeInsets.all(Space.l),
            children: [
              Card(
                child: Column(children: [
                  ListTile(
                    leading: const CircleAvatar(child: Icon(Icons.person_outline)),
                    title: Text(user.name, overflow: TextOverflow.ellipsis),
                    subtitle: Text('${user.role.label}${user.email.isEmpty ? '' : ' · ${user.email}'}',
                        maxLines: 2, overflow: TextOverflow.ellipsis),
                  ),
                  const Divider(),
                  ListTile(
                    leading: Icon(cloud ? Icons.cloud_done_outlined : Icons.cloud_off_outlined,
                        color: cloud ? AppColors.accent : AppColors.muted),
                    title: Text(cloud ? 'Synced across all store devices' : 'Demo mode'),
                    subtitle: Text(cloud
                        ? 'Bills, stock and udhaar update live on every phone and computer signed in to this store. '
                            'Stock and bills stay viewable offline; completing a sale needs internet so two counters can never sell the same strip.'
                        : 'Sample data kept only in this browser tab. Install the app and sign in to use the shared store.'),
                  ),
                ]),
              ),
              const SizedBox(height: Space.l),
              Text('Store', style: text.titleMedium),
              const SizedBox(height: Space.s),
              Card(
                child: AsyncBody<StoreProfile>(
                  value: store,
                  builder: (p) => Column(children: [
                    ListTile(
                      leading: const Icon(Icons.storefront_outlined),
                      title: Text(p.name, overflow: TextOverflow.ellipsis),
                      subtitle: Text(
                        [
                          if (p.fullAddress.isNotEmpty) p.fullAddress,
                          if (p.phone.isNotEmpty) 'Phone ${p.phone}',
                          if (p.gstin.isNotEmpty) 'GSTIN ${p.gstin}',
                          if (p.drugLicenseNumbers.isNotEmpty) 'DL ${p.drugLicenseNumbers}',
                        ].join('\n').ifEmpty('Add address, GSTIN and drug licence — they print on every bill.'),
                      ),
                      isThreeLine: true,
                      trailing: user.role.canEditStore
                          ? IconButton(
                              tooltip: 'Edit store details',
                              icon: const Icon(Icons.edit_outlined),
                              onPressed: () => showDialog<void>(context: context, builder: (_) => _StoreDialog(profile: p)),
                            )
                          : null,
                    ),
                  ]),
                ),
              ),
              const SizedBox(height: Space.l),
              Text('Account', style: text.titleMedium),
              const SizedBox(height: Space.s),
              Card(
                child: Column(children: [
                  if (auth is DemoAuthService) ...[
                    ListTile(
                      leading: const Icon(Icons.switch_account_outlined),
                      title: const Text('Try as another role'),
                      subtitle: const Text('See what counter staff and pharmacists can do.'),
                      trailing: DropdownButton<UserRole>(
                        value: user.role,
                        underline: const SizedBox.shrink(),
                        items: [for (final r in UserRole.values) DropdownMenuItem(value: r, child: Text(r.label))],
                        onChanged: (r) {
                          if (r != null) auth.switchRole(r);
                        },
                      ),
                    ),
                  ] else ...[
                    ListTile(
                      leading: const Icon(Icons.password_outlined),
                      title: const Text('Change password'),
                      trailing: const Icon(Icons.chevron_right),
                      onTap: () => showDialog<void>(context: context, builder: (_) => const _PasswordDialog()),
                    ),
                    const Divider(),
                    ListTile(
                      leading: const Icon(Icons.logout, color: AppColors.danger),
                      title: const Text('Sign out', style: TextStyle(color: AppColors.danger)),
                      onTap: () async {
                        final ok = await confirmDialog(context,
                            title: 'Sign out?',
                            message: 'The bill in progress on this device will be cleared.',
                            confirmLabel: 'Sign out',
                            danger: true);
                        if (ok) await auth.signOut();
                      },
                    ),
                  ],
                ]),
              ),
              const SizedBox(height: Space.l),
              Text(
                'Staff accounts are created by the owner with the setup script (see README). '
                'Sales are never deleted — cancelled bills keep their reason and who cancelled them.',
                style: text.bodySmall?.copyWith(color: AppColors.muted),
              ),
              const SizedBox(height: Space.s),
              Text('MedBills 1.1.0', style: text.bodySmall?.copyWith(color: AppColors.muted)),
            ],
          ),
        ),
      ),
    );
  }
}

extension on String {
  String ifEmpty(String fallback) => isEmpty ? fallback : this;
}

class _StoreDialog extends ConsumerStatefulWidget {
  const _StoreDialog({required this.profile});
  final StoreProfile profile;

  @override
  ConsumerState<_StoreDialog> createState() => _StoreDialogState();
}

class _StoreDialogState extends ConsumerState<_StoreDialog> {
  final _formKey = GlobalKey<FormState>();
  late final _name = TextEditingController(text: widget.profile.name);
  late final _address = TextEditingController(text: widget.profile.addressLine);
  late final _city = TextEditingController(text: widget.profile.city);
  late final _state = TextEditingController(text: widget.profile.state.isEmpty ? 'Madhya Pradesh' : widget.profile.state);
  late final _phone = TextEditingController(text: widget.profile.phone);
  late final _gstin = TextEditingController(text: widget.profile.gstin);
  late final _dl = TextEditingController(text: widget.profile.drugLicenseNumbers);
  bool _busy = false;

  static final _gstinPattern = RegExp(r'^\d{2}[A-Z]{5}\d{4}[A-Z][1-9A-Z]Z[0-9A-Z]$');

  @override
  void dispose() {
    for (final c in [_name, _address, _city, _state, _phone, _gstin, _dl]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _busy = true);
    try {
      await ref.read(repositoryProvider)!.updateStore(widget.profile.copyWith(
            name: _name.text.trim(),
            addressLine: _address.text.trim(),
            city: _city.text.trim(),
            state: _state.text.trim(),
            phone: _phone.text.trim(),
            gstin: _gstin.text.trim().toUpperCase(),
            drugLicenseNumbers: _dl.text.trim(),
          ));
      if (mounted) Navigator.pop(context);
    } catch (e) {
      if (mounted) showMessage(context, friendlyError(e), error: true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    const gap = SizedBox(height: Space.m);
    return AlertDialog(
      title: const Text('Store details'),
      content: DialogBody(
        maxWidth: 520,
        child: Form(
          key: _formKey,
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            TextFormField(
              controller: _name,
              decoration: const InputDecoration(labelText: 'Store name'),
              textCapitalization: TextCapitalization.words,
              validator: (v) => (v ?? '').trim().isEmpty ? 'Required' : null,
            ),
            gap,
            TextFormField(controller: _address, decoration: const InputDecoration(labelText: 'Address')),
            gap,
            TextFormField(controller: _city, decoration: const InputDecoration(labelText: 'City')),
            gap,
            TextFormField(controller: _state, decoration: const InputDecoration(labelText: 'State')),
            gap,
            TextFormField(
              controller: _phone,
              decoration: const InputDecoration(labelText: 'Phone'),
              keyboardType: TextInputType.phone,
              inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[0-9+ ]')), LengthLimitingTextInputFormatter(15)],
            ),
            gap,
            TextFormField(
              controller: _gstin,
              decoration: const InputDecoration(labelText: 'GSTIN', hintText: '23ABCDE1234F1Z5'),
              textCapitalization: TextCapitalization.characters,
              inputFormatters: [LengthLimitingTextInputFormatter(15)],
              validator: (v) {
                final value = (v ?? '').trim().toUpperCase();
                if (value.isEmpty) return null;
                return _gstinPattern.hasMatch(value) ? null : 'GSTIN is 15 characters, e.g. 23ABCDE1234F1Z5';
              },
            ),
            gap,
            TextFormField(
              controller: _dl,
              decoration: const InputDecoration(labelText: 'Drug licence numbers', hintText: '20B/…, 21B/…'),
            ),
          ]),
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
        FilledButton(onPressed: _busy ? null : _save, child: const Text('Save')),
      ],
    );
  }
}

class _PasswordDialog extends ConsumerStatefulWidget {
  const _PasswordDialog();

  @override
  ConsumerState<_PasswordDialog> createState() => _PasswordDialogState();
}

class _PasswordDialogState extends ConsumerState<_PasswordDialog> {
  final _formKey = GlobalKey<FormState>();
  final _current = TextEditingController();
  final _next = TextEditingController();
  final _confirm = TextEditingController();
  bool _busy = false;

  @override
  void dispose() {
    _current.dispose();
    _next.dispose();
    _confirm.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _busy = true);
    try {
      await ref.read(authServiceProvider).changePassword(_current.text, _next.text);
      if (mounted) {
        Navigator.pop(context);
        showMessage(context, 'Password changed.');
      }
    } catch (e) {
      if (mounted) showMessage(context, friendlyError(e), error: true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    const gap = SizedBox(height: Space.m);
    return AlertDialog(
      title: const Text('Change password'),
      content: DialogBody(
        child: Form(
          key: _formKey,
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            TextFormField(
              controller: _current,
              obscureText: true,
              autofillHints: const [AutofillHints.password],
              decoration: const InputDecoration(labelText: 'Current password'),
              validator: (v) => (v ?? '').isEmpty ? 'Required' : null,
            ),
            gap,
            TextFormField(
              controller: _next,
              obscureText: true,
              autofillHints: const [AutofillHints.newPassword],
              decoration: const InputDecoration(labelText: 'New password', helperText: 'At least 8 characters'),
              validator: (v) => (v ?? '').length < 8 ? 'At least 8 characters' : null,
            ),
            gap,
            TextFormField(
              controller: _confirm,
              obscureText: true,
              decoration: const InputDecoration(labelText: 'Repeat new password'),
              validator: (v) => v != _next.text ? 'Passwords don\'t match' : null,
            ),
          ]),
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
        FilledButton(onPressed: _busy ? null : _save, child: const Text('Change')),
      ],
    );
  }
}
