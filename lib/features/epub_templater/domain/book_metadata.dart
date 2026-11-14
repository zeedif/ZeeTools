import 'package:freezed_annotation/freezed_annotation.dart';

import 'marc_relator.dart';
import 'subjects.dart';
import 'title_languages.dart';

part 'book_metadata.freezed.dart';
part 'book_metadata.g.dart';

// Tienda de Amazon donde se busca la ficha del libro.
enum AmazonStore {
  jp('https://www.amazon.co.jp', 'Amazon Japón', 'ja-JP,ja;q=0.9'),
  com('https://www.amazon.com', 'Amazon', 'en-US,en;q=0.9');

  const AmazonStore(this.host, this.label, this.acceptLanguage);

  final String host;
  final String label;
  final String acceptLanguage;
}

// Texto en otro idioma o escritura (alternate-script). [lang] es una etiqueta
// BCP 47: 'ja' para kanji/kana, 'ja-Latn' para romaji, 'en' para inglés.
@Freezed()
abstract class LocalizedText with _$LocalizedText {
  const factory LocalizedText({
    @Default('') String lang,
    @Default('') String text,
  }) = _LocalizedText;

  factory LocalizedText.fromJson(Map<String, dynamic> json) => _$LocalizedTextFromJson(json);
}

@Freezed()
abstract class Actor with _$Actor {
  const factory Actor({
    @Default('') String name,
    @Default('') String fileAs,
    // Nombre en su escritura original (japonés, coreano o chino); va como ruby en los créditos.
    @Default([]) List<LocalizedText> altNames,
    @Default([]) List<MarcRelator> roles,
    // Lo que sigue solo afecta a los créditos de la página de título.
    @Default(true) bool credited,
    // Deja una línea en blanco antes de la persona siguiente.
    @Default(false) bool separated,
    @Default('') String url,
    // Idiomas de la traducción; sin origen, los créditos dicen solo a qué idioma.
    @Default('') String fromLang,
    @Default('') String toLang,
  }) = _Actor;

  factory Actor.fromJson(Map<String, dynamic> json) => _$ActorFromJson(json);
}

extension ActorX on Actor {
  bool get isCreator => roles.any((r) => r.creator);

  bool get isTranslator => roles.contains(MarcRelator.trl);

  // Tradujo a otro idioma que el del libro (p. ej. del japonés al inglés en un libro en español): no es traductor
  // de este libro, así que solo figura en los créditos.
  bool translatesToOther(String bookLanguage) {
    String base(String lang) => lang.trim().toLowerCase().split('-').first;
    return isTranslator && toLang.trim().isNotEmpty && base(toLang) != base(bookLanguage);
  }

  // Funciones que se escriben en el OPF.
  List<MarcRelator> opfRoles(String bookLanguage) => translatesToOther(bookLanguage) ? roles.where((r) => r != MarcRelator.trl).toList() : roles;

  // El primer nombre en una escritura original, el único que se edita y se muestra.
  LocalizedText? get scriptName => altNames.where((t) => scriptedLanguages.any((o) => o.name == t.lang.trim().toLowerCase()) && t.text.trim().isNotEmpty).firstOrNull;
}

// Líneas en blanco que admiten los créditos: tras los creadores y antes del maquetador.
const maxCreditSeparators = 2;

// Sin separadores elegidos, una línea en blanco tras el último creador y antes del maquetador,
// como en las páginas de título de la plantilla anterior.
List<Actor> withDefaultSeparators(List<Actor> actors) {
  if (actors.any((a) => a.separated)) return actors;
  final lastCreator = actors.lastIndexWhere((a) => a.isCreator);
  final beforeLayout = actors.indexWhere((a) => a.roles.contains(MarcRelator.mrk)) - 1;
  return [
    for (final (i, a) in actors.indexed)
      if ((i == lastCreator || i == beforeLayout) && i < actors.length - 1) a.copyWith(separated: true) else a,
  ];
}

// «Nombre Apellido» → «Apellido, Nombre»; un nombre de una sola palabra queda igual.
String fileAsFor(String name) {
  final parts = name.trim().split(RegExp(r'\s+'));
  if (parts.length < 2) return name.trim();
  return '${parts.last}, ${parts.sublist(0, parts.length - 1).join(' ')}';
}

@Freezed()
abstract class WebLink with _$WebLink {
  const factory WebLink({
    @Default('') String label,
    @Default('') String url,
    // Lo que se ve del enlace; vacío = la propia URL.
    @Default('') String text,
  }) = _WebLink;

