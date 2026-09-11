import 'package:flutter_riverpod/flutter_riverpod.dart';

const _maxPins = 10;
const _maxRecent = 10;

class SearchPreferences {
  final List<String> pinnedMedicineIds;
  final List<String> recentSearches;

  const SearchPreferences({
    this.pinnedMedicineIds = const ['med_001', 'med_002', 'med_004'],
    this.recentSearches = const [],
  });

  SearchPreferences copyWith({
    List<String>? pinnedMedicineIds,
    List<String>? recentSearches,
  }) {
    return SearchPreferences(
      pinnedMedicineIds: pinnedMedicineIds ?? this.pinnedMedicineIds,
      recentSearches: recentSearches ?? this.recentSearches,
    );
  }
}

class SearchPreferencesNotifier extends StateNotifier<SearchPreferences> {
  SearchPreferencesNotifier() : super(const SearchPreferences());

  void togglePin(String medicineId) {
    final pins = List<String>.from(state.pinnedMedicineIds);
    if (pins.contains(medicineId)) {
      pins.remove(medicineId);
    } else {
      if (pins.length >= _maxPins) pins.removeAt(0);
      pins.add(medicineId);
    }
    state = state.copyWith(pinnedMedicineIds: pins);
  }

  void addRecentSearch(String query) {
    if (query.trim().isEmpty) return;
    final recents = List<String>.from(state.recentSearches)
      ..removeWhere((q) => q == query)
      ..insert(0, query);
    if (recents.length > _maxRecent) {
      recents.removeRange(_maxRecent, recents.length);
    }
    state = state.copyWith(recentSearches: recents);
  }
}

final searchPreferencesProvider =
    StateNotifierProvider<SearchPreferencesNotifier, SearchPreferences>((ref) {
  return SearchPreferencesNotifier();
});
