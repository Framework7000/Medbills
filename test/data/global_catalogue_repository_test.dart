import 'package:flutter_test/flutter_test.dart';
import 'package:nuskha_pms/data/repositories/global_catalogue_repository.dart';

void main() {
  test('declares the full catalogue size the seed stands in for', () {
    expect(GlobalCatalogueRepository.totalCatalogueCount, 253973);
  });

  test('searchCatalogue filters by name and generic name', () {
    final repo = GlobalCatalogueRepository();
    final results = repo.searchCatalogue('paracetamol');
    expect(results, isNotEmpty);
    expect(results.every((m) =>
        m.name.toLowerCase().contains('paracetamol') ||
        m.genericName.toLowerCase().contains('paracetamol')), isTrue);
  });
}
