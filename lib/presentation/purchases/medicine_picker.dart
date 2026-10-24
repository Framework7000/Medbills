import 'package:flutter/material.dart';
import 'package:phosphoricons_flutter/phosphoricons_flutter.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/repositories/global_catalogue_repository.dart';
import '../../domain/models/medicine.dart';
import '../../domain/models/schedule_type.dart';
import '../../domain/services/pack_units.dart';
import '../../domain/services/stock_summary.dart';
import '../../state/providers.dart';
import '../inventory/medicine_edit_dialog.dart';
import '../theme.dart';

/// Choose a medicine from the store, the master catalogue (it is added to
/// the store when stock is received), or create a new one.
Future<PickedMedicine?> pickMedicine(BuildContext context, {String initialQuery = ''}) =>
    showDialog<PickedMedicine>(context: context, builder: (_) => _MedicinePicker(initialQuery: initialQuery));

class PickedMedicine {
  const PickedMedicine(this.medicine, this.referenceMrpPaise);
  final Medicine medicine;
  final int referenceMrpPaise;
}

class _MedicinePicker extends ConsumerStatefulWidget {
  const _MedicinePicker({this.initialQuery = ''});
  final String initialQuery;

  @override
  ConsumerState<_MedicinePicker> createState() => _MedicinePickerState();
}

class _MedicinePickerState extends ConsumerState<_MedicinePicker> {
  late final _query = TextEditingController(text: widget.initialQuery);

  @override
  void dispose() {
    _query.dispose();
    super.dispose();
  }

  Future<void> _createNew() async {
    final repo = ref.read(repositoryProvider)!;
    final draft = Medicine(
      id: repo.newMedicineId(),
      storeId: repo.storeId,
      name: _query.text.trim(),
      genericName: '',
      manufacturer: '',
      type: '',
      packSizeLabel: '',
      unitsPerPack: 1,
      hsnCode: '3004',
      gstRate: 5.0,
      scheduleType: ScheduleType.unknown,
      minStock: 0,
      shelfLocation: '',
      updatedAt: DateTime.now(),
    );
    final created = await showMedicineEditor(context, initial: draft, isNew: true, save: false);
    if (created != null && mounted) Navigator.pop(context, PickedMedicine(created, 0));
  }

  /// A medicine from the all-India list isn't hand-checked: the pharmacist
  /// confirms its schedule, GST and pack before it joins the store.
  Future<void> _confirmFromIndia(CatalogueEntry e) async {
    final confirmed = await showMedicineEditor(context, initial: e.medicine, isNew: true, save: false);
    if (confirmed != null && mounted) Navigator.pop(context, PickedMedicine(confirmed, e.referenceMrpPaise));
  }

