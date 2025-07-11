// ignore_for_file: prefer_const_constructors

import 'package:equatable/equatable.dart';
import 'package:ht_data_client/ht_data_client.dart';
import 'package:ht_data_inmemory/ht_data_inmemory.dart';
import 'package:ht_shared/ht_shared.dart';
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
  });

  final String id;
  final String title;
  final Category category;
  final bool isPublished;
  final double rating;

  Map<String, dynamic> toJson() => {
        'id': id,
        'title': title,
        'category': category.toJson(),
        'isPublished': isPublished,
        'rating': rating,
      };

  @override
  List<Object?> get props => [id, title, category, isPublished, rating];
}

List<Article> createTestArticles(int count) {
  return List.generate(count, (i) {
    return Article(
      id: 'id-$i',
      title: 'Article $i',
      category: Category(id: 'cat-${i % 2}', name: 'Category ${i % 2}'),
      isPublished: i % 2 == 0,
      rating: 3.0 + i,
    );
  });
}

void main() {
  group('HtDataInMemory', () {
    late HtDataInMemory<Article> client;
    late List<Article> initialArticles;

    setUp(() {
      initialArticles = createTestArticles(3);
      client = HtDataInMemory<Article>(
        getId: (article) => article.id,
        toJson: (article) => article.toJson(),
      );
    });

    group('constructor', () {
      test('can be instantiated', () {
        expect(
          client,
          isA<HtDataInMemory<Article>>(),
        );
      });

      test('loads initialData correctly', () async {
        // Arrange
        final clientWithData = HtDataInMemory<Article>(
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
          () => HtDataInMemory<Article>(
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
        final readResponse = await client.read(id: newArticle.id, userId: userId);
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
        final readResponse =
            await client.read(id: userScopedArticleToUpdate.id, userId: userId);
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
  });
}