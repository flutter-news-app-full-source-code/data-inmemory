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
  });
}