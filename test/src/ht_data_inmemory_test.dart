import 'package:ht_data_inmemory/src/ht_data_inmemory.dart';
import 'package:ht_shared/ht_shared.dart';
import 'package:test/test.dart';

// Define a simple model for testing
class TestModel {
  const TestModel({
    required this.id,
    this.name,
    this.description,
    this.count,
    this.category,
    this.tags,
    this.nested,
  });

  factory TestModel.fromJson(Map<String, dynamic> json) {
    return TestModel(
      id: json['id'] as String,
      name: json['name'] as String?,
      description: json['description'] as String?,
      count: json['count'] as int?,
      category: json['category'] != null
          ? TestCategory.fromJson(json['category'] as Map<String, dynamic>)
          : null,
      tags: (json['tags'] as List<dynamic>?)?.cast<String>(),
      nested: json['nested'] != null
          ? TestNested.fromJson(json['nested'] as Map<String, dynamic>)
          : null,
    );
  }

  final String id;
  final String? name;
  final String? description;
  final int? count;
  final TestCategory? category;
  final List<String>? tags;
  final TestNested? nested;

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      if (name != null) 'name': name,
      if (description != null) 'description': description,
      if (count != null) 'count': count,
      if (category != null) 'category': category!.toJson(),
      if (tags != null) 'tags': tags,
      if (nested != null) 'nested': nested!.toJson(),
    };
  }

  // Removed Equatable props
}

class TestCategory {
  const TestCategory({required this.id, this.name});

  factory TestCategory.fromJson(Map<String, dynamic> json) =>
      TestCategory(id: json['id'] as String, name: json['name'] as String?);
  final String id;
  final String? name;
  Map<String, dynamic> toJson() => {'id': id, if (name != null) 'name': name};
  // Removed Equatable props
}

class TestNested {
  const TestNested({required this.value, this.deeper});

  factory TestNested.fromJson(Map<String, dynamic> json) => TestNested(
        value: json['value'] as String,
        deeper: json['deeper'] != null
            ? TestDeeper.fromJson(json['deeper'] as Map<String, dynamic>)
            : null,
      );
  final String value;
  final TestDeeper? deeper;
  Map<String, dynamic> toJson() => {
        'value': value,
        if (deeper != null) 'deeper': deeper!.toJson(),
      };
  // Removed Equatable props
}

class TestDeeper {
  const TestDeeper({required this.finalValue});
  factory TestDeeper.fromJson(Map<String, dynamic> json) =>
      TestDeeper(finalValue: json['finalValue'] as String);
  final String finalValue;
  Map<String, dynamic> toJson() => {'finalValue': finalValue};
  // Removed Equatable props
}

// Define a simple Source model for testing _transformQuery branches
class TestSource {
  const TestSource({
    required this.id,
    required this.name,
    this.sourceType,
    this.language,
    this.headquarters,
  });

  factory TestSource.fromJson(Map<String, dynamic> json) {
    return TestSource(
      id: json['id'] as String,
      name: json['name'] as String,
      sourceType: json['source_type'] as String?,
      language: json['language'] as String?,
      headquarters: json['headquarters'] != null
          ? TestCountry.fromJson(json['headquarters'] as Map<String, dynamic>)
          : null,
    );
  }

  final String id;
  final String name;
  final String? sourceType;
  final String? language;
  final TestCountry? headquarters;

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'name': name,
      if (sourceType != null) 'source_type': sourceType,
      if (language != null) 'language': language,
      if (headquarters != null) 'headquarters': headquarters!.toJson(),
    };
  }
}

// Define a simple Country model for testing _transformQuery branches
class TestCountry {
  const TestCountry({required this.id, required this.name, this.isoCode});

  factory TestCountry.fromJson(Map<String, dynamic> json) {
    return TestCountry(
      id: json['id'] as String,
      name: json['name'] as String,
      isoCode: json['iso_code'] as String?,
    );
  }

  final String id;
  final String name;
  final String? isoCode;

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'name': name,
      if (isoCode != null) 'iso_code': isoCode,
    };
  }
}

// Define a generic model for testing the 'else' branch of _transformQuery
class TestOtherModel {
  const TestOtherModel({required this.id, this.value});

