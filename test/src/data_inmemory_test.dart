// ignore_for_file: prefer_const_constructors, use_is_even_rather_than_modulo

import 'package:core/core.dart';
import 'package:data_inmemory/data_inmemory.dart';
import 'package:equatable/equatable.dart';
import 'package:test/test.dart';

class Category extends Equatable {
  const Category({required this.id, required this.name});

  final String id;
  final String name;

  Map<String, dynamic> toJson() => {'id': id, 'name': name};

  @override
  List<Object?> get props => [id, name];
}

class Article extends Equatable {
  const Article({
    required this.id,
    required this.title,
    required this.category,
    this.isPublished = false,
    this.rating = 0.0,
    this.publishedAt,
  });

  final String id;
  final String title;
  final Category category;
  final bool isPublished;
  final double rating;
  final DateTime? publishedAt;

  Map<String, dynamic> toJson() => {
        'id': id,
        'title': title,
        'category': category.toJson(),
        'isPublished': isPublished,
        'rating': rating,
        'publishedAt': publishedAt?.toIso8601String(),
        'type': 'headline', // Add type for search query simulation
      };

  @override
  List<Object?> get props => [
        id,
        title,
        category,
        isPublished,
        rating,
        publishedAt,
      ];
}

List<Article> createTestArticles(int count) {
  return List.generate(count, (i) {
    return Article(
      id: 'id-$i',
      title: 'Article $i',
      category: Category(id: 'cat-${i % 2}', name: 'Category ${i % 2}'),
      isPublished: i % 2 == 0,
      rating: 3.0 + i,
      publishedAt: i.isEven ? DateTime(2024).add(Duration(days: i)) : null,
    );
  });
}

