import 'package:flutter_test/flutter_test.dart';
import 'package:swift_music/features/catalog/data/demo_catalog_repository.dart';

void main() {
  final catalog = DemoCatalogRepository();
  test('search trims input and matches title or artist case-insensitively', () {
    expect(catalog.search('  MIDNIGHT  ').single.id, 'demo-1');
    expect(catalog.search('soundhelix').length, 6);
    expect(catalog.search('missing recording'), isEmpty);
  });
  test('genre and query filters are combined', () {
    expect(catalog.search('heart', genre: 'Electronic').single.id, 'demo-2');
    expect(catalog.search('heart', genre: 'Jazz'), isEmpty);
    expect(catalog.search(''), hasLength(6));
  });
}
