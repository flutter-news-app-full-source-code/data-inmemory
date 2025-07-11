import 'dart:async';
import 'package:equatable/equatable.dart';
import 'package:ht_data_client/ht_data_client.dart';
import 'package:ht_shared/ht_shared.dart';
import 'package:ht_data_inmemory/ht_data_inmemory.dart';
import 'package:logging/logging.dart';
import 'package:test/test.dart';

/// A simple test item for in-memory data client.
class TestItem extends Equatable {
  const TestItem({
    required this.id,
    required this.name,
    required this.value,
    this.details,
  });

  final String id;
  final String name;
  final int? value; // Made nullable
  final Map<String, dynamic>? details;

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'value': value,
        'details': details,
      };

  factory TestItem.fromJson(Map<String, dynamic> json) {
    return TestItem(
      id: json['id'] as String,
      name: json['name'] as String,
      value: json['value'] as int?, // Made nullable
      details: json['details'] as Map<String, dynamic>?,
    );
  }

  @override
  List<Object?> get props => [id, name, value, details];

  TestItem copyWith({
    String? id,
    String? name,
    int? value,
    Map<String, dynamic>? details,
  }) {
    return TestItem(
      id: id ?? this.id,
      name: name ?? this.name,
      value: value ?? this.value,
      details: details ?? this.details,
    );
  }
}

String getTestItemId(TestItem item) => item.id;