void main() {
  group('DataInMemory', () {
    late DataInMemory<Article> client;
    late List<Article> initialArticles;

    setUp(() {
      initialArticles = createTestArticles(3);
      client = DataInMemory<Article>(
        getId: (article) => article.id,
        toJson: (article) => article.toJson(),
      );
    });

    group('constructor', () {
      test('can be instantiated', () {
        expect(client, isA<DataInMemory<Article>>());
      });

      test('loads initialData correctly', () async {
        // Arrange
        final clientWithData = DataInMemory<Article>(
          getId: (article) => article.id,
          toJson: (article) => article.toJson(),
          initialData: initialArticles,
        );

        // Act
        final response = await clientWithData.readAll();

        // Assert
        expect(response.data.items.length, 3);
        expect(response.data.items, containsAll(initialArticles));
      });

      test('throws ArgumentError for duplicate IDs in initialData', () {
        // Arrange
        final articlesWithDuplicates = [
          ...initialArticles,
          Article(
            id: 'id-0', // Duplicate ID
            title: 'Duplicate Article',
            category: const Category(id: 'cat-dup', name: 'Duplicate'),
          ),
        ];

        // Act & Assert
        expect(
          () => DataInMemory<Article>(
            getId: (article) => article.id,
            toJson: (article) => article.toJson(),
            initialData: articlesWithDuplicates,
          ),
          throwsA(isA<ArgumentError>()),
        );
      });
    });

    group('create', () {
      final newArticle = Article(
        id: 'new-id',
        title: 'New Article',
        category: const Category(id: 'cat-new', name: 'New'),
      );

      test('should create an item successfully in global scope', () async {
        // Act
        final response = await client.create(item: newArticle);

        // Assert
        expect(response.data, newArticle);

        // Verify it was stored
        final readResponse = await client.read(id: newArticle.id);
        expect(readResponse.data, newArticle);
      });

      test('should create an item successfully in user scope', () async {
        // Arrange
        const userId = 'user-123';

        // Act
        final response = await client.create(item: newArticle, userId: userId);

        // Assert
        expect(response.data, newArticle);

        // Verify it was stored in the user's scope
        final readResponse = await client.read(
          id: newArticle.id,
          userId: userId,
        );
        expect(readResponse.data, newArticle);

        // Verify it's not in the global scope
        expect(
          () => client.read(id: newArticle.id),
          throwsA(isA<NotFoundException>()),
        );
      });

      test('should throw BadRequestException for duplicate ID', () async {
        // Arrange: create the item first
        await client.create(item: newArticle);

        // Act & Assert
        expect(
          () => client.create(item: newArticle),
          throwsA(isA<BadRequestException>()),
        );
      });
    });

    group('read', () {
      setUp(() async {
        // Pre-populate with one global and one user-scoped article
        await client.create(item: initialArticles[0]);
        await client.create(item: initialArticles[1], userId: 'user-123');
      });

      test('should read an item successfully from global scope', () async {
        // Arrange
        final idToRead = initialArticles[0].id;

        // Act
        final response = await client.read(id: idToRead);

        // Assert
        expect(response.data, initialArticles[0]);
      });

      test('should read an item successfully from user scope', () async {
        // Arrange
        final idToRead = initialArticles[1].id;
        const userId = 'user-123';

        // Act
        final response = await client.read(id: idToRead, userId: userId);

        // Assert
        expect(response.data, initialArticles[1]);
      });

      test('should throw NotFoundException for non-existent ID', () {
        // Arrange
        const nonExistentId = 'id-does-not-exist';

        // Act & Assert
        expect(
          () => client.read(id: nonExistentId),
          throwsA(isA<NotFoundException>()),
        );
      });

      test('should throw NotFoundException for item in different scope', () {
        // Arrange: item exists in user-123 scope
        final idInUserScope = initialArticles[1].id;

        // Act & Assert: try to read from global scope
        expect(
          () => client.read(id: idInUserScope),
          throwsA(isA<NotFoundException>()),
        );
      });
    });

    group('update', () {
      late Article articleToUpdate;
      late Article userScopedArticleToUpdate;
      const userId = 'user-123';

      setUp(() async {
        articleToUpdate = initialArticles[0];
        userScopedArticleToUpdate = initialArticles[1];
        // Pre-populate with one global and one user-scoped article
        await client.create(item: articleToUpdate);
        await client.create(item: userScopedArticleToUpdate, userId: userId);
      });

      test('should update an item successfully in global scope', () async {
        // Arrange
        final updatedArticle = Article(
          id: articleToUpdate.id,
          title: 'Updated Title',
          category: articleToUpdate.category,
        );

        // Act
        final response = await client.update(
          id: articleToUpdate.id,
          item: updatedArticle,
        );

        // Assert
        expect(response.data, updatedArticle);
        final readResponse = await client.read(id: articleToUpdate.id);
        expect(readResponse.data.title, 'Updated Title');
      });

      test('should update an item successfully in user scope', () async {
        // Arrange
        final updatedArticle = Article(
          id: userScopedArticleToUpdate.id,
          title: 'Updated User-Scoped Title',
          category: userScopedArticleToUpdate.category,
        );

        // Act
        final response = await client.update(
          id: userScopedArticleToUpdate.id,
          item: updatedArticle,
          userId: userId,
        );

        // Assert
        expect(response.data, updatedArticle);
        final readResponse = await client.read(
          id: userScopedArticleToUpdate.id,
          userId: userId,
        );
        expect(readResponse.data.title, 'Updated User-Scoped Title');
      });

      test('should throw NotFoundException for non-existent ID', () {
        // Arrange
        const nonExistentId = 'id-does-not-exist';
        final updatedArticle = Article(
          id: nonExistentId,
          title: 'Non-existent',
          category: const Category(id: 'cat-new', name: 'New'),
        );

        // Act & Assert
        expect(
          () => client.update(id: nonExistentId, item: updatedArticle),
          throwsA(isA<NotFoundException>()),
        );
      });

      test('should throw BadRequestException for ID mismatch', () {
        // Arrange
        final updatedArticleWithWrongId = Article(
          id: 'wrong-id', // ID in object is different from path ID
          title: 'Mismatched ID',
          category: articleToUpdate.category,
        );

        // Act & Assert
        expect(
          () => client.update(
            id: articleToUpdate.id, // Path ID
            item: updatedArticleWithWrongId,
          ),
          throwsA(isA<BadRequestException>()),
        );
      });
    });

    group('delete', () {
      late Article articleToDelete;
      late Article userScopedArticleToDelete;
      const userId = 'user-123';

      setUp(() async {
        articleToDelete = initialArticles[0];
        userScopedArticleToDelete = initialArticles[1];
        // Pre-populate with one global and one user-scoped article
        await client.create(item: articleToDelete);
        await client.create(item: userScopedArticleToDelete, userId: userId);
      });

      test('should delete an item successfully from global scope', () async {
        // Act
        await client.delete(id: articleToDelete.id);

        // Assert: Verify it's gone
        expect(
          () => client.read(id: articleToDelete.id),
          throwsA(isA<NotFoundException>()),
        );
      });

      test('should delete an item successfully from user scope', () async {
        // Act
        await client.delete(id: userScopedArticleToDelete.id, userId: userId);

        // Assert: Verify it's gone from user scope
        expect(
          () => client.read(id: userScopedArticleToDelete.id, userId: userId),
          throwsA(isA<NotFoundException>()),
        );

        // Assert: Verify global scope is unaffected
        final globalItemResponse = await client.read(id: articleToDelete.id);
        expect(globalItemResponse.data, articleToDelete);
      });

      test('should throw NotFoundException for non-existent ID', () {
        // Arrange
        const nonExistentId = 'id-does-not-exist';

        // Act & Assert
        expect(
          () => client.delete(id: nonExistentId),
          throwsA(isA<NotFoundException>()),
        );
      });
    });

    group('readAll', () {
      late DataInMemory<Article> clientWithData;
      late List<Article> allArticles;

      setUp(() {
        // Create 10 articles for diverse testing scenarios
        allArticles = createTestArticles(10);
        clientWithData = DataInMemory<Article>(
          getId: (article) => article.id,
          toJson: (article) => article.toJson(),
          initialData: allArticles,
        );
      });

      group('filtering', () {
        test('should return all items when no filter is provided', () async {
          // Act
          final response = await clientWithData.readAll();

          // Assert
          expect(response.data.items.length, 10);
        });

        test('should filter by a simple exact match', () async {
          // Arrange
          final filter = {'isPublished': true}; // 5 articles are published

          // Act
          final response = await clientWithData.readAll(filter: filter);

          // Assert
          expect(response.data.items.length, 5);
          expect(response.data.items.every((a) => a.isPublished), isTrue);
        });

        test(
          'should return an empty list for a filter with no matches',
          () async {
            // Arrange
            final filter = {'title': 'Non-existent Title'};

            // Act
            final response = await clientWithData.readAll(filter: filter);

            // Assert
            expect(response.data.items, isEmpty);
          },
        );

        test('should filter correctly within a user scope', () async {
          // Arrange
          const userId = 'user-abc';
          final userArticles = [
            Article(
              id: 'user-id-1',
              title: 'User Article 1',
              category: Category(id: 'cat-1', name: 'Category 1'),
              isPublished: true,
            ),
            Article(
              id: 'user-id-2',
              title: 'User Article 2',
              category: Category(id: 'cat-2', name: 'Category 2'),
            ),
          ];
          await client.create(item: userArticles[0], userId: userId);
          await client.create(item: userArticles[1], userId: userId);
          final filter = {'isPublished': true};

          // Act
          final response = await client.readAll(filter: filter, userId: userId);

          // Assert
          expect(response.data.items.length, 1);
          expect(response.data.items.first.id, 'user-id-1');
        });

        test(r'should filter using $in operator', () async {
          // Arrange
          final filter = {
            'category.id': {
              r'$in': ['cat-1'],
            },
          }; // 5 articles are in cat-1

          // Act
          final response = await clientWithData.readAll(filter: filter);

          // Assert
          expect(response.data.items.length, 5);
          expect(
            response.data.items.every((a) => a.category.id == 'cat-1'),
            isTrue,
          );
        });

        test(r'should filter using $nin (not in) operator', () async {
          // Arrange
          final filter = {
            'category.id': {
              r'$nin': ['cat-1'],
            },
          }; // 5 articles are not in cat-1 (they are in cat-0)

          // Act
          final response = await clientWithData.readAll(filter: filter);

          // Assert
          expect(response.data.items.length, 5);
          expect(
            response.data.items.every((a) => a.category.id != 'cat-1'),
            isTrue,
          );
        });

        test(r'should filter using $ne (not equal) operator', () async {
          // Arrange
          final filter = {
            'title': {r'$ne': 'Article 5'},
          }; // 9 articles do not have this title

          // Act
          final response = await clientWithData.readAll(filter: filter);

          // Assert
          expect(response.data.items.length, 9);
          expect(
            response.data.items.every((a) => a.title != 'Article 5'),
            isTrue,
          );
        });

        test(r'should filter using $gte (>=) operator on a double', () async {
          // Arrange
          final filter = {
            'rating': {r'$gte': 10.0},
          }; // Articles 7, 8, 9 have ratings 10.0, 11.0, 12.0

          // Act
          final response = await clientWithData.readAll(filter: filter);

          // Assert
          expect(response.data.items.length, 3);
          expect(response.data.items.every((a) => a.rating >= 10.0), isTrue);
        });

        test(r'should filter using $gt (>) operator on a double', () async {
          // Arrange
          final filter = {
            'rating': {r'$gt': 10.0},
          }; // Articles 8, 9 have ratings 11.0, 12.0

          // Act
          final response = await clientWithData.readAll(filter: filter);

          // Assert
          expect(response.data.items.length, 2);
          expect(response.data.items.every((a) => a.rating > 10.0), isTrue);
        });

        test(r'should filter using $lte (<=) operator on a double', () async {
          // Arrange
          final filter = {
            'rating': {r'$lte': 5.0},
          }; // Articles 0, 1, 2 have ratings 3.0, 4.0, 5.0

          // Act
          final response = await clientWithData.readAll(filter: filter);

          // Assert
          expect(response.data.items.length, 3);
          expect(response.data.items.every((a) => a.rating <= 5.0), isTrue);
        });

        test(r'should filter using $lt (<) operator on a double', () async {
          // Arrange
          final filter = {
            'rating': {r'$lt': 5.0},
          }; // Articles 0, 1 have ratings 3.0, 4.0

          // Act
          final response = await clientWithData.readAll(filter: filter);

          // Assert
          expect(response.data.items.length, 2);
          expect(response.data.items.every((a) => a.rating < 5.0), isTrue);
        });

        test(
          'should filter using dot-notation for nested properties',
          () async {
            // Arrange
            final filter = {
              'category.name': 'Category 1',
            }; // 5 articles are in Category 1

            // Act
            final response = await clientWithData.readAll(filter: filter);

            // Assert
            expect(response.data.items.length, 5);
            expect(
              response.data.items.every((a) => a.category.name == 'Category 1'),
              isTrue,
            );
          },
        );

        test('should filter using the special "q" search parameter', () async {
          // Arrange
          final filter = {'q': 'Article 1'}; // Matches 'Article 1'

          // Act
          final response = await clientWithData.readAll(filter: filter);

          // Assert
          expect(response.data.items.length, 1);
          expect(response.data.items.first.title, 'Article 1');
        });

        test(
          'should correctly perform case-insensitive partial search with "q"',
          () async {
            // Arrange
            final filter = {'q': 'rticle 2'}; // Matches 'Article 2'

            // Act
            final response = await clientWithData.readAll(filter: filter);

            // Assert
            expect(response.data.items.length, 1);
            expect(response.data.items.first.title, 'Article 2');
          },
        );

        test(
          'should return no results for a non-matching "q" search',
          () async {
            // Arrange
            final filter = {'q': 'NonExistent'};

            // Act
            final response = await clientWithData.readAll(filter: filter);

            // Assert
            expect(response.data.items, isEmpty);
          },
        );

        test('should combine "q" search with other filters', () async {
          // Arrange: Search for 'Article' (matches all) but only published
          final filter = {'q': 'Article', 'isPublished': true};

          // Act
          final response = await clientWithData.readAll(filter: filter);

          // Assert
          expect(response.data.items.length, 5);
          expect(response.data.items.every((a) => a.isPublished), isTrue);
        });
      });

      group('sorting', () {
        test('should sort by a single field in descending order', () async {
          // Arrange
          final sort = [const SortOption('rating', SortOrder.desc)];

          // Act
          final response = await clientWithData.readAll(sort: sort);

          // Assert
          expect(response.data.items.first.rating, 12.0); // Highest rating
          expect(response.data.items.last.rating, 3.0); // Lowest rating
        });

        test('should sort by multiple fields', () async {
          // Arrange: Sort by isPublished (desc), then rating (asc)
          final sort = [
            const SortOption('isPublished', SortOrder.desc),
            const SortOption('rating'),
          ];

          // Act
          final response = await clientWithData.readAll(sort: sort);
          final items = response.data.items;

          // Assert: First 5 items are published, sorted by rating ascending
          final publishedItems = items.take(5).toList();
          expect(publishedItems.every((a) => a.isPublished), isTrue);
          expect(publishedItems.first.rating, 3.0); // id-0, rating 3.0
          expect(publishedItems.last.rating, 11.0); // id-8, rating 11.0

          // Assert: Last 5 items are not published, sorted by rating ascending
          final unpublishedItems = items.skip(5).toList();
          expect(unpublishedItems.every((a) => !a.isPublished), isTrue);
          expect(unpublishedItems.first.rating, 4.0); // id-1, rating 4.0
          expect(unpublishedItems.last.rating, 12.0); // id-9, rating 12.0
        });

        test('should handle null values by sorting them last', () async {
          // Arrange: Sort by publishedAt ascending. Nulls should be last.
          final sort = [const SortOption('publishedAt')];

          // Act
          final response = await clientWithData.readAll(sort: sort);
          final items = response.data.items;

          // Assert: First 5 items have non-null dates and are sorted
          final nonNullItems = items.take(5).toList();
          expect(nonNullItems.every((a) => a.publishedAt != null), isTrue);
          expect(nonNullItems.first.publishedAt, DateTime(2024)); // Article 0
          expect(
            nonNullItems.last.publishedAt,
            DateTime(2024).add(Duration(days: 8)),
          ); // Article 8

          // Assert: Last 5 items have null dates
          final nullItems = items.skip(5).toList();
          expect(nullItems.every((a) => a.publishedAt == null), isTrue);
        });
      });

      group('pagination', () {
        test('should respect limit and set hasMore to true', () async {
          // Arrange
          // Sort by ID to have a predictable order for cursor check
          final sort = [const SortOption('id')];
          final pagination = PaginationOptions(limit: 5);

          // Act
          final response = await clientWithData.readAll(
            sort: sort,
            pagination: pagination,
          );

          // Assert
          expect(response.data.items.length, 5);
          expect(response.data.hasMore, isTrue);
          expect(response.data.cursor, 'id-4'); // Last item in the page
        });

        test('should set hasMore to false when items match limit', () async {
          // Arrange
          final pagination = PaginationOptions(limit: 10);

          // Act
          final response = await clientWithData.readAll(pagination: pagination);

          // Assert
          expect(response.data.items.length, 10);
          expect(response.data.hasMore, isFalse);
          expect(response.data.cursor, isNull);
        });

        test(
          'should set hasMore to false when items are less than limit',
          () async {
            // Arrange
            final pagination = PaginationOptions(limit: 15);

            // Act
            final response = await clientWithData.readAll(
              pagination: pagination,
            );

            // Assert
            expect(response.data.items.length, 10);
            expect(response.data.hasMore, isFalse);
            expect(response.data.cursor, isNull);
          },
        );

        test('should fetch the next page correctly using a cursor', () async {
          // Arrange: sort by ID for predictable order
          final sort = [const SortOption('id')];
          final firstPagePagination = PaginationOptions(limit: 4);

          // Act: Get the first page
          final firstResponse = await clientWithData.readAll(
            sort: sort,
            pagination: firstPagePagination,
          );
          final cursor = firstResponse.data.cursor;

          // Assert first page is correct
          expect(firstResponse.data.items.length, 4);
          expect(firstResponse.data.hasMore, isTrue);
          expect(cursor, 'id-3');

          // Act: Get the second page using the cursor
          final secondPagePagination = PaginationOptions(
            limit: 4,
            cursor: cursor,
          );
          final secondResponse = await clientWithData.readAll(
            sort: sort,
            pagination: secondPagePagination,
          );

          // Assert second page is correct
          expect(secondResponse.data.items.length, 4);
          expect(secondResponse.data.hasMore, isTrue);
          expect(secondResponse.data.items.first.id, 'id-4');
          expect(secondResponse.data.items.last.id, 'id-7');
          expect(secondResponse.data.cursor, 'id-7');
        });

        test('should return an empty list for a non-existent cursor', () async {
          // Arrange
          final pagination = PaginationOptions(cursor: 'non-existent-id');

          // Act
          final response = await clientWithData.readAll(pagination: pagination);

          // Assert
          expect(response.data.items, isEmpty);
          expect(response.data.hasMore, isFalse);
          expect(response.data.cursor, isNull);
        });
      });
    });

    group('count', () {
      late DataInMemory<Article> clientWithData;

      setUp(() {
        clientWithData = DataInMemory<Article>(
          getId: (article) => article.id,
          toJson: (article) => article.toJson(),
          initialData: createTestArticles(10),
        );
      });

      test('should return the total count of all items', () async {
        final response = await clientWithData.count();
        expect(response.data, 10);
      });

      test('should return the count of items matching a filter', () async {
        final filter = {'isPublished': true}; // 5 articles are published
        final response = await clientWithData.count(filter: filter);
        expect(response.data, 5);
      });

      test('should return 0 for a filter with no matches', () async {
        final filter = {'title': 'Non-existent Title'};
        final response = await clientWithData.count(filter: filter);
        expect(response.data, 0);
      });

      test('should return the correct count for a user scope', () async {
        const userId = 'user-xyz';
        await clientWithData.create(
          item: Article(
            id: 'user-article-1',
            title: 'User Article 1',
            category: Category(id: 'cat-1', name: 'Category 1'),
          ),
          userId: userId,
        );
        await clientWithData.create(
          item: Article(
            id: 'user-article-2',
            title: 'User Article 2',
            category: Category(id: 'cat-2', name: 'Category 2'),
          ),
          userId: userId,
        );

        final response = await clientWithData.count(userId: userId);
        expect(response.data, 2);
      });
    });

    group('aggregate', () {
      late DataInMemory<Article> clientWithData;

      setUp(() {
        clientWithData = DataInMemory<Article>(
          getId: (article) => article.id,
          toJson: (article) => article.toJson(),
          initialData: createTestArticles(10),
        );
      });

      test(r'should process a simple $match stage', () async {
        final pipeline = [
          {
            r'$match': {'isPublished': true},
          },
        ];
        final response = await clientWithData.aggregate(pipeline: pipeline);
        expect(response.data.length, 5);
        expect(
          response.data.every((item) => item['isPublished'] == true),
          isTrue,
        );
      });

      test(r'should process a $group stage with $sum accumulator', () async {
        final pipeline = [
          {
            r'$group': {
              '_id': r'$category.id',
              'count': {r'$sum': 1},
            },
          },
          {
            r'$sort': {'_id': 1},
          },
        ];

        final response = await clientWithData.aggregate(pipeline: pipeline);

        expect(response.data.length, 2);
        expect(response.data[0], {'_id': 'cat-0', 'count': 5});
        expect(response.data[1], {'_id': 'cat-1', 'count': 5});
      });

      test(r'should process a $sort stage', () async {
        final pipeline = [
          {
            r'$sort': {'rating': -1},
          },
        ];
        final response = await clientWithData.aggregate(pipeline: pipeline);
        expect(response.data.length, 10);
        expect(response.data.first['rating'], 12.0); // Highest rating
        expect(response.data.last['rating'], 3.0); // Lowest rating
      });

      test(r'should process a $limit stage', () async {
        final pipeline = [
          {r'$limit': 3},
        ];
        final response = await clientWithData.aggregate(pipeline: pipeline);
        expect(response.data.length, 3);
      });

      test(
        r'should process a complex pipeline ($group, $sort, $limit)',
        () async {
          final pipeline = [
            {
              r'$group': {
                '_id': r'$category.name',
                'totalRating': {r'$sum': r'$rating'},
              },
            },
            {
              r'$sort': {'totalRating': -1},
            },
            {r'$limit': 1},
          ];

          final response = await clientWithData.aggregate(pipeline: pipeline);

          // Category 1 has higher ratings (odd numbers)
          expect(response.data.length, 1);
          expect(response.data.first['_id'], 'Category 1');
          expect(
            response.data.first['totalRating'],
            4.0 + 6.0 + 8.0 + 10.0 + 12.0,
          );
        },
      );

      test('should process a pipeline within a user scope', () async {
        const userId = 'user-agg';
        await clientWithData.create(
          item: Article(
            id: 'user-article-1',
            title: 'User Article 1',
            category: Category(id: 'cat-user', name: 'User Category'),
          ),
          userId: userId,
        );

        final pipeline = [
          {
            r'$group': {
              '_id': r'$category.id',
              'count': {r'$sum': 1},
            },
          },
        ];

        final response = await clientWithData.aggregate(
          pipeline: pipeline,
          userId: userId,
        );
        expect(response.data.length, 1);
        expect(response.data.first, {'_id': 'cat-user', 'count': 1});
      });
    });
  });
}