  factory TestOtherModel.fromJson(Map<String, dynamic> json) {
    return TestOtherModel(
      id: json['id'] as String,
      value: json['value'] as String?,
    );
  }

  final String id;
  final String? value;

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      if (value != null) 'value': value,
    };
  }
}

void main() {
  group('HtDataInMemory', () {
    late HtDataInMemory<TestModel> client;
    const model1 = TestModel(
      id: 'id1',
      name: 'Item One',
      description: 'Description for item one',
      count: 10,
      category: TestCategory(id: 'cat1', name: 'Category A'),
      tags: ['tagA', 'tagB'],
      nested: TestNested(
        value: 'nestedVal1',
        deeper: TestDeeper(finalValue: 'deepVal1'),
      ),
    );
    const model2 = TestModel(
      id: 'id2',
      name: 'Item Two',
      description: 'Another item here (two)',
      count: 20,
      category: TestCategory(id: 'cat2', name: 'Category B'),
      tags: ['tagB', 'tagC'],
      nested: TestNested(
        value: 'nestedVal2',
        deeper: TestDeeper(finalValue: 'deepVal2'),
      ),
    );
    const model3User1 = TestModel(
      id: 'id3',
      name: 'User One Item',
      description: 'Specific to user1',
      count: 30,
      category: TestCategory(id: 'cat1'),
      tags: ['tagA', 'tagD'],
      nested: TestNested(
        value: 'nestedVal3User1',
        deeper: TestDeeper(finalValue: 'deepVal3User1'),
      ),
    );

    String getId(TestModel item) => item.id;
    Map<String, dynamic> toJson(TestModel item) => item.toJson();

    setUp(() {
      client = HtDataInMemory<TestModel>(
        getId: getId,
        toJson: toJson,
        initialData: [model1, model2], // Global data
      );
      // Add user-specific data
      // ignore: cascade_invocations
      client.create(item: model3User1, userId: 'user1');
    });

    test('constructor throws ArgumentError for duplicate ID in initialData',
        () {
      expect(
        () => HtDataInMemory<TestModel>(
          getId: getId,
          toJson: toJson,
          initialData: [model1, model1], // Duplicate ID
        ),
        throwsA(isA<ArgumentError>()),
      );
    });

    group('CRUD Operations', () {
      test('create adds an item', () async {
        const newItem = TestModel(id: 'id4', name: 'New Item');
        final response = await client.create(item: newItem);
        expect(response.data, newItem);
        final readResponse = await client.read(id: 'id4');
        expect(readResponse.data, newItem);
      });

      test('create throws BadRequestException for duplicate ID', () async {
        const newItem = TestModel(id: 'id1', name: 'Duplicate Item');
        expect(
          () => client.create(item: newItem),
          throwsA(isA<BadRequestException>()),
        );
      });

      test('read retrieves an existing item', () async {
        final response = await client.read(id: 'id1');
        expect(response.data, model1);
      });

      test('read throws NotFoundException for non-existent ID', () async {
        expect(
          () => client.read(id: 'nonExistent'),
          throwsA(isA<NotFoundException>()),
        );
      });

      test('update modifies an existing item', () async {
        final updatedItem = TestModel(
          id: 'id1',
          name: 'Updated Item One',
          description: model1.description,
          count: model1.count,
          category: model1.category,
        );
        final response = await client.update(id: 'id1', item: updatedItem);
        expect(response.data.name, 'Updated Item One');
        final readResponse = await client.read(id: 'id1');
        expect(readResponse.data.name, 'Updated Item One');
      });

      test('update throws NotFoundException for non-existent ID', () async {
        const item = TestModel(id: 'nonExistent', name: 'Non Existent');
        expect(
          () => client.update(id: 'nonExistent', item: item),
          throwsA(isA<NotFoundException>()),
        );
      });

      test('update throws BadRequestException for ID mismatch', () async {
        const item = TestModel(id: 'id5', name: 'Mismatch ID');
        expect(
          () => client.update(id: 'id1', item: item), // Path ID is id1
          throwsA(isA<BadRequestException>()),
        );
      });

      test('delete removes an item', () async {
        await client.delete(id: 'id1');
        expect(
          () => client.read(id: 'id1'),
          throwsA(isA<NotFoundException>()),
        );
      });

      test('delete throws NotFoundException for non-existent ID', () async {
        expect(
          () => client.delete(id: 'nonExistent'),
          throwsA(isA<NotFoundException>()),
        );
      });
    });

    group('User Scoping', () {
      test('create and read user-specific item', () async {
        const userItem = TestModel(id: 'userItem2', name: 'User2 Item');
        await client.create(item: userItem, userId: 'user2');
        final response = await client.read(id: 'userItem2', userId: 'user2');
        expect(response.data, userItem);
        // Ensure it's not in global scope
        expect(
          () => client.read(id: 'userItem2'),
          throwsA(isA<NotFoundException>()),
        );
        // Ensure it's not in another user's scope
        expect(
          () => client.read(id: 'userItem2', userId: 'user1'),
          throwsA(isA<NotFoundException>()),
        );
      });

      test('global items are not accessible via userId', () async {
        expect(
          () => client.read(id: 'id1', userId: 'user1'),
          throwsA(isA<NotFoundException>()),
        );
      });

      test('user-specific items are not accessible globally', () async {
        expect(
          () => client.read(id: 'id3'), // model3User1 is for user1
          throwsA(isA<NotFoundException>()),
        );
      });
    });

    group('readAll', () {
      test('retrieves all global items', () async {
        final response = await client.readAll();
        expect(response.data.items, containsAll([model1, model2]));
        expect(response.data.items.length, 2);
      });

      test('retrieves all items for a specific user', () async {
        final response = await client.readAll(userId: 'user1');
        expect(response.data.items, contains(model3User1));
        expect(response.data.items.length, 1);
      });

      test('pagination works correctly', () async {
        // Add more global items for pagination testing
        await client.create(
          item: const TestModel(id: 'id_pg3', name: 'Page 3'),
        );
        await client.create(
          item: const TestModel(id: 'id_pg4', name: 'Page 4'),
        );
        await client.create(
          item: const TestModel(id: 'id_pg5', name: 'Page 5'),
        );
        // Total global: model1, model2, id_pg3, id_pg4, id_pg5 (5 items)

        // Page 1: limit 2
        var response = await client.readAll(limit: 2);
        expect(response.data.items.length, 2);
        expect(response.data.hasMore, isTrue);
        expect(response.data.cursor, isNotNull);
        final cursor1 = response.data.cursor;

        // Page 2: limit 2, startAfter cursor1
        response = await client.readAll(limit: 2, startAfterId: cursor1);
        expect(response.data.items.length, 2);
        expect(response.data.hasMore, isTrue);
        expect(response.data.cursor, isNotNull);
        final cursor2 = response.data.cursor;

        // Page 3: limit 2, startAfter cursor2 (should have 1 item left)
        response = await client.readAll(limit: 2, startAfterId: cursor2);
        expect(response.data.items.length, 1);
        expect(response.data.hasMore, isFalse);
        expect(response.data.cursor, isNull);
      });

      test('pagination with startAfterId not found returns empty', () async {
        final response = await client.readAll(startAfterId: 'nonExistentId');
        expect(response.data.items, isEmpty);
        expect(response.data.hasMore, isFalse);
        expect(response.data.cursor, isNull);
      });

      group('with sorting', () {
        test('sorts by name ascending', () async {
          final response = await client.readAll(sortBy: 'name');
          expect(
            response.data.items.map((e) => e.id).toList(),
            ['id1', 'id2'],
          );
        });

        test('sorts by name descending', () async {
          final response =
              await client.readAll(sortBy: 'name', sortOrder: SortOrder.desc);
          expect(
            response.data.items.map((e) => e.id).toList(),
            ['id2', 'id1'],
          );
        });

        test('sorts by numeric count descending', () async {
          final response =
              await client.readAll(sortBy: 'count', sortOrder: SortOrder.desc);
          expect(
            response.data.items.map((e) => e.id).toList(),
            ['id2', 'id1'],
          );
        });

        test('sorts with null values (nulls last)', () async {
          await client.create(item: const TestModel(id: 'id4', name: null));
          final response = await client.readAll(sortBy: 'name');
          // Expect 'Item One', 'Item Two', then the one with null name
          final ids = response.data.items.map((e) => e.id).toList();
          expect(ids.length, 3);
          expect(ids.sublist(0, 2), containsAll(['id1', 'id2']));
          expect(ids.last, 'id4');
        });
      });
    });

    group('readAllByQuery', () {
      test('empty query returns all items', () async {
        final response = await client.readAllByQuery({});
        expect(response.data.items.length, 2); // model1, model2
        final userResponse = await client.readAllByQuery({}, userId: 'user1');
        expect(userResponse.data.items.length, 1); // model3User1
      });

      test('_contains filter (case-insensitive)', () async {
        // Global
        var response = await client
            .readAllByQuery({'name_contains': 'item'}); // Matches both
        expect(response.data.items.length, 2);
        response = await client
            .readAllByQuery({'name_contains': 'ONE'}); // Matches model1
        expect(response.data.items.length, 1);
        expect(response.data.items.first.id, 'id1');
        response = await client.readAllByQuery(
          {'description_contains': 'ITEM ONE'},
        ); // Matches model1
        expect(response.data.items.length, 1);
        expect(response.data.items.first.id, 'id1');

        // User-specific
        final userResponse = await client.readAllByQuery(
          {'name_contains': 'USER'},
          userId: 'user1',
        ); // Matches model3User1
        expect(userResponse.data.items.length, 1);
        expect(userResponse.data.items.first.id, 'id3');
      });

      test('_in filter for top-level field (case-insensitive)', () async {
        final response =
            await client.readAllByQuery({'id_in': 'id1,ID2'}); // model1, model2
        expect(response.data.items.length, 2);
        expect(
          response.data.items.map((e) => e.id),
          containsAll(['id1', 'id2']),
        );
      });

      test('_in filter for nested field (case-insensitive)', () async {
        // Global
        var response =
            await client.readAllByQuery({'category.id_in': 'cat1'}); // model1
        expect(response.data.items.length, 1);
        expect(response.data.items.first.id, 'id1');

        response = await client
            .readAllByQuery({'category.id_in': 'CAT1,cat2'}); // model1, model2
        expect(response.data.items.length, 2);

        // User-specific
        final userResponse = await client.readAllByQuery(
          {'category.id_in': 'CAT1'},
          userId: 'user1',
        ); // model3User1
        expect(userResponse.data.items.length, 1);
        expect(userResponse.data.items.first.id, 'id3');
      });

      test(
          '_in filter for list field (tags) - checks if any item tag is in query list',
          () async {
        // model1 has tags: ['tagA', 'tagB']
        // model2 has tags: ['tagB', 'tagC']
        // model3User1 (user1) has tags: ['tagA', 'tagD']

        // Global: Query for items that have EITHER 'tagA' OR 'tagX' (case-insensitive)
        var response = await client.readAllByQuery({'tags_in': 'tagA,tagX'});
        // Should match model1 (has tagA)
        expect(response.data.items.length, 1, reason: 'Global: tagA or tagX');
        expect(response.data.items.map((e) => e.id), contains('id1'));

        // Global: Query for items that have EITHER 'tagB' OR 'tagD' (case-insensitive)
        response = await client.readAllByQuery({'tags_in': 'tagb,TAGD'});
        // Should match model1 (tagB), model2 (tagB)
        expect(response.data.items.length, 2, reason: 'Global: tagB or tagD');
        expect(
          response.data.items.map((e) => e.id),
          containsAll(['id1', 'id2']),
        );

        // User-specific: Query for items that have EITHER 'tagA' OR 'tagD'
        final userResponse = await client
            .readAllByQuery({'tags_in': 'taga,tagd'}, userId: 'user1');
        // Should match model3User1 (has tagA and tagD)
        expect(
          userResponse.data.items.length,
          1,
          reason: 'User1: tagA or tagD',
        );
        expect(userResponse.data.items.first.id, 'id3');

        // Global: Query for items that have 'tagC'
        response = await client.readAllByQuery({'tags_in': 'tagc'});
        // Should match model2
        expect(response.data.items.length, 1, reason: 'Global: tagC');
        expect(response.data.items.first.id, 'id2');

        // Global: Query for non-existent tag
        response = await client.readAllByQuery({'tags_in': 'tagZ'});
        expect(response.data.items.length, 0, reason: 'Global: tagZ');

        // Global: Query with empty string in list (should not cause error)
        response = await client.readAllByQuery({'tags_in': 'tagA,,tagB'});
        expect(response.data.items.length, 2, reason: 'Global: tagA,,tagB');

        // Global: Query with only commas (should result in no matches if not empty list)
        response = await client.readAllByQuery({'tags_in': ',,'});
        expect(response.data.items.length, 0, reason: 'Global: ,,');
      });

      test('exact match filter (case-sensitive for string comparison)',
          () async {
        final response =
            await client.readAllByQuery({'name': 'Item One'}); // model1
        expect(response.data.items.length, 1);
        expect(response.data.items.first.id, 'id1');

        final responseFail =
            await client.readAllByQuery({'name': 'item one'}); // Fails
        expect(responseFail.data.items.length, 0);
      });

      test('exact match for integer field (converted to string)', () async {
        final response = await client.readAllByQuery({'count': '10'});
        expect(response.data.items.length, 1);
        expect(response.data.items.first.id, 'id1');
      });

      test('combined filters (AND logic)', () async {
        // name_contains AND category.id_in
        final response = await client.readAllByQuery({
          'name_contains': 'item', // model1, model2
          'category.id_in': 'cat1', // model1
        }); // Should result in model1
        expect(response.data.items.length, 1);
        expect(response.data.items.first.id, 'id1');
      });

      test('query with no matches', () async {
        final response =
            await client.readAllByQuery({'name_contains': 'NonExistent'});
        expect(response.data.items.length, 0);
      });

      test('query on deeply nested field', () async {
        var response = await client
            .readAllByQuery({'nested.deeper.finalValue_contains': 'DEEPVAL1'});
        expect(response.data.items.length, 1);
        expect(response.data.items.first.id, 'id1');

        response = await client.readAllByQuery(
          {'nested.deeper.finalValue_in': 'deepVal1,deepValX'},
        );
        expect(response.data.items.length, 1);
        expect(response.data.items.first.id, 'id1');

        response = await client
            .readAllByQuery({'nested.deeper.finalValue': 'deepVal1'});
        expect(response.data.items.length, 1);
        expect(response.data.items.first.id, 'id1');
      });

      test('pagination on queried results', () async {
        // Add more items that match a query
        await client.create(
          item: const TestModel(id: 'q_item3', name: 'Query Item Alpha'),
        );
        await client.create(
          item: const TestModel(id: 'q_item4', name: 'Query Item Beta'),
        );
        await client.create(
          item: const TestModel(id: 'q_item5', name: 'Query Item Gamma'),
        );
        // model1 (Item One), model2 (Item Two) also match 'Item'
        // Total 5 items match 'name_contains': 'Item'

        var response = await client.readAllByQuery(
          {'name_contains': 'Item', 'limit': '2'},
        );
        expect(response.data.items.length, 2);
        expect(response.data.hasMore, isTrue);
        final cursor1 = response.data.cursor;

        response = await client.readAllByQuery(
          {'name_contains': 'Item', 'limit': '2', 'startAfterId': cursor1},
        );
        expect(response.data.items.length, 2);
        expect(response.data.hasMore, isTrue);
        final cursor2 = response.data.cursor;

        response = await client.readAllByQuery(
          {'name_contains': 'Item', 'limit': '2', 'startAfterId': cursor2},
        );
        expect(response.data.items.length, 1);
        expect(response.data.hasMore, isFalse);
      });

      test('filters and sorts results', () async {
        // Add another item to make it interesting
        await client.create(
          item: const TestModel(
            id: 'id_q_sort',
            name: 'Item Alpha',
            category: TestCategory(id: 'cat1'),
          ),
        );
        // model1: name 'Item One', category 'cat1'
        // model_q_sort: name 'Item Alpha', category 'cat1'

        final response = await client.readAllByQuery(
          {'category.id_in': 'cat1'},
          sortBy: 'name',
          sortOrder: SortOrder.desc,
        );

        // Should match model1 and id_q_sort, sorted by name descending
        // 'Item One' > 'Item Alpha'
        expect(response.data.items.length, 2);
        expect(
          response.data.items.map((e) => e.id).toList(),
          ['id1', 'id_q_sort'],
        );
      });
    });
  });
}