void main() {
  group('HtDataInMemory', () {
    late HtDataInMemory<TestItem> client;
    late Logger logger;
    final List<LogRecord> logRecords = [];

    setUp(() {
      logger = Logger('TestLogger');
      logger.clearListeners();
      logger.onRecord.listen(logRecords.add);
      logRecords.clear(); // Clear logs before each test

      client = HtDataInMemory<TestItem>(
        toJson: (item) => item.toJson(),
        getId: getTestItemId,
        logger: logger,
      );
    });

    group('create', () {
      test('should create an item successfully in global scope', () async {
        final item = TestItem(id: '1', name: 'Test Item 1', value: 10);
        final response = await client.create(item: item);

        expect(response.data, item);
        expect(logRecords, contains(predicate<LogRecord>((record) {
          return record.message.contains('Create SUCCESS: id="1" added to scope "global"');
        })));
      });

      test('should create an item successfully for a specific user', () async {
        final item = TestItem(id: '2', name: 'Test Item 2', value: 20);
        const userId = 'user123';
        final response = await client.create(item: item, userId: userId);

        expect(response.data, item);
        expect(logRecords, contains(predicate<LogRecord>((record) {
          return record.message.contains('Create SUCCESS: id="2" added to scope "user123"');
        })));
      });

      test('should throw BadRequestException if item with ID already exists', () async {
        final item = TestItem(id: '3', name: 'Test Item 3', value: 30);
        await client.create(item: item);

        expect(
          () => client.create(item: item),
          throwsA(isA<BadRequestException>().having(
            (e) => e.message,
            'message',
            contains('Item with ID "3" already exists for user "global"'),
          )),
        );
        expect(logRecords, contains(predicate<LogRecord>((record) {
          return record.message.contains('Create FAILED: Item with ID "3" already exists for scope "global"');
        })));
      });
    });

    group('read', () {
      test('should read an item successfully from global scope', () async {
        final item = TestItem(id: '4', name: 'Test Item 4', value: 40);
        await client.create(item: item);

        final response = await client.read(id: '4');
        expect(response.data, item);
        expect(logRecords, contains(predicate<LogRecord>((record) {
          return record.message.contains('Read SUCCESS: id="4" FOUND for scope "global"');
        })));
      });

      test('should read an item successfully for a specific user', () async {
        final item = TestItem(id: '5', name: 'Test Item 5', value: 50);
        const userId = 'user123';
        await client.create(item: item, userId: userId);

        final response = await client.read(id: '5', userId: userId);
        expect(response.data, item);
        expect(logRecords, contains(predicate<LogRecord>((record) {
          return record.message.contains('Read SUCCESS: id="5" FOUND for scope "user123"');
        })));
      });

      test('should throw NotFoundException if item not found in global scope', () async {
        expect(
          () => client.read(id: 'nonExistent'),
          throwsA(isA<NotFoundException>().having(
            (e) => e.message,
            'message',
            contains('Item with ID "nonExistent" not found for user "global"'),
          )),
        );
        expect(logRecords, contains(predicate<LogRecord>((record) {
          return record.message.contains('Read FAILED: id="nonExistent" NOT FOUND for scope "global"');
        })));
      });

      test('should throw NotFoundException if item not found for a specific user', () async {
        const userId = 'user123';
        expect(
          () => client.read(id: 'nonExistent', userId: userId),
          throwsA(isA<NotFoundException>().having(
            (e) => e.message,
            'message',
            contains('Item with ID "nonExistent" not found for user "user123"'),
          )),
        );
        expect(logRecords, contains(predicate<LogRecord>((record) {
          return record.message.contains('Read FAILED: id="nonExistent" NOT FOUND for scope "user123"');
        })));
      });
    });

    group('update', () {
      test('should update an item successfully in global scope', () async {
        final item = TestItem(id: '6', name: 'Original Item 6', value: 60);
        await client.create(item: item);
        final updatedItem = item.copyWith(name: 'Updated Item 6', value: 65);

        final response = await client.update(id: '6', item: updatedItem);
        expect(response.data, updatedItem);
        expect(logRecords, contains(predicate<LogRecord>((record) {
          return record.message.contains('Update SUCCESS: id="6" updated for scope "global"');
        })));
      });

      test('should update an item successfully for a specific user', () async {
        final item = TestItem(id: '7', name: 'Original Item 7', value: 70);
        const userId = 'user456';
        await client.create(item: item, userId: userId);
        final updatedItem = item.copyWith(name: 'Updated Item 7', value: 75);

        final response = await client.update(id: '7', item: updatedItem, userId: userId);
        expect(response.data, updatedItem);
        expect(logRecords, contains(predicate<LogRecord>((record) {
          return record.message.contains('Update SUCCESS: id="7" updated for scope "user456"');
        })));
      });

      test('should throw NotFoundException if item not found for update', () async {
        final item = TestItem(id: 'nonExistentUpdate', name: 'Non Existent', value: 100);
        expect(
          () => client.update(id: 'nonExistentUpdate', item: item),
          throwsA(isA<NotFoundException>().having(
            (e) => e.message,
            'message',
            contains('Item with ID "nonExistentUpdate" not found for update for user "global"'),
          )),
        );
        expect(logRecords, contains(predicate<LogRecord>((record) {
          return record.message.contains('Update FAILED: id="nonExistentUpdate" NOT FOUND for scope "global"');
        })));
      });

      test('should throw BadRequestException if item ID mismatch during update', () async {
        final item = TestItem(id: '8', name: 'Test Item 8', value: 80);
        await client.create(item: item);
        final mismatchedItem = item.copyWith(id: 'mismatchedId');

        expect(
          () => client.update(id: '8', item: mismatchedItem),
          throwsA(isA<BadRequestException>().having(
            (e) => e.message,
            'message',
            contains('Item ID ("mismatchedId") does not match path ID ("8") for "global"'),
          )),
        );
        expect(logRecords, contains(predicate<LogRecord>((record) {
          return record.message.contains('Update FAILED: ID mismatch: incoming "mismatchedId", path "8" for scope "global"');
        })));
      });
    });

    group('delete', () {
      test('should delete an item successfully from global scope', () async {
        final item = TestItem(id: '9', name: 'Test Item 9', value: 90);
        await client.create(item: item);

        await client.delete(id: '9');
        await expectLater(
          () => client.read(id: '9'),
          throwsA(isA<NotFoundException>()),
        );
        expect(logRecords, contains(predicate<LogRecord>((record) {
          return record.message.contains('Delete SUCCESS: id="9" deleted for scope "global"');
        })));
      });

      test('should delete an item successfully for a specific user', () async {
        final item = TestItem(id: '10', name: 'Test Item 10', value: 100);
        const userId = 'user789';
        await client.create(item: item, userId: userId);

        await client.delete(id: '10', userId: userId);
        await expectLater(
          () => client.read(id: '10', userId: userId),
          throwsA(isA<NotFoundException>()),
        );
        expect(logRecords, contains(predicate<LogRecord>((record) {
          return record.message.contains('Delete SUCCESS: id="10" deleted for scope "user789"');
        })));
      });

      test('should throw NotFoundException if item not found for deletion', () async {
        expect(
          () => client.delete(id: 'nonExistentDelete'),
          throwsA(isA<NotFoundException>().having(
            (e) => e.message,
            'message',
            contains('Item with ID "nonExistentDelete" not found for deletion for user "global"'),
          )),
        );
        expect(logRecords, contains(predicate<LogRecord>((record) {
          return record.message.contains('Delete FAILED: id="nonExistentDelete" NOT FOUND for scope "global"');
        })));
      });
    });

    group('readAll', () {
      test('should return an empty list when no items exist', () async {
        final response = await client.readAll();
        expect(response.data.items, isEmpty);
        expect(response.data.hasMore, isFalse);
        expect(response.data.cursor, isNull);
      });

      test('should return all items in global scope', () async {
        final item1 = TestItem(id: '11', name: 'Item 11', value: 110);
        final item2 = TestItem(id: '12', name: 'Item 12', value: 120);
        await client.create(item: item1);
        await client.create(item: item2);

        final response = await client.readAll();
        expect(response.data.items, containsAll([item1, item2]));
        expect(response.data.items.length, 2);
        expect(response.data.hasMore, isFalse);
        expect(response.data.cursor, isNull);
      });

      test('should return all items for a specific user', () async {
        final item1 = TestItem(id: '13', name: 'Item 13', value: 130);
        final item2 = TestItem(id: '14', name: 'Item 14', value: 140);
        const userId = 'userReadAll';
        await client.create(item: item1, userId: userId);
        await client.create(item: item2, userId: userId);

        final response = await client.readAll(userId: userId);
        expect(response.data.items, containsAll([item1, item2]));
        expect(response.data.items.length, 2);
        expect(response.data.hasMore, isFalse);
        expect(response.data.cursor, isNull);
      });

      test('should return a limited number of items with pagination limit', () async {
        final items = List.generate(5, (i) => TestItem(id: '${i + 15}', name: 'Item ${i + 15}', value: i + 150));
        for (final item in items) {
          await client.create(item: item);
        }

        final response = await client.readAll(pagination: const PaginationOptions(limit: 2));
        expect(response.data.items.length, 2);
        expect(response.data.items, containsAll([items[0], items[1]]));
        expect(response.data.hasMore, isTrue);
        expect(response.data.cursor, items[1].id);
      });

      test('should return items starting from a cursor', () async {
        final items = List.generate(5, (i) => TestItem(id: '${i + 20}', name: 'Item ${i + 20}', value: i + 200));
        for (final item in items) {
          await client.create(item: item);
        }

        final response = await client.readAll(pagination: PaginationOptions(cursor: items[1].id));
        expect(response.data.items.length, 3);
        expect(response.data.items, containsAll([items[2], items[3], items[4]]));
        expect(response.data.hasMore, isFalse);
        expect(response.data.cursor, isNull);
      });

      test('should return items with pagination limit and cursor', () async {
        final items = List.generate(10, (i) => TestItem(id: '${i + 25}', name: 'Item ${i + 25}', value: i + 250));
        for (final item in items) {
          await client.create(item: item);
        }

        final response = await client.readAll(
          pagination: PaginationOptions(cursor: items[2].id, limit: 3),
        );
        expect(response.data.items.length, 3);
        expect(response.data.items, containsAll([items[3], items[4], items[5]]));
        expect(response.data.hasMore, isTrue);
        expect(response.data.cursor, items[5].id);
      });

      test('should return empty list if cursor not found', () async {
        final items = List.generate(3, (i) => TestItem(id: '${i + 35}', name: 'Item ${i + 35}', value: i + 350));
        for (final item in items) {
          await client.create(item: item);
        }

        final response = await client.readAll(pagination: const PaginationOptions(cursor: 'nonExistentCursor'));
        expect(response.data.items, isEmpty);
        expect(response.data.hasMore, isFalse);
        expect(response.data.cursor, isNull);
      });

      test('should return empty list if cursor is at the end of the list', () async {
        final items = List.generate(3, (i) => TestItem(id: '${i + 40}', name: 'Item ${i + 40}', value: i + 400));
        for (final item in items) {
          await client.create(item: item);
        }

        final response = await client.readAll(pagination: PaginationOptions(cursor: items.last.id));
        expect(response.data.items, isEmpty);
        expect(response.data.hasMore, isFalse);
        expect(response.data.cursor, isNull);
      });

      test('should sort items by a string field in ascending order', () async {
        final itemA = TestItem(id: 's1', name: 'Apple', value: 1);
        final itemB = TestItem(id: 's2', name: 'Banana', value: 2);
        final itemC = TestItem(id: 's3', name: 'Cherry', value: 3);
        await client.create(item: itemC);
        await client.create(item: itemA);
        await client.create(item: itemB);

        final response = await client.readAll(sort: [const SortOption('name', SortOrder.asc)]);
        expect(response.data.items, [itemA, itemB, itemC]);
      });

      test('should sort items by a string field in descending order', () async {
        final itemA = TestItem(id: 's1', name: 'Apple', value: 1);
        final itemB = TestItem(id: 's2', name: 'Banana', value: 2);
        final itemC = TestItem(id: 's3', name: 'Cherry', value: 3);
        await client.create(item: itemC);
        await client.create(item: itemA);
        await client.create(item: itemB);

        final response = await client.readAll(sort: [const SortOption('name', SortOrder.desc)]);
        expect(response.data.items, [itemC, itemB, itemA]);
      });

      test('should sort items by a numeric field in ascending order', () async {
        final itemA = TestItem(id: 'v1', name: 'Item A', value: 10);
        final itemB = TestItem(id: 'v2', name: 'Item B', value: 5);
        final itemC = TestItem(id: 'v3', name: 'Item C', value: 15);
        await client.create(item: itemC);
        await client.create(item: itemA);
        await client.create(item: itemB);

        final response = await client.readAll(sort: [const SortOption('value', SortOrder.asc)]);
        expect(response.data.items, [itemB, itemA, itemC]);
      });

      test('should sort items by a numeric field in descending order', () async {
        final itemA = TestItem(id: 'v1', name: 'Item A', value: 10);
        final itemB = TestItem(id: 'v2', name: 'Item B', value: 5);
        final itemC = TestItem(id: 'v3', name: 'Item C', value: 15);
        await client.create(item: itemC);
        await client.create(item: itemA);
        await client.create(item: itemB);

        final response = await client.readAll(sort: [const SortOption('value', SortOrder.desc)]);
        expect(response.data.items, [itemC, itemA, itemB]);
      });

      test('should handle null values in sorting (nulls last)', () async {
        final itemA = TestItem(id: 'n1', name: 'Item A', value: 10);
        final itemB = TestItem(id: 'n2', name: 'Item B', value: 5, details: {'category': null});
        final itemC = TestItem(id: 'n3', name: 'Item C', value: 15);
        final itemD = TestItem(id: 'n4', name: 'Item D', value: null); // value is null
        await client.create(item: itemA);
        await client.create(item: itemB);
        await client.create(item: itemC);
        await client.create(item: itemD);

        final response = await client.readAll(sort: [const SortOption('value', SortOrder.asc)]);
        expect(response.data.items, [itemB, itemA, itemC, itemD]); // 5, 10, 15, null
      });

      test('should sort by multiple criteria', () async {
        final item1 = TestItem(id: 'm1', name: 'Apple', value: 10);
        final item2 = TestItem(id: 'm2', name: 'Banana', value: 5);
        final item3 = TestItem(id: 'm3', name: 'Apple', value: 15);
        await client.create(item: item1);
        await client.create(item: item2);
        await client.create(item: item3);

        final response = await client.readAll(sort: [
          const SortOption('name', SortOrder.asc),
          const SortOption('value', SortOrder.desc),
        ]);
        expect(response.data.items, [item3, item1, item2]); // Apple (15), Apple (10), Banana (5)
      });

      test('should fall back to string comparison for non-comparable types in _sortItems', () async {
        final item1 = TestItem(id: 'nc1', name: 'Zebra', value: 1, details: {'category': 'alpha'});
        final item2 = TestItem(id: 'nc2', name: 'Antelope', value: 2, details: {'category': 'beta'});
        final item3 = TestItem(id: 'nc3', name: 'Yak', value: 3, details: {'category': 'gamma'});
        await client.create(item: item1);
        await client.create(item: item2);
        await client.create(item: item3);

        // Sorting by a map field, which is not Comparable. Should fall back to string comparison of its toString().
        final response = await client.readAll(sort: [const SortOption('details', SortOrder.asc)]);
        // The toString() of a map is usually sorted by key, so {'category': 'alpha'} comes before {'category': 'beta'} etc.
        expect(response.data.items, [item1, item2, item3]);
      });
    });

    group('readAll with filter', () {
      late List<TestItem> initialItems;

      setUp(() async {
        initialItems = [
          TestItem(id: 'f1', name: 'Apple', value: 10, details: {'category': 'fruit', 'count': 5}),
          TestItem(id: 'f2', name: 'Banana', value: 20, details: {'category': 'fruit', 'count': 10}),
          TestItem(id: 'f3', name: 'Carrot', value: 30, details: {'category': 'vegetable', 'count': 15}),
          TestItem(id: 'f4', name: 'Date', value: 40, details: {'category': 'fruit', 'count': 20}),
          TestItem(id: 'f5', name: 'Eggplant', value: 50, details: {'category': 'vegetable', 'count': 25}),
          TestItem(id: 'f6', name: 'Fig', value: 60, details: {'category': 'fruit', 'count': 30}),
        ];
        for (final item in initialItems) {
          await client.create(item: item);
        }
      });

      test('should return all items when filter is empty', () async {
        final response = await client.readAll(filter: {});
        expect(response.data.items.length, initialItems.length);
        expect(response.data.items, containsAll(initialItems));
      });

      test('should filter by exact match on a top-level field', () async {
        final response = await client.readAll(filter: {'name': 'Apple'});
        expect(response.data.items.length, 1);
        expect(response.data.items.first.id, 'f1');
      });

      test('should filter by exact match on a top-level field for a specific user', () async {
        final userItems = [
          TestItem(id: 'u1', name: 'User Apple', value: 100),
          TestItem(id: 'u2', name: 'User Banana', value: 200),
        ];
        const userId = 'filterUser';
        for (final item in userItems) {
          await client.create(item: item, userId: userId);
        }

        final response = await client.readAll(userId: userId, filter: {'name': 'User Apple'});
        expect(response.data.items.length, 1);
        expect(response.data.items.first.id, 'u1');
      });

      test('should filter by nested property exact match', () async {
        final response = await client.readAll(filter: {'details.category': 'vegetable'});
        expect(response.data.items.length, 2);
        expect(response.data.items.map((e) => e.id), containsAll(['f3', 'f5']));
      });

      test('should filter using "\$in" operator', () async {
        final response = await client.readAll(filter: {
          'name': {'$in': ['Apple', 'Carrot']},
        });
        expect(response.data.items.length, 2);
        expect(response.data.items.map((e) => e.id), containsAll(['f1', 'f3']));
      });

      test('should filter using "\$in" operator with case-insensitivity', () async {
        final response = await client.readAll(filter: {
          'name': {'$in': ['apple', 'carrot']},
        });
        expect(response.data.items.length, 2);
        expect(response.data.items.map((e) => e.id), containsAll(['f1', 'f3']));
      });

      test('should filter using "\$in" operator with empty list (no match)', () async {
        final response = await client.readAll(filter: {
          'name': {'$in': []},
        });
        expect(response.data.items, isEmpty);
      });

      test('should filter using "\$in" operator with null item value (no match)', () async {
        final itemWithNullValue = TestItem(id: 'f7', name: 'Null Item', value: null);
        await client.create(item: itemWithNullValue);
        final response = await client.readAll(filter: {
          'value': {'$in': [10, 20]},
        });
        expect(response.data.items.map((e) => e.id), isNot(contains('f7')));
      });

      test('should filter using "\$nin" operator', () async {
        final response = await client.readAll(filter: {
          'name': {'$nin': ['Apple', 'Carrot']},
        });
        expect(response.data.items.length, 4);
        expect(response.data.items.map((e) => e.id), containsAll(['f2', 'f4', 'f5', 'f6']));
      });

      test('should filter using "\$nin" operator with case-insensitivity', () async {
        final response = await client.readAll(filter: {
          'name': {'$nin': ['apple', 'carrot']},
        });
        expect(response.data.items.length, 4);
        expect(response.data.items.map((e) => e.id), containsAll(['f2', 'f4', 'f5', 'f6']));
      });

      test('should filter using "\$nin" operator with null item value (should match if null not in list)', () async {
        final itemWithNullValue = TestItem(id: 'f7', name: 'Null Item', value: null);
        await client.create(item: itemWithNullValue);
        final response = await client.readAll(filter: {
          'value': {'$nin': [10, 20]},
        });
        expect(response.data.items.map((e) => e.id), contains('f7'));
      });

      test('should filter using "\$ne" operator', () async {
        final response = await client.readAll(filter: {
          'name': {'$ne': 'Apple'},
        });
        expect(response.data.items.length, 5);
        expect(response.data.items.map((e) => e.id), isNot(contains('f1')));
      });

      test('should filter using "\$ne" operator with null item value', () async {
        final itemWithNullValue = TestItem(id: 'f7', name: 'Null Item', value: null);
        await client.create(item: itemWithNullValue);
        final response = await client.readAll(filter: {
          'value': {'$ne': 10},
        });
        expect(response.data.items.map((e) => e.id), contains('f7'));
      });

      test('should filter using "\$gte" operator', () async {
        final response = await client.readAll(filter: {
          'value': {'$gte': 30},
        });
        expect(response.data.items.length, 4);
        expect(response.data.items.map((e) => e.id), containsAll(['f3', 'f4', 'f5', 'f6']));
      });

      test('should filter using "\$gt" operator', () async {
        final response = await client.readAll(filter: {
          'value': {'$gt': 30},
        });
        expect(response.data.items.length, 3);
        expect(response.data.items.map((e) => e.id), containsAll(['f4', 'f5', 'f6']));
      });

      test('should filter using "\$lte" operator', () async {
        final response = await client.readAll(filter: {
          'value': {'$lte': 30},
        });
        expect(response.data.items.length, 3);
        expect(response.data.items.map((e) => e.id), containsAll(['f1', 'f2', 'f3']));
      });

      test('should filter using "\$lt" operator', () async {
        final response = await client.readAll(filter: {
          'value': {'$lt': 30},
        });
        expect(response.data.items.length, 2);
        expect(response.data.items.map((e) => e.id), containsAll(['f1', 'f2']));
      });

      test('should return false for comparison operators with non-comparable types', () async {
        final response = await client.readAll(filter: {
          'details': {'$gte': {'category': 'fruit'}}, // Map is not Comparable
        });
        expect(response.data.items, isEmpty);
      });

      test('should return false for comparison operators with null item value', () async {
        final itemWithNullValue = TestItem(id: 'f7', name: 'Null Item', value: null);
        await client.create(item: itemWithNullValue);
        final response = await client.readAll(filter: {
          'value': {'$gte': 10},
        });
        expect(response.data.items.map((e) => e.id), isNot(contains('f7')));
      });

      test('should combine multiple exact match filters (AND logic)', () async {
        final response = await client.readAll(filter: {
          'name': 'Apple',
          'value': 10,
        });
        expect(response.data.items.length, 1);
        expect(response.data.items.first.id, 'f1');
      });

      test('should combine exact match with operator filters (AND logic)', () async {
        final response = await client.readAll(filter: {
          'details.category': 'fruit',
          'value': {'$gte': 20},
        });
        expect(response.data.items.length, 3); // f2, f4, f6
        expect(response.data.items.map((e) => e.id), containsAll(['f2', 'f4', 'f6']));
      });

      test('should filter and paginate', () async {
        final response = await client.readAll(
          filter: {'details.category': 'fruit'},
          pagination: const PaginationOptions(limit: 2),
        );
        expect(response.data.items.length, 2);
        expect(response.data.items.map((e) => e.id), containsAll(['f1', 'f2']));
        expect(response.data.hasMore, isTrue);
      });

      test('should filter and sort', () async {
        final response = await client.readAll(
          filter: {'details.category': 'fruit'},
          sort: [const SortOption('value', SortOrder.desc)],
        );
        expect(response.data.items.length, 4); // f6, f4, f2, f1
        expect(response.data.items.map((e) => e.id), ['f6', 'f4', 'f2', 'f1']);
      });

      test('should filter, paginate, and sort', () async {
        final response = await client.readAll(
          filter: {'details.category': 'fruit'},
          pagination: const PaginationOptions(limit: 2),
          sort: [const SortOption('value', SortOrder.desc)],
        );
        expect(response.data.items.length, 2);
        expect(response.data.items.map((e) => e.id), ['f6', 'f4']); // Fig, Date
        expect(response.data.hasMore, isTrue);
      });
    });
  });
}