  @override
  Widget build(BuildContext context) {
    final index = ref.watch(stockIndexProvider).valueOrNull ?? const <String, StockSummary>{};
    final catalogue = ref.watch(catalogueProvider);
    final q = _query.text.trim().toLowerCase();
    final storeMatches = index.values
        .where((s) => q.isEmpty || s.medicine.name.toLowerCase().contains(q) || s.medicine.genericName.toLowerCase().contains(q))
        .toList()
      ..sort((a, b) => a.medicine.name.toLowerCase().compareTo(b.medicine.name.toLowerCase()));
    final inStoreCatalogueIds = index.values.map((s) => s.medicine.catalogueId ?? s.medicine.id).toSet();
    final List<CatalogueEntry> catalogueMatches = q.isEmpty
        ? const []
        : catalogue.search(q).where((e) => !inStoreCatalogueIds.contains(e.medicine.id)).toList();
    // All medicines in India, once the query is specific enough to be useful.
    final india = ref.watch(indiaCatalogueProvider);
    final shownNames = {...storeMatches.map((s) => s.medicine.name.toLowerCase()), ...catalogueMatches.map((e) => e.medicine.name.toLowerCase())};
    final List<CatalogueEntry> indiaMatches = q.length < 3
        ? const []
        : (india.valueOrNull?.search(q) ?? const <CatalogueEntry>[])
            .where((e) => !inStoreCatalogueIds.contains(e.medicine.id) && !shownNames.contains(e.medicine.name.toLowerCase()))
            .toList();
    final text = Theme.of(context).textTheme;

    return AlertDialog(
      title: const Text('Choose medicine'),
      contentPadding: const EdgeInsets.fromLTRB(Space.xl, Space.l, Space.xl, 0),
      content: SizedBox(
        width: 480,
        height: 460,
        child: Column(children: [
          TextField(
            controller: _query,
            autofocus: true,
            decoration: const InputDecoration(hintText: 'Search brand or generic', prefixIcon: Icon(PhosphorIconsRegular.magnifyingGlass)),
            onChanged: (_) => setState(() {}),
          ),
          const SizedBox(height: Space.s),
          Expanded(
            child: ListView(children: [
              if (storeMatches.isNotEmpty) Padding(
                padding: const EdgeInsets.symmetric(vertical: Space.s),
                child: Text('In your store', style: text.labelLarge?.copyWith(color: AppColors.muted)),
              ),
              for (final s in storeMatches.take(50))
                ListTile(
                  dense: true,
                  title: Text(s.medicine.name, overflow: TextOverflow.ellipsis),
                  subtitle: Text('${s.medicine.packSizeLabel} · ${PackUnits.describe(s.sellableUnits, s.medicine.unitsPerPack)} in stock',
                      overflow: TextOverflow.ellipsis),
                  onTap: () => Navigator.pop(
                    context,
                    PickedMedicine(s.medicine, s.nextBatch?.mrpPaise ?? (s.batches.isEmpty ? 0 : s.batches.last.mrpPaise)),
                  ),
                ),
              if (catalogueMatches.isNotEmpty) Padding(
                padding: const EdgeInsets.symmetric(vertical: Space.s),
                child: Text('Master catalogue (adds to your store)', style: text.labelLarge?.copyWith(color: AppColors.muted)),
              ),
              for (final e in catalogueMatches.take(50))
                ListTile(
                  dense: true,
                  title: Text(e.medicine.name, overflow: TextOverflow.ellipsis),
                  subtitle: Text('${e.medicine.manufacturer} · ${e.medicine.packSizeLabel}', overflow: TextOverflow.ellipsis),
                  trailing: const Icon(PhosphorIconsRegular.plusCircle),
                  onTap: () => Navigator.pop(context, PickedMedicine(e.medicine, e.referenceMrpPaise)),
                ),
              if (indiaMatches.isNotEmpty) Padding(
                padding: const EdgeInsets.symmetric(vertical: Space.s),
                child: Text('All medicines in India (check before first sale)',
                    style: text.labelLarge?.copyWith(color: AppColors.muted)),
              ),
              for (final e in indiaMatches)
                ListTile(
                  dense: true,
                  title: Text(e.medicine.name, overflow: TextOverflow.ellipsis),
                  subtitle: Text('${e.medicine.genericName} · ${e.medicine.manufacturer} · ${e.medicine.packSizeLabel}',
                      maxLines: 2, overflow: TextOverflow.ellipsis),
                  trailing: const Icon(PhosphorIconsRegular.plusCircle),
                  onTap: () => _confirmFromIndia(e),
                ),
              if (q.length >= 3 && india.isLoading)
                const Padding(
                  padding: EdgeInsets.all(Space.m),
                  child: Text('Loading all medicines in India…', textAlign: TextAlign.center),
                ),
              if (storeMatches.isEmpty && catalogueMatches.isEmpty && indiaMatches.isEmpty && !india.isLoading)
                const Padding(
                  padding: EdgeInsets.all(Space.xl),
                  child: Text('Nothing found. Create it as a new medicine.', textAlign: TextAlign.center),
                ),
            ]),
          ),
        ]),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
        OutlinedButton.icon(onPressed: _createNew, icon: const Icon(PhosphorIconsRegular.plus), label: const Text('New medicine')),
      ],
    );
  }
}

