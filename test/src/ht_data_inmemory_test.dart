//
// ignore_for_file: avoid_equals_and_hash_code_on_mutable_classes

import 'package:ht_data_inmemory/src/ht_data_inmemory.dart';
import 'package:ht_shared/ht_shared.dart';
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
      test('should create and return the item in SuccessApiResponse', () async {
        final createdResponse = await client.create(item: item1);
        expect(createdResponse.data, equals(item1));
        // Verify it can be read back
        final readResponse = await client.read(id: item1.id);
        expect(readResponse.data, equals(item1));
      });

      test('should throw BadRequestException if item with ID already exists',
          () async {
        await client.create(item: item1); // Create first time
        // Attempt to create again with the same ID
        expect(
          () => client.create(item: item1),
          throwsA(isA<BadRequestException>()),
        );
      });
    });

    group('read', () {
      setUp(() async {
        // Pre-populate for read tests
        await client.create(item: item1);
        await client.create(item: item2);
      });

      test('should return the item in SuccessApiResponse if ID exists',
          () async {
        final response1 = await client.read(id: item1.id);
        expect(response1.data, equals(item1));
        final response2 = await client.read(id: item2.id);
        expect(response2.data, equals(item2));
      });

      test('should throw NotFoundException if ID does not exist', () async {
        expect(
          () => client.read(id: 'non_existent_id'),
          throwsA(isA<NotFoundException>()),
        );
      });
    });

    group('readAll', () {
      test('should return empty PaginatedResponse when client is empty',
          () async {
        final response = await client.readAll();
        expect(response.data.items, isEmpty);
        expect(response.data.cursor, isNull);
        expect(response.data.hasMore, isFalse);
      });

      test('should return all items in PaginatedResponse when client has data',
          () async {
        await client.create(item: item1);
        await client.create(item: item2);
        await client.create(item: item3);
        final response = await client.readAll();
        expect(response.data.items, hasLength(3));
        expect(response.data.items, containsAll([item1, item2, item3]));
        expect(response.data.hasMore, isFalse); // No limit, so no more pages
        expect(response.data.cursor, isNull); // No more pages
      });

      test('should return limited items and indicate hasMore', () async {
        // Create items in a predictable order for pagination testing
        final items =
            List.generate(5, (i) => _TestModel(id: 'id$i', value: 'v$i'));
        for (final item in items) {
          await client.create(item: item);
        }

        final response = await client.readAll(limit: 2);
        expect(response.data.items, hasLength(2));
        expect(response.data.items, containsAll([items[0], items[1]]));
        expect(response.data.hasMore, isTrue);
        expect(
          response.data.cursor,
          equals(items[1].id),
        ); // Cursor is last item's ID
      });

      test('should return items after startAfterId', () async {
        final items =
            List.generate(5, (i) => _TestModel(id: 'id$i', value: 'v$i'));
        for (final item in items) {
          await client.create(item: item);
        }
        final startAfter = items[1].id; // Start after the second item

        final response = await client.readAll(startAfterId: startAfter);
        expect(response.data.items, hasLength(3)); // Should get items 2, 3, 4
        expect(
          response.data.items,
          containsAll([items[2], items[3], items[4]]),
        );
        expect(response.data.hasMore, isFalse); // No limit, got all remaining
        expect(response.data.cursor, isNull);
      });

      test('should return items after startAfterId with limit', () async {
        final items =
            List.generate(5, (i) => _TestModel(id: 'id$i', value: 'v$i'));
        for (final item in items) {
          await client.create(item: item);
        }
        final startAfter = items[1].id; // Start after the second item

        final response =
            await client.readAll(startAfterId: startAfter, limit: 2);
        expect(response.data.items, hasLength(2)); // Should get items 2, 3
        expect(response.data.items, containsAll([items[2], items[3]]));
        expect(response.data.hasMore, isTrue); // Item 4 still exists
        expect(
          response.data.cursor,
          equals(items[3].id),
        ); // Cursor is last item's ID
      });

      test(
          'should return empty PaginatedResponse if startAfterId '
          'does not exist', () async {
        await client.create(item: item1);
        final response = await client.readAll(startAfterId: 'non_existent_id');
        expect(response.data.items, isEmpty);
        expect(response.data.cursor, isNull);
        expect(response.data.hasMore, isFalse);
      });

      test(
          'should return empty PaginatedResponse if startAfterId is the '
          'last item', () async {
        final items =
            List.generate(3, (i) => _TestModel(id: 'id$i', value: 'v$i'));
        for (final item in items) {
          await client.create(item: item);
        }
        final lastItemId = items.last.id;
        final response = await client.readAll(startAfterId: lastItemId);
        expect(response.data.items, isEmpty);
        expect(response.data.cursor, isNull);
        expect(response.data.hasMore, isFalse);
      });
    });

    group('readAllByQuery', () {
      setUp(() async {
        // Pre-populate for query tests
        await client.create(item: item1); // category: A
        await client.create(item: item2); // category: B
        await client.create(item: item3); // category: A
      });

      test('should return all items in PaginatedResponse if query is empty',
          () async {
        final response = await client.readAllByQuery({});
        expect(response.data.items, hasLength(3));
        expect(response.data.items, containsAll([item1, item2, item3]));
        expect(response.data.hasMore, isFalse);
        expect(response.data.cursor, isNull);
      });

      test('should return matching items in PaginatedResponse', () async {
        final response = await client.readAllByQuery({'category': 'A'});
        expect(response.data.items, hasLength(2));
        expect(response.data.items, containsAll([item1, item3]));
        expect(response.data.items, isNot(contains(item2)));
        expect(response.data.hasMore, isFalse);
        expect(response.data.cursor, isNull);
      });

      test('should return items matching multiple query parameters', () async {
        final response =
            await client.readAllByQuery({'category': 'A', 'value': 'value1'});
        expect(response.data.items, hasLength(1));
        expect(response.data.items, contains(item1));
        expect(response.data.hasMore, isFalse);
        expect(response.data.cursor, isNull);
      });

      test('should return empty PaginatedResponse if no items match query',
          () async {
        final response = await client.readAllByQuery({'category': 'C'});
        expect(response.data.items, isEmpty);
        expect(response.data.cursor, isNull);
        expect(response.data.hasMore, isFalse);
      });

      test(
          'should return empty PaginatedResponse if query key does not exist '
          'in items', () async {
        final response =
            await client.readAllByQuery({'non_existent_key': 'value'});
        expect(response.data.items, isEmpty);
        expect(response.data.cursor, isNull);
        expect(response.data.hasMore, isFalse);
      });

      test('should apply pagination to query results (startAfterId)', () async {
        // Ensure predictable order for this test
        client = HtDataInMemoryClient<_TestModel>(
          toJson: _testModelToJson,
          getId: _getTestModelId,
          initialData: [item1, item3, item2], // item1, item3 are category 'A'
        );
        final startAfter = item1.id;
        final response = await client
            .readAllByQuery({'category': 'A'}, startAfterId: startAfter);
        expect(response.data.items, hasLength(1));
        expect(
          response.data.items.first,
          equals(item3),
        ); // Should be the second 'A'
        expect(response.data.hasMore, isFalse);
        expect(response.data.cursor, isNull);
      });

      test('should apply pagination to query results (startAfterId + limit)',
          () async {
        // Ensure predictable order
        const itemA1 = _TestModel(id: 'a1', value: 'v1', category: 'A');
        const itemA2 = _TestModel(id: 'a2', value: 'v2', category: 'A');
        const itemA3 = _TestModel(id: 'a3', value: 'v3', category: 'A');
        client = HtDataInMemoryClient<_TestModel>(
          toJson: _testModelToJson,
          getId: _getTestModelId,
          initialData: [itemA1, itemA2, itemA3],
        );
        final startAfter = itemA1.id;
        final response = await client.readAllByQuery(
          {'category': 'A'},
          startAfterId: startAfter,
          limit: 1,
        );
        expect(response.data.items, hasLength(1));
        expect(response.data.items.first, equals(itemA2));
        expect(response.data.hasMore, isTrue); // itemA3 remains
        expect(response.data.cursor, equals(itemA2.id));
      });
    });

    group('update', () {
      setUp(() async {
        // Pre-populate for update tests
        await client.create(item: item1);
      });

      test('should update and return item in SuccessApiResponse if ID exists',
          () async {
        const updatedItem = _TestModel(id: 'id1', value: 'updated_value');
        final updateResponse =
            await client.update(id: item1.id, item: updatedItem);
        expect(updateResponse.data, equals(updatedItem));
        // Verify the stored item is updated
        final readResponse = await client.read(id: item1.id);
        expect(readResponse.data, equals(updatedItem));
      });

      test('should throw NotFoundException if ID does not exist', () async {
        const itemToUpdate = _TestModel(id: 'non_existent_id', value: 'value');
        expect(
          () => client.update(id: 'non_existent_id', item: itemToUpdate),
          throwsA(isA<NotFoundException>()),
        );
      });

      test('should throw BadRequestException if item ID does not match path ID',
          () async {
        // ID in path is item1.id ('id1'), but item has 'id_mismatch'
        const mismatchedItem = _TestModel(id: 'id_mismatch', value: 'value');
        expect(
          () => client.update(id: item1.id, item: mismatchedItem),
          throwsA(isA<BadRequestException>()),
        );
      });
    });

    group('delete', () {
      setUp(() async {
        // Pre-populate for delete tests
        await client.create(item: item1);
        await client.create(item: item2);
      });

      test('should delete the item if ID exists', () async {
        await client.delete(id: item1.id);
        // Verify it's gone
        expect(
          () => client.read(id: item1.id),
          throwsA(isA<NotFoundException>()),
        );
        // Verify other items remain
        final readResponse = await client.read(id: item2.id);
        expect(readResponse.data, equals(item2));
        final allResponse = await client.readAll();
        expect(allResponse.data.items, hasLength(1));
      });

      test('should throw NotFoundException if ID does not exist', () async {
        expect(
          () => client.delete(id: 'non_existent_id'),
          throwsA(isA<NotFoundException>()),
        );
      });
    });

    group('constructor', () {
      test(
          'should initialize with empty storage if initialData is null or empty',
          () async {
        // Test case 1: initialData is null (from root setUp)
        final response1 = await client.readAll();
        expect(response1.data.items, isEmpty);

        // Test case 2: initialData is empty list
        client = HtDataInMemoryClient<_TestModel>(
          toJson: _testModelToJson,
          getId: _getTestModelId,
          initialData: [],
        );
        final response2 = await client.readAll();
        expect(response2.data.items, isEmpty);
      });

      test('should initialize with items from initialData', () async {
        final initialItems = [item1, item2];
        client = HtDataInMemoryClient<_TestModel>(
          toJson: _testModelToJson,
          getId: _getTestModelId,
          initialData: initialItems,
        );

        // Verify items can be read back
        final readResponse1 = await client.read(id: item1.id);
        expect(readResponse1.data, equals(item1));
        final readResponse2 = await client.read(id: item2.id);
        expect(readResponse2.data, equals(item2));

        // Verify readAll returns the initial items
        final allResponse = await client.readAll();
        expect(allResponse.data.items, hasLength(2));
        expect(allResponse.data.items, containsAll(initialItems));
      });

      test('should throw ArgumentError if initialData contains duplicate IDs',
          () {
        final initialItemsWithDuplicate = [
          item1,
          item2,
          // Duplicate ID
          _TestModel(id: item1.id, value: 'duplicate_value'),
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

    group('User Scoping', () {
      const userId1 = 'user1';
      const userId2 = 'user2';
      const user1Item1 =
          _TestModel(id: 'u1item1', value: 'user1Value1', category: 'U1');
      const user1Item2 =
          _TestModel(id: 'u1item2', value: 'user1Value2', category: 'U1');
      const user2Item1 =
          _TestModel(id: 'u2item1', value: 'user2Value1', category: 'U2');
      const globalItem1 =
          _TestModel(id: 'gitem1', value: 'globalValue1', category: 'G');

      setUp(() async {
        // Initialize a fresh client for each user scoping test
        client = HtDataInMemoryClient<_TestModel>(
          toJson: _testModelToJson,
          getId: _getTestModelId,
        );

        // Populate with some data
        await client.create(item: user1Item1, userId: userId1);
        await client.create(item: user1Item2, userId: userId1);
        await client.create(item: user2Item1, userId: userId2);
        await client.create(item: globalItem1); // Global item (userId: null)
      });

      test(
          'create should store items under the correct userId and globally '
          'if userId is null', () async {
        // Verify user1Item1 was created for userId1
        final responseUser1 =
            await client.read(id: user1Item1.id, userId: userId1);
        expect(responseUser1.data, equals(user1Item1));

        // Verify user2Item1 was created for userId2
        final responseUser2 =
            await client.read(id: user2Item1.id, userId: userId2);
        expect(responseUser2.data, equals(user2Item1));

        // Verify globalItem1 was created globally
        final responseGlobal = await client.read(id: globalItem1.id);
        expect(responseGlobal.data, equals(globalItem1));

        // Verify user1Item1 is not accessible globally or by userId2
        expect(
          () => client.read(id: user1Item1.id),
          throwsA(isA<NotFoundException>()),
        );
        expect(
          () => client.read(id: user1Item1.id, userId: userId2),
          throwsA(isA<NotFoundException>()),
        );
      });

      test('read should retrieve items specific to userId or global', () async {
        // Already implicitly tested by the create test's verification steps
        // but can add more specific read assertions if needed.
        final r1 = await client.read(id: user1Item1.id, userId: userId1);
        expect(r1.data, user1Item1);

        final r2 = await client.read(id: user2Item1.id, userId: userId2);
        expect(r2.data, user2Item1);

        final r3 = await client.read(id: globalItem1.id); // Global
        expect(r3.data, globalItem1);
      });

      test('readAll should return items scoped to userId or global', () async {
        // User 1
        final responseUser1 = await client.readAll(userId: userId1);
        expect(responseUser1.data.items, hasLength(2));
        expect(responseUser1.data.items, containsAll([user1Item1, user1Item2]));

        // User 2
        final responseUser2 = await client.readAll(userId: userId2);
        expect(responseUser2.data.items, hasLength(1));
        expect(responseUser2.data.items, contains(user2Item1));

        // Global
        final responseGlobal = await client.readAll(); // userId is null
        expect(responseGlobal.data.items, hasLength(1));
        expect(responseGlobal.data.items, contains(globalItem1));
      });

      test('readAllByQuery should respect userId scoping', () async {
        // Query for user1's items
        final responseUser1 = await client.readAllByQuery(
          {'category': 'U1'},
          userId: userId1,
        );
        expect(responseUser1.data.items, hasLength(2));
        expect(responseUser1.data.items, containsAll([user1Item1, user1Item2]));

        // Query for user2's items
        final responseUser2 = await client.readAllByQuery(
          {'category': 'U2'},
          userId: userId2,
        );
        expect(responseUser2.data.items, hasLength(1));
        expect(responseUser2.data.items, contains(user2Item1));

        // Query for global items
        final responseGlobal = await client.readAllByQuery({'category': 'G'});
        expect(responseGlobal.data.items, hasLength(1));
        expect(responseGlobal.data.items, contains(globalItem1));

        // Query for 'U1' globally should be empty
        final emptyResponse = await client.readAllByQuery({'category': 'U1'});
        expect(emptyResponse.data.items, isEmpty);
      });

      test('update should modify items only within the correct scope',
          () async {
        const updatedUser1Item =
            _TestModel(id: 'u1item1', value: 'updatedUser1Value');
        await client.update(
          id: user1Item1.id,
          item: updatedUser1Item,
          userId: userId1,
        );

        // Verify update for user1
        final readUser1 = await client.read(id: user1Item1.id, userId: userId1);
        expect(readUser1.data.value, equals('updatedUser1Value'));

        // Verify global item with same ID (if it existed) is not affected
        // (In this setup, globalItem1 has a different ID, so this tests isolation)
        final readGlobal = await client.read(id: globalItem1.id);
        expect(readGlobal.data.value, equals('globalValue1'));

        // Attempt to update user1's item via global scope should fail
        expect(
          () => client.update(id: user1Item1.id, item: updatedUser1Item),
          throwsA(isA<NotFoundException>()),
        );
      });

      test('delete should remove items only from the correct scope', () async {
        // Delete user1's item
        await client.delete(id: user1Item1.id, userId: userId1);
        expect(
          () => client.read(id: user1Item1.id, userId: userId1),
          throwsA(isA<NotFoundException>()),
        );

        // Verify user1's other item, user2's item, and global item still exist
        final user1Remaining =
            await client.read(id: user1Item2.id, userId: userId1);
        expect(user1Remaining.data, equals(user1Item2));

        final user2Item = await client.read(id: user2Item1.id, userId: userId2);
        expect(user2Item.data, equals(user2Item1));

        final globalItem = await client.read(id: globalItem1.id);
        expect(globalItem.data, equals(globalItem1));

        // Attempt to delete global item using a userId should fail
        expect(
          () => client.delete(id: globalItem1.id, userId: userId1),
          throwsA(isA<NotFoundException>()),
        );
      });
    });
  });
}
