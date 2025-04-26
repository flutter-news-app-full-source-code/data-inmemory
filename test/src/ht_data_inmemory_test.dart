//
// ignore_for_file: avoid_equals_and_hash_code_on_mutable_classes, lines_longer_than_80_chars

import 'package:ht_data_inmemory/src/ht_data_inmemory.dart';
import 'package:ht_http_client/ht_http_client.dart'
    show BadRequestException, NotFoundException;
import 'package:test/test.dart';

// Simple private model for testing purposes
class _TestModel {
  const _TestModel({required this.id, required this.value, this.category});
  final String id;
  final String value;
  final String? category;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is _TestModel &&
          runtimeType == other.runtimeType &&
          id == other.id &&
          value == other.value &&
          category == other.category;

  @override
  int get hashCode => id.hashCode ^ value.hashCode ^ category.hashCode;

  @override
  String toString() {
    return '_TestModel{id: $id, value: $value, category: $category}';
  }
}

// Helper functions for the test model
Map<String, dynamic> _testModelToJson(_TestModel item) => {
      'id': item.id,
      'value': item.value,
      if (item.category != null) 'category': item.category,
    };

String _getTestModelId(_TestModel item) => item.id;

void main() {
  group('HtDataInMemoryClient', () {
    late HtDataInMemoryClient<_TestModel> client;
    const item1 = _TestModel(id: 'id1', value: 'value1', category: 'A');
    const item2 = _TestModel(id: 'id2', value: 'value2', category: 'B');
    const item3 = _TestModel(id: 'id3', value: 'value3', category: 'A');

    setUp(() {
      client = HtDataInMemoryClient<_TestModel>(
        toJson: _testModelToJson,
        getId: _getTestModelId,
      );
    });

    group('create', () {
      test('should create and return the item', () async {
        final createdItem = await client.create(item1);
        expect(createdItem, equals(item1));
        // Verify it can be read back
        expect(await client.read(item1.id), equals(item1));
      });

      test('should throw BadRequestException if item with ID already exists',
          () async {
        await client.create(item1); // Create first time
        // Attempt to create again with the same ID
        expect(
          () => client.create(item1),
          throwsA(isA<BadRequestException>()),
        );
      });
    });

    group('read', () {
      setUp(() async {
        // Pre-populate for read tests
        await client.create(item1);
        await client.create(item2);
      });

      test('should return the item if ID exists', () async {
        expect(await client.read(item1.id), equals(item1));
        expect(await client.read(item2.id), equals(item2));
      });

      test('should throw NotFoundException if ID does not exist', () async {
        expect(
          () => client.read('non_existent_id'),
          throwsA(isA<NotFoundException>()),
        );
      });
    });

    group('readAll', () {
      test('should return empty list when client is empty', () async {
        expect(await client.readAll(), isEmpty);
      });

      test('should return all items when client has data', () async {
        await client.create(item1);
        await client.create(item2);
        await client.create(item3);
        final result = await client.readAll();
        expect(result, hasLength(3));
        expect(result, containsAll([item1, item2, item3]));
      });

      test('should return items with limit', () async {
        await client.create(item1);
        await client.create(item2);
        await client.create(item3);
        final result = await client.readAll(limit: 2);
        expect(result, hasLength(2));
        // Order isn't guaranteed by Map.values, so check if it's any valid combo
        expect(
          result,
          anyOf([
            containsAll([item1, item2]),
            containsAll([item1, item3]),
            containsAll([item2, item3]),
          ]),
        );
      });

      test('should return items after startAfterId', () async {
        await client.create(item1);
        await client.create(item2);
        await client.create(item3);
        // Need to know the internal order to test reliably, let's read all first
        final allItems = await client.readAll();
        final firstItemId = allItems[0].id;
        final result = await client.readAll(startAfterId: firstItemId);
        expect(result, hasLength(allItems.length - 1));
        expect(result, isNot(contains(allItems[0])));
      });

      test('should return items after startAfterId with limit', () async {
        await client.create(item1);
        await client.create(item2);
        await client.create(item3);
        final allItems = await client.readAll(); // Get items to know order
        final firstItemId = allItems[0].id;
        final result =
            await client.readAll(startAfterId: firstItemId, limit: 1);
        expect(result, hasLength(1));
        expect(result.first, equals(allItems[1])); // Expect the second item
      });

      test('should return empty list if startAfterId does not exist', () async {
        await client.create(item1);
        final result = await client.readAll(startAfterId: 'non_existent_id');
        expect(result, isEmpty);
      });

      test('should return empty list if startAfterId is the last item',
          () async {
        await client.create(item1);
        await client.create(item2);
        final allItems = await client.readAll();
        final lastItemId = allItems.last.id;
        final result = await client.readAll(startAfterId: lastItemId);
        expect(result, isEmpty);
      });
    });

    group('readAllByQuery', () {
      setUp(() async {
        // Pre-populate for query tests
        await client.create(item1); // category: A
        await client.create(item2); // category: B
        await client.create(item3); // category: A
      });

      test('should return all items if query is empty', () async {
        final result = await client.readAllByQuery({});
        expect(result, hasLength(3));
        expect(result, containsAll([item1, item2, item3]));
      });

      test('should return items matching a single query parameter', () async {
        final result = await client.readAllByQuery({'category': 'A'});
        expect(result, hasLength(2));
        expect(result, containsAll([item1, item3]));
        expect(result, isNot(contains(item2)));
      });

      test('should return items matching multiple query parameters', () async {
        final result =
            await client.readAllByQuery({'category': 'A', 'value': 'value1'});
        expect(result, hasLength(1));
        expect(result, contains(item1));
      });

      test('should return empty list if no items match query', () async {
        final result = await client.readAllByQuery({'category': 'C'});
        expect(result, isEmpty);
      });

      test('should return empty list if query key does not exist in items',
          () async {
        final result =
            await client.readAllByQuery({'non_existent_key': 'value'});
        expect(result, isEmpty);
      });

      test('should apply pagination to query results (limit)', () async {
        final result = await client.readAllByQuery({'category': 'A'}, limit: 1);
        expect(result, hasLength(1));
        // Check if it's either item1 or item3
        expect(result.first == item1 || result.first == item3, isTrue);
      });

      test('should apply pagination to query results (startAfterId)', () async {
        // Get the items matching the query first to know the order
        final matchingItems = await client.readAllByQuery({'category': 'A'});
        final firstMatchingId = matchingItems[0].id;
        final result = await client
            .readAllByQuery({'category': 'A'}, startAfterId: firstMatchingId);
        expect(result, hasLength(1));
        expect(
          result.first,
          equals(matchingItems[1]),
        ); // Should be the second match
      });

      test('should apply pagination to query results (startAfterId + limit)',
          () async {
        final matchingItems = await client.readAllByQuery({'category': 'A'});
        final firstMatchingId = matchingItems[0].id;
        // Limit is 0, should return empty
        final result = await client.readAllByQuery(
          {'category': 'A'},
          startAfterId: firstMatchingId,
          limit: 0,
        );
        expect(result, isEmpty);
      });
    });

    group('update', () {
      setUp(() async {
        // Pre-populate for update tests
        await client.create(item1);
      });

      test('should update and return the item if ID exists', () async {
        const updatedItem = _TestModel(id: 'id1', value: 'updated_value');
        final result = await client.update(item1.id, updatedItem);
        expect(result, equals(updatedItem));
        // Verify the stored item is updated
        expect(await client.read(item1.id), equals(updatedItem));
      });

      test('should throw NotFoundException if ID does not exist', () async {
        const itemToUpdate = _TestModel(id: 'non_existent_id', value: 'value');
        expect(
          () => client.update('non_existent_id', itemToUpdate),
          throwsA(isA<NotFoundException>()),
        );
      });

      test('should throw BadRequestException if item ID does not match path ID',
          () async {
        // ID in path is item1.id ('id1'), but item has 'id_mismatch'
        const mismatchedItem = _TestModel(id: 'id_mismatch', value: 'value');
        expect(
          () => client.update(item1.id, mismatchedItem),
          throwsA(isA<BadRequestException>()),
        );
      });
    });

    group('delete', () {
      setUp(() async {
        // Pre-populate for delete tests
        await client.create(item1);
        await client.create(item2);
      });

      test('should delete the item if ID exists', () async {
        await client.delete(item1.id);
        // Verify it's gone
        expect(
          () => client.read(item1.id),
          throwsA(isA<NotFoundException>()),
        );
        // Verify other items remain
        expect(await client.read(item2.id), equals(item2));
        expect(await client.readAll(), hasLength(1));
      });

      test('should throw NotFoundException if ID does not exist', () async {
        expect(
          () => client.delete('non_existent_id'),
          throwsA(isA<NotFoundException>()),
        );
      });
    });

    group('constructor', () {
      test('should initialize with empty storage if initialData is null',
          () async {
        // client is already initialized with null initialData in root setUp
        expect(await client.readAll(), isEmpty);
      });

      test('should initialize with empty storage if initialData is empty list',
          () async {
        client = HtDataInMemoryClient<_TestModel>(
          toJson: _testModelToJson,
          getId: _getTestModelId,
          initialData: [],
        );
        expect(await client.readAll(), isEmpty);
      });

      test('should initialize with items from initialData', () async {
        final initialItems = [item1, item2];
        client = HtDataInMemoryClient<_TestModel>(
          toJson: _testModelToJson,
          getId: _getTestModelId,
          initialData: initialItems,
        );

        // Verify items can be read back
        expect(await client.read(item1.id), equals(item1));
        expect(await client.read(item2.id), equals(item2));

        // Verify readAll returns the initial items
        final allItems = await client.readAll();
        expect(allItems, hasLength(2));
        expect(allItems, containsAll(initialItems));
      });

      test('should throw ArgumentError if initialData contains duplicate IDs',
          () {
        final initialItemsWithDuplicate = [
          item1,
          item2,
          _TestModel(id: item1.id, value: 'duplicate_value'), // Duplicate ID
        ];

        expect(
          () => HtDataInMemoryClient<_TestModel>(
            toJson: _testModelToJson,
            getId: _getTestModelId,
            initialData: initialItemsWithDuplicate,
          ),
          throwsA(isA<ArgumentError>()),
        );
      });
    });
  });
}