  factory WebLink.fromJson(Map<String, dynamic> json) => _$WebLinkFromJson(json);
}

@Freezed()
abstract class BookMetadata with _$BookMetadata {
  const factory BookMetadata({
    // UUID sin el prefijo urn:uuid:. Nunca se guarda en los perfiles.
    @Default('') String identifier,
    @Default('es') String language,
    @Default('') String title,
    // El título y la serie principales van en inglés; vacío equivale a [language].
    @Default('en') String titleLang,
    @Default('') String titleSort,
    @Default([]) List<LocalizedText> altTitles,
    @Default('') String date,
    @Default('Novela ligera') String bookType,
    @Default('') String description,
    @Default([]) List<Actor> actors,
    @Default([]) List<String> publishers,
    @Default([]) List<WebLink> links,
    @Default('') String isbn13,
    @Default('') String isbn10,
    @Default('') String asin,
    @Default('') String sourceUrl,
    // Página donde se publicó originalmente una novela web (dc:source).
    @Default('') String originalSource,
    @Default('') String series,
    @Default('en') String seriesLang,
    @Default([]) List<LocalizedText> altSeries,
    @Default('1') String seriesIndex,
    // Obra que reúne varias series o volúmenes sueltos (la principal, sus derivadas, sus secuelas).
    @Default('') String collection,
    @Default('') String collectionLang,
    // Volumen único: sin serie.
    @Default(false) bool standalone,
    // Idioma en que se escribió la obra; sin él se deduce de los equivalentes del título.
    OriginalLanguage? originalLanguage,
    Demographic? demographic,
    @Default([]) List<String> genres,
    @Default([]) List<String> editions,
    // Escala de calibre: 0–10 (medias estrellas).
    int? rating,
  }) = _BookMetadata;

  factory BookMetadata.fromJson(Map<String, dynamic> json) => _$BookMetadataFromJson(json);

  factory BookMetadata.initial() => BookMetadata(
    originalLanguage: OriginalLanguage.ja,
    actors: const [
      Actor(roles: [MarcRelator.aut]),
      Actor(roles: [MarcRelator.ill], separated: true),
      Actor(roles: [MarcRelator.trl], toLang: spanishLanguage, separated: true),
      Actor(roles: [MarcRelator.mrk]),
      Actor(name: 'ZeePubs', fileAs: 'ZeePubs', roles: [MarcRelator.dst], url: 'https://www.facebook.com/ZeePubs'),
    ],
    publishers: const [''],
  );
}

extension BookMetadataX on BookMetadata {
  bool get hasSeries => !standalone && series.trim().isNotEmpty;

  OriginalLanguage? get original => originalLanguage ?? originalLanguageOf(altTitles) ?? originalLanguageOf(altSeries);

  // Idioma del título y la serie principales.
  String get mainLanguage => original?.mainLanguage ?? mainTitleLanguage;

  bool get hasAuthor => actors.any((a) => a.roles.contains(MarcRelator.aut) && a.name.trim().isNotEmpty);

  bool get hasPublisher => publishers.any((x) => x.trim().isNotEmpty);

  // Una novela web no tiene ISBN ni ficha de Amazon; en su lugar, la página donde se publicó.
  bool get isWebNovel => catalogValue(bookTypes, bookType) == 'Novela web';

  // Las novelas a secas se buscan en Amazon.com; las ligeras, en Amazon Japón.
  AmazonStore get amazonStore => catalogValue(bookTypes, bookType) == 'Novela' ? AmazonStore.com : AmazonStore.jp;

  // Con otro idioma original cambia el idioma del título y la serie principales y sus equivalentes.
  BookMetadata withOriginal(OriginalLanguage lang) {
    final main = lang.mainLanguage;
    final title = withMainLanguage(this.title, titleLang.isEmpty ? language : titleLang, altTitles, main);
    final series = withMainLanguage(this.series, seriesLang.isEmpty ? language : seriesLang, altSeries, main);
    return copyWith(
      originalLanguage: lang,
      title: title.text,
      titleLang: title.lang,
      altTitles: withOriginalLanguage(title.alternates, lang),
      series: series.text,
      seriesLang: series.lang,
      altSeries: withOriginalLanguage(series.alternates, lang),
    );
  }

  // Orden: grupo de edad, demografía, géneros y edición en el orden del catálogo.
  List<String> get subjects => [
    if (demographic case final d?) ...[d.ageGroup, d.label],
    ...literaryGenres.where(genres.contains),
    ...editionFeatures.where(editions.contains),
  ];
}
