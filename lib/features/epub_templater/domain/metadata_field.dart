import 'package:collection/collection.dart';

import 'book_metadata.dart';

const _equality = DeepCollectionEquality();

// Campos editables de [BookMetadata], para aplicar un cambio a varios libros sin
// tocar el resto de sus valores.
enum MetadataField {
  identifier,
  language,
  title,
  titleLang,
  titleSort,
  altTitles,
  date,
  bookType,
  description,
  actors,
  publishers,
  links,
  isbn13,
  isbn10,
  asin,
  sourceUrl,
  originalSource,
  series,
  seriesLang,
  altSeries,
  seriesIndex,
  collection,
  collectionLang,
  standalone,
  originalLanguage,
  demographic,
  genres,
  editions,
  rating;

  Object? read(BookMetadata m) => switch (this) {
    identifier => m.identifier,
    language => m.language,
    title => m.title,
    titleLang => m.titleLang,
    titleSort => m.titleSort,
    altTitles => m.altTitles,
    date => m.date,
    bookType => m.bookType,
    description => m.description,
    actors => m.actors,
    publishers => m.publishers,
    links => m.links,
    isbn13 => m.isbn13,
    isbn10 => m.isbn10,
    asin => m.asin,
    sourceUrl => m.sourceUrl,
    originalSource => m.originalSource,
    series => m.series,
    seriesLang => m.seriesLang,
    altSeries => m.altSeries,
    seriesIndex => m.seriesIndex,
    collection => m.collection,
    collectionLang => m.collectionLang,
    standalone => m.standalone,
    originalLanguage => m.originalLanguage,
    demographic => m.demographic,
    genres => m.genres,
    editions => m.editions,
    rating => m.rating,
  };

  // [target] con el valor que tiene este campo en [source].
  BookMetadata copy(BookMetadata target, BookMetadata source) => switch (this) {
    identifier => target.copyWith(identifier: source.identifier),
    language => target.copyWith(language: source.language),
    title => target.copyWith(title: source.title),
    titleLang => target.copyWith(titleLang: source.titleLang),
    titleSort => target.copyWith(titleSort: source.titleSort),
    altTitles => target.copyWith(altTitles: source.altTitles),
    date => target.copyWith(date: source.date),
    bookType => target.copyWith(bookType: source.bookType),
    description => target.copyWith(description: source.description),
    actors => target.copyWith(actors: source.actors),
    publishers => target.copyWith(publishers: source.publishers),
    links => target.copyWith(links: source.links),
    isbn13 => target.copyWith(isbn13: source.isbn13),
    isbn10 => target.copyWith(isbn10: source.isbn10),
    asin => target.copyWith(asin: source.asin),
    sourceUrl => target.copyWith(sourceUrl: source.sourceUrl),
    originalSource => target.copyWith(originalSource: source.originalSource),
    series => target.copyWith(series: source.series),
    seriesLang => target.copyWith(seriesLang: source.seriesLang),
    altSeries => target.copyWith(altSeries: source.altSeries),
    seriesIndex => target.copyWith(seriesIndex: source.seriesIndex),
    collection => target.copyWith(collection: source.collection),
    collectionLang => target.copyWith(collectionLang: source.collectionLang),
    standalone => target.copyWith(standalone: source.standalone),
    originalLanguage => target.copyWith(originalLanguage: source.originalLanguage),
    demographic => target.copyWith(demographic: source.demographic),
    genres => target.copyWith(genres: source.genres),
    editions => target.copyWith(editions: source.editions),
    rating => target.copyWith(rating: source.rating),
  };

  bool same(BookMetadata a, BookMetadata b) => _equality.equals(read(a), read(b));
}

// Valores con los que se muestra un campo que difiere entre libros.
const _blank = BookMetadata(language: '', bookType: '', seriesIndex: '');

// Metadatos comunes a [books]: cada campo que difiere queda vacío y en [mixed].
({BookMetadata common, Set<MetadataField> mixed}) commonMetadata(List<BookMetadata> books) {
  final mixed = {
    for (final field in MetadataField.values)
      if (books.skip(1).any((m) => !field.same(m, books.first))) field,
  };
  var common = books.firstOrNull ?? const BookMetadata();
  for (final field in mixed) {
    common = field.copy(common, _blank);
  }
  return (common: common, mixed: mixed);
}

// Campos del formulario [edited] que cambian respecto a [common].
Set<MetadataField> changedFields(BookMetadata common, BookMetadata edited) => {
  for (final field in MetadataField.values)
    if (!field.same(common, edited)) field,
};

BookMetadata applyFields(BookMetadata target, BookMetadata source, Iterable<MetadataField> fields) => fields.fold(target, (m, field) => field.copy(m, source));
