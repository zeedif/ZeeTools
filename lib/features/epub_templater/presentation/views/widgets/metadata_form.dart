import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '/common/theme/app_dimensions.dart';
import '/common/utils/input_formatters.dart';
import '/common/utils/list_toggle.dart';
import '/common/widgets/app_text_field.dart';
import '/common/widgets/editable_list.dart';
import '/common/widgets/field_grid.dart';
import '/common/widgets/field_group.dart';
import '/common/widgets/form_page.dart';
import '/common/widgets/form_section.dart';
import '/common/widgets/outlined_dropdown.dart';
import '/common/widgets/selection_pill.dart';
import '/features/settings/data/preferences_repo.dart';
import '/features/settings/domain/date_display_format.dart';
import '/inject_dependencies.dart';
import '../../../data/epub_template_builder.dart';
import '../../../domain/book_metadata.dart';
import '../../../domain/marc_relator.dart';
import '../../../domain/metadata_field.dart';
import '../../../domain/subjects.dart';
import '../../../domain/title_languages.dart';
import 'amazon_lookup.dart';

const mixedValuesHint = 'Varios valores';
const noValueHint = 'Sin valor';

// [mixed]: campos que difieren entre los libros editados; se muestran vacíos y
// solo se aplican a todos si se les da un valor. Con [multiple], los campos que
// ningún libro tiene se señalan como vacíos en todos.
class const MetadataForm({
  super.key,
  required final BookMetadata metadata,
  required final ValueChanged<BookMetadata Function(BookMetadata m)> onChanged,
  final Set<MetadataField> mixed = const {},
  final bool multiple = false,
  final VoidCallback? onRegenerateIdentifier,
  // La plantilla tiene página de título: se editan sus créditos y enlaces.
  final bool showCredits = false,
}) extends StatelessWidget {
  String? _status(MetadataField field) {
    if (mixed.contains(field)) return mixedValuesHint;
    if (!multiple) return null;
    return switch (field.read(metadata)) {
      null => noValueHint,
      String value when value.trim().isEmpty => noValueHint,
      List<Object?> value when value.isEmpty => noValueHint,
      _ => null,
    };
  }

  String? _hint(MetadataField field, [String? hint]) => _status(field) ?? hint;

  @override
  Widget build(BuildContext context) {
    final m = metadata;
    final web = m.isWebNovel && !mixed.contains(MetadataField.bookType);
    final bookOriginal = scriptedLanguages.where((o) => o.name == m.language.trim().toLowerCase().split('-').first).firstOrNull;
    final original = bookOriginal ?? m.original;
    final main = original?.mainLanguage ?? mainTitleLanguage;
    final required = requiredAlternate(m.language, main: main);
    // Lo que difiere entre libros no se señala: se muestra vacío a propósito.
    final problems = metadataProblems(m, main: main)..removeWhere((field, _) => mixed.contains(field) || (field == MetadataField.series && mixed.contains(MetadataField.standalone)));
    int issues(Set<MetadataField> fields) => problems.keys.where(fields.contains).length;
    Widget identifiers(Widget? lookup) => FieldGrid(
      columns: 4,
      children: [
        _BookTypeField(
          value: m.bookType,
          hint: _hint(MetadataField.bookType),
          onChanged: (v) => onChanged((m) => m.copyWith(bookType: v)),
        ),
        AppTextField(
          label: 'ASIN de ${m.amazonStore.label}',
          value: m.asin,
          hint: _hint(MetadataField.asin),
          enabled: !web,
          suffix: lookup,
          onChanged: (v) => onChanged((m) => m.copyWith(asin: v.trim().toUpperCase())),
        ),
        AppTextField(
          label: 'ISBN-13',
          value: m.isbn13,
          hint: _hint(MetadataField.isbn13, '978-XX-XXXX-XXX-X'),
          enabled: !web,
          inputFormatters: [isbnFormatter(isbn13Groups)],
          error: problems[MetadataField.isbn13]?.label,
          onChanged: (v) => onChanged(
            (m) => m.copyWith(
              isbn13: v,
              isbn10: switch (isbn10From13(v)) {
                final ten? when m.isbn10.trim().isEmpty => formatIsbn(ten, isbn10Groups),
                _ => m.isbn10,
              },
            ),
          ),
        ),
        AppTextField(
          label: 'ISBN-10',
          value: m.isbn10,
          hint: _hint(MetadataField.isbn10, 'XX-XXXX-XXX-X'),
          enabled: !web,
          inputFormatters: [isbnFormatter(isbn10Groups)],
          error: problems[MetadataField.isbn10]?.label,
          onChanged: (v) => onChanged(
            (m) => m.copyWith(
              isbn10: v,
              isbn13: switch (isbn13From10(v)) {
                final thirteen? when m.isbn13.trim().isEmpty => formatIsbn(thirteen, isbn13Groups),
                _ => m.isbn13,
              },
            ),
          ),
        ),
      ],
    );
    final hasSeries = m.hasSeries || mixed.contains(MetadataField.series);
    final theme = Theme.of(context);
    void movePublisher(int from, int to) => onChanged(
      (m) => m.copyWith(
        publishers: [...m.publishers]
          ..removeAt(from)
          ..insert(to, m.publishers[from]),
      ),
    );
    final addPublisher = OutlinedButton.icon(
      icon: const Icon(Icons.add),
      label: const Text('Añadir editorial'),
      onPressed: () => onChanged((m) => m.copyWith(publishers: [...m.publishers, ''])),
    );

    return FormPage(
      showIndex: true,
      sections: [
        FormSection(
          title: 'Identificación',
          icon: Icons.fingerprint,
          issues: issues(const {MetadataField.isbn13, MetadataField.isbn10}),
          children: [
            if (multiple || web) identifiers(null) else AmazonLookup(metadata: m, onApply: onChanged, fields: identifiers),
            if (web)
              AppTextField(
                label: 'Publicación original',
                value: m.originalSource,
                hint: _hint(MetadataField.originalSource, 'https://ncode.syosetu.com/n3009bk'),
                helper: 'Página donde se publicó la novela web; una novela web no tiene ISBN ni ficha de Amazon.',
                onChanged: (v) => onChanged((m) => m.copyWith(originalSource: v.trim())),
              ),
            InputDecorator(
              decoration: InputDecoration(
                labelText: 'Identificador único',
                suffixIcon: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (!mixed.contains(MetadataField.identifier))
                      IconButton(
                        tooltip: 'Copiar',
                        icon: const Icon(Icons.copy, size: 18),
                        onPressed: () => Clipboard.setData(ClipboardData(text: 'urn:uuid:${m.identifier}')),
                      ),
                    if (onRegenerateIdentifier != null) IconButton(tooltip: 'Generar otro', icon: const Icon(Icons.refresh, size: 18), onPressed: onRegenerateIdentifier),
                  ],
                ),
              ),
              child: mixed.contains(MetadataField.identifier) ? const Text(mixedValuesHint) : SelectableText('urn:uuid:${m.identifier}'),
            ),
          ],
        ),
        FormSection(
          title: 'Título y serie',
          icon: Icons.translate,
          issues: issues(const {MetadataField.language, MetadataField.series, MetadataField.seriesIndex, MetadataField.altSeries, MetadataField.title, MetadataField.altTitles}),
          children: [
            FieldGrid(
              children: [
                OutlinedDropdown<String?>(
                  label: 'Idioma del libro',
                  value: mixed.contains(MetadataField.language) || m.language.isEmpty ? null : m.language,
                  hint: _hint(MetadataField.language),
                  helper: required == null ? null : 'El título y la serie llevan también su equivalente en ${languageName(required)}.',
                  error: problems[MetadataField.language]?.label,
                  onChanged: (v) => onChanged((m) => m.copyWith(language: v ?? m.language)),
                  items: [
                    for (final MapEntry(key: code, value: name) in bookLanguages.entries) DropdownMenuItem(value: code, child: Text(name)),
                    if (m.language.isNotEmpty && !bookLanguages.containsKey(m.language) && !mixed.contains(MetadataField.language)) DropdownMenuItem(value: m.language, child: Text(m.language)),
                  ],
                ),
                OutlinedDropdown<OriginalLanguage?>(
                  label: 'Idioma en que se escribió la obra',
                  value: original,
                  hint: _hint(MetadataField.originalLanguage),
                  helper: bookOriginal != null
                      ? 'El del libro.'
                      : switch (original) {
                          OriginalLanguage.es => 'El título y la serie principales van en español; en inglés son opcionales.',
                          OriginalLanguage(scripted: true) => 'Añade el título y la serie romanizados y en su escritura.',
                          _ => null,
                        },
                  onChanged: bookOriginal != null
                      ? null
                      : (v) {
                          if (v != null) onChanged((m) => m.withOriginal(v));
                        },
                  items: [for (final o in OriginalLanguage.values) DropdownMenuItem(value: o, child: Text(o.label))],
                ),
              ],
            ),
            Wrap(
              spacing: AppSpacing.medium,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                SegmentedButton<bool>(
                  showSelectedIcon: false,
                  emptySelectionAllowed: true,
                  segments: const [
                    ButtonSegment(value: false, label: Text('En una serie'), icon: Icon(Icons.collections_bookmark_outlined)),
                    ButtonSegment(value: true, label: Text('Volumen único'), icon: Icon(Icons.book_outlined)),
                  ],
                  selected: {if (!mixed.contains(MetadataField.standalone)) m.standalone},
                  onSelectionChanged: (v) {
                    if (v.isNotEmpty) onChanged((m) => m.copyWith(standalone: v.single));
                  },
                ),
                if (_status(MetadataField.standalone) case final status?) Text(status, style: theme.textTheme.labelLarge),
              ],
            ),
            if (!m.standalone || mixed.contains(MetadataField.standalone))
              Card.outlined(
                margin: EdgeInsets.zero,
                child: Padding(
                  padding: const EdgeInsets.all(AppPadding.medium + AppPadding.small),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    spacing: AppSpacing.medium + AppSpacing.small,
                    children: [
                      FieldGrid(
                        spans: const [2, 1],
                        children: [
                          AppTextField(
                            key: ValueKey('series-$main'),
                            label: 'Serie en ${languageName(main)}',
                            value: m.series,
                            hint: _hint(MetadataField.series),
                            helper: 'El título y sus equivalentes la siguen mientras empiecen por ella.',
                            error: problems[MetadataField.series]?.label,
                            onChanged: (v) => onChanged(
                              (m) => m.copyWith(
                                series: v,
                                seriesLang: main,
                                title: multiple ? m.title : followSeries(m.title, m.series, v),
                                titleLang: multiple ? m.titleLang : main,
                                altSeries: m.series.trim().isNotEmpty ? m.altSeries : withOriginalLanguage(m.altSeries, original),
                              ),
                            ),
                          ),
                          AppTextField(
                            label: 'Volumen',
                            value: m.seriesIndex,
                            hint: _hint(MetadataField.seriesIndex),
                            enabled: hasSeries,
                            inputFormatters: [decimalNumberFormatter],
                            error: problems[MetadataField.seriesIndex]?.label,
                            onChanged: (v) => onChanged((m) => m.copyWith(seriesIndex: v)),
                          ),
                        ],
                      ),
                      _Alternates(
                        items: m.altSeries,
                        main: main,
                        requiredLang: required,
                        original: original,
                        noun: 'Serie',
                        hint: _hint(MetadataField.altSeries),
                        error: problems[MetadataField.altSeries]?.label,
                        onChanged: (v) => onChanged((m) => m.copyWith(altSeries: v, altTitles: multiple ? m.altTitles : followSeriesAlternates(m.altTitles, m.altSeries, v))),
                      ),
                    ],
                  ),
                ),
              ),
            AppTextField(
              label: 'Colección',
              value: m.collection,
              hint: _hint(MetadataField.collection),
              helper: 'Obra que reúne varias series o volúmenes sueltos: la principal, sus derivadas y sus secuelas. Vacía si el libro no forma parte de ninguna.',
              onChanged: (v) => onChanged((m) => m.copyWith(collection: v, collectionLang: main)),
            ),
            FieldGrid(
              spans: const [2, 1],
              children: [
                AppTextField(
                  key: ValueKey('title-$main'),
                  label: 'Título en ${languageName(main)}',
                  value: m.title,
                  hint: _hint(MetadataField.title, 'Nombre de la novela - Volumen 01 [SIGLAS]'),
                  error: problems[MetadataField.title]?.label,
                  onChanged: (v) => onChanged((m) => m.copyWith(title: v, titleLang: main)),
                ),
                AppTextField(
                  label: 'Título para ordenar',
                  value: m.titleSort,
                  hint: _hint(MetadataField.titleSort),
                  helper: 'Cómo se ordena en la biblioteca; vacío, por el título.',
                  onChanged: (v) => onChanged((m) => m.copyWith(titleSort: v)),
                ),
              ],
            ),
            _Alternates(
              items: m.altTitles,
              main: main,
              requiredLang: required,
              original: original,
              noun: 'Título',
              hint: _hint(MetadataField.altTitles),
              error: problems[MetadataField.altTitles]?.label,
              onChanged: (v) => onChanged((m) => m.copyWith(altTitles: v)),
            ),
          ],
        ),
        FormSection(
          title: 'Personas',
          icon: Icons.people_outline,
          issues: issues(const {MetadataField.actors}),
          children: [
            if (mixed.contains(MetadataField.actors)) Text('Las personas que añadas sustituyen a las de cada libro · $mixedValuesHint', style: theme.textTheme.labelLarge) else if (problems[MetadataField.actors] case final problem?) Text(problem.message, style: theme.textTheme.labelLarge?.copyWith(color: theme.colorScheme.error)),
            EditableList<Actor>(
              items: m.actors,
              addLabel: 'Añadir persona',
              createItem: () => const Actor(roles: [MarcRelator.ctb]),
              onChanged: (v) => onChanged((m) => m.copyWith(actors: v)),
              gapBuilder: showCredits ? (context, i) => _CreditGap(index: i, actors: m.actors, bookLanguage: m.language, onChanged: (v) => onChanged((m) => m.copyWith(actors: v))) : null,
              itemBuilder: (context, i, actor, update, controls) => _ActorEditor(
                number: i + 1,
                actor: actor,
                onChanged: update,
                controls: controls,
                showCredits: showCredits,
                bookLanguage: m.language,
                originalScript: original != null && original.scripted ? original : null,
              ),
            ),
          ],
        ),
        FormSection(
          title: 'Publicación',
          icon: Icons.event_note_outlined,
          issues: issues(const {MetadataField.date, MetadataField.publishers, MetadataField.description}),
          children: [
            FieldGrid(
              children: [
                _DateField(
                  value: m.date,
                  hint: _hint(MetadataField.date),
                  error: problems[MetadataField.date]?.label,
                  onChanged: (v) => onChanged((m) => m.copyWith(date: v)),
                ),
                for (final (i, publisher) in m.publishers.indexed)
                  AppTextField(
                    key: ValueKey('publisher-$i-${m.publishers.length}'),
                    label: 'Editorial o grupo',
                    value: publisher,
                    error: publisher.trim().isEmpty ? problems[MetadataField.publishers]?.label : null,
                    onChanged: (v) => onChanged((m) => m.copyWith(publishers: [...m.publishers]..[i] = v)),
                    suffix: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        if (m.publishers.length > 1) ...[
                          IconButton(tooltip: 'Mover antes', icon: const Icon(Icons.arrow_back, size: 18), onPressed: i == 0 ? null : () => movePublisher(i, i - 1)),
                          IconButton(tooltip: 'Mover después', icon: const Icon(Icons.arrow_forward, size: 18), onPressed: i == m.publishers.length - 1 ? null : () => movePublisher(i, i + 1)),
                        ],
                        IconButton(tooltip: 'Quitar', icon: const Icon(Icons.close, size: 18), onPressed: () => onChanged((m) => m.copyWith(publishers: [...m.publishers]..removeAt(i)))),
                      ],
                    ),
                  ),
                // Sin editoriales, el botón lleva la etiqueta para mostrar el estado del campo.
                if (m.publishers.isEmpty) FieldGroup(label: 'Editorial o grupo', status: _status(MetadataField.publishers), error: problems[MetadataField.publishers]?.label, child: addPublisher) else addPublisher,
              ],
            ),
            if (showCredits)
              FieldGroup(
                label: 'Enlaces en la página de título',
                status: _status(MetadataField.links),
                child: EditableList<WebLink>(
                  items: m.links,
                  addLabel: 'Añadir enlace',
                  createItem: () => const WebLink(),
                  onChanged: (v) => onChanged((m) => m.copyWith(links: v)),
                  itemBuilder: (context, _, link, update, controls) => EditableRow(
                    controls: controls,
                    child: FieldGrid(
                      columns: 4,
                      spans: const [1, 1, 2],
                      children: [
                        AppTextField(
                          label: 'Etiqueta',
                          value: link.label,
                          hint: 'Página Web',
                          onChanged: (v) => update(link.copyWith(label: v)),
                        ),
                        AppTextField(
                          label: 'Texto del enlace',
                          value: link.text,
                          hint: 'La URL',
                          onChanged: (v) => update(link.copyWith(text: v)),
                        ),
                        AppTextField(
                          label: 'URL',
                          value: link.url,
                          onChanged: (v) => update(link.copyWith(url: v.trim())),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            AppTextField(
              label: 'Sinopsis',
              value: m.description,
              hint: _hint(MetadataField.description),
              error: problems[MetadataField.description]?.label,
              minLines: 4,
              maxLines: 16,
              onChanged: (v) => onChanged((m) => m.copyWith(description: v)),
            ),
          ],
        ),
        FormSection(
          title: 'Clasificación',
          icon: Icons.sell_outlined,
          issues: issues(const {MetadataField.demographic, MetadataField.genres}),
          children: [
            FieldGrid(
              columns: 2,
              minCellWidth: 320,
              children: [
                FieldGroup(
                  label: 'Demografía',
                  status: _status(MetadataField.demographic),
                  error: problems[MetadataField.demographic]?.label,
                  child: SelectionPillGroup(
                    options: Demographic.values,
                    selected: (d) => m.demographic == d,
                    label: (d) => d.label,
                    tooltip: (d) => 'Añade también «${d.ageGroup}»',
                    onTap: (d) => onChanged((m) => m.copyWith(demographic: m.demographic == d ? null : d)),
                  ),
                ),
                FieldGroup(
                  label: 'Edición',
                  status: _status(MetadataField.editions),
                  child: SelectionPillGroup(
                    options: editionFeatures,
                    selected: m.editions.contains,
                    label: (feature) => feature,
                    onTap: (feature) => onChanged((m) => m.copyWith(editions: m.editions.toggled(feature))),
                  ),
                ),
              ],
            ),
            FieldGroup(
              label: 'Géneros',
              status: _status(MetadataField.genres),
              error: problems[MetadataField.genres]?.label,
              child: SelectionPillGroup(
                options: literaryGenres,
                selected: m.genres.contains,
                label: (genre) => genre,
                onTap: (genre) => onChanged((m) => m.copyWith(genres: m.genres.toggled(genre))),
              ),
            ),
            FieldGroup(
              label: 'Calificación de calibre',
              status: _status(MetadataField.rating),
              child: _RatingField(
                value: m.rating,
                onChanged: (v) => onChanged((m) => m.copyWith(rating: v)),
              ),
            ),
          ],
        ),
      ],
    );
  }
}

// Equivalentes de un título o serie: el del idioma del libro (obligatorio), el español y el
// inglés cuando no son el principal y, si la obra se escribió en japonés, coreano o chino, el
// romanizado y el de su escritura.
class const _Alternates({
  required final List<LocalizedText> items,
  // Idioma del principal.
  required final String main,
  // Idioma del libro cuando no es el del principal.
  required final String? requiredLang,
  required final OriginalLanguage? original,
  required final String noun,
  required final ValueChanged<List<LocalizedText>> onChanged,
  final String? hint,
  // Del equivalente obligatorio.
  final String? error,
}) extends StatelessWidget {
  Widget _field(String label, String lang, {String? error}) => AppTextField(
    key: ValueKey('$noun-$lang'),
    label: '$noun $label',
    value: localizedText(items, lang),
    hint: hint,
    error: error,
    onChanged: (v) => onChanged(withLocalizedText(items, lang, v)),
  );

  @override
  Widget build(BuildContext context) {
    return FieldGrid(
      children: [
        if (requiredLang case final lang?) _field('en ${languageName(lang)}', lang, error: error),
        for (final lang in const [spanishLanguage, mainTitleLanguage])
          if (lang != main && lang != requiredLang) _field('en ${languageName(lang)}', lang),
        if (original case final o? when o.scripted) ...[
          _field('en ${o.romanization}', o.romanized),
          if (o.name != requiredLang) _field('en ${o.label.toLowerCase()}', o.name),
        ],
      ],
    );
  }
}

// Admite cualquier tipo escrito a mano además de los del catálogo.
class const _BookTypeField({required final String value, required final ValueChanged<String> onChanged, final String? hint}) extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Autocomplete<String>(
      initialValue: TextEditingValue(text: value),
      optionsBuilder: (v) => bookTypes.where((t) => t.toLowerCase().contains(v.text.toLowerCase())),
      onSelected: onChanged,
      fieldViewBuilder: (context, controller, focusNode, _) => TextField(
        controller: controller,
        focusNode: focusNode,
        onChanged: onChanged,
        decoration: InputDecoration(labelText: 'Tipo de libro', hintText: hint),
      ),
    );
  }
}

const _starSize = 28.0;

// Escala de calibre: cada estrella vale 2 y su mitad izquierda, 1. Pulsar la calificación actual la quita.
class const _RatingField({required final int? value, required final ValueChanged<int?> onChanged}) extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final rating = value ?? 0;
    return Row(
      spacing: AppSpacing.medium,
      children: [
        Tooltip(
          message: 'La mitad izquierda de una estrella cuenta media',
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              for (var star = 1; star <= 5; star++)
                MouseRegion(
                  cursor: SystemMouseCursors.click,
                  child: GestureDetector(
                    onTapUp: (details) {
                      final picked = star * 2 - (details.localPosition.dx < _starSize / 2 ? 1 : 0);
                      onChanged(picked == value ? null : picked);
                    },
                    child: Icon(
                      switch (rating - star * 2) {
                        >= 0 => Icons.star_rounded,
                        -1 => Icons.star_half_rounded,
                        _ => Icons.star_outline_rounded,
                      },
                      size: _starSize,
                      color: Theme.of(context).colorScheme.primary,
                    ),
                  ),
                ),
            ],
          ),
        ),
        Text(value == null ? 'Sin calificar' : '${rating ~/ 2}${rating.isOdd ? ',5' : ''} de 5'),
        if (value != null) IconButton(tooltip: 'Quitar la calificación', icon: const Icon(Icons.close, size: 18), onPressed: () => onChanged(null)),
      ],
    );
  }
}

// Una tarjeta por persona: identidad, funciones, traducción y créditos, cada cosa en su fila.
class const _ActorEditor({
  required final int number,
  required final Actor actor,
  required final ValueChanged<Actor> onChanged,
  required final Widget controls,
  required final bool showCredits,
  required final String bookLanguage,
  // Escritura de la obra, que se propone para los nombres de sus creadores.
  required final OriginalLanguage? originalScript,
}) extends StatefulWidget {
  @override
  State<_ActorEditor> createState() => _ActorEditorState();
}

class _ActorEditorState extends State<_ActorEditor> {
  // Sin escritura propia, el nombre va solo en alfabeto latino y no hay nombre original que escribir.
  late OriginalLanguage? _script = switch (widget.actor.scriptName) {
    final name? => scriptedLanguages.where((o) => o.name == name.lang.trim().toLowerCase()).firstOrNull,
    null when widget.actor.isCreator => widget.originalScript,
    null => null,
  };

  void _onScriptChanged(OriginalLanguage? script, String text) {
    setState(() => _script = script);
    widget.onChanged(widget.actor.copyWith(altNames: script == null || text.trim().isEmpty ? const [] : [LocalizedText(lang: script.name, text: text)]));
  }

  @override
  Widget build(BuildContext context) {
    final actor = widget.actor;
    final theme = Theme.of(context);
    final scriptText = actor.scriptName?.text ?? '';
    final otherLanguage = actor.translatesToOther(widget.bookLanguage);
    final languages = [
      const DropdownMenuItem(value: '', child: Text('No se menciona')),
      for (final MapEntry(key: code, value: name) in bookLanguages.entries) DropdownMenuItem(value: code, child: Text(name)),
    ];
    return Card.outlined(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(AppPadding.medium + AppPadding.small, AppPadding.medium + AppPadding.small, AppPadding.small, AppPadding.medium + AppPadding.small),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          spacing: AppSpacing.medium + AppSpacing.small,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              spacing: AppSpacing.medium + AppSpacing.small,
              children: [
                Padding(
                  padding: const EdgeInsets.only(top: AppPadding.small),
                  child: CircleAvatar(
                    radius: 14,
                    backgroundColor: actor.isCreator ? theme.colorScheme.primaryContainer : theme.colorScheme.surfaceContainerHighest,
                    child: Text('${widget.number}', style: theme.textTheme.labelMedium),
                  ),
                ),
                Expanded(
                  child: FieldGrid(
                    columns: 4,
                    minCellWidth: 180,
                    children: [
                      OutlinedDropdown<OriginalLanguage?>(
                        label: 'Idioma del nombre',
                        value: _script,
                        onChanged: (v) => _onScriptChanged(v, scriptText),
                        items: [
                          const DropdownMenuItem(value: null, child: Text('Alfabeto latino')),
                          for (final o in scriptedLanguages) DropdownMenuItem(value: o, child: Text(o.label)),
                        ],
                      ),
                      AppTextField(
                        label: switch (_script) {
                          final o? => 'Nombre en ${o.romanization}',
                          null => 'Nombre',
                        },
                        value: actor.name,
                        // El orden se deduce del nombre mientras nadie lo haya editado a mano.
                        onChanged: (name) => widget.onChanged(actor.copyWith(name: name, fileAs: actor.fileAs.isEmpty || actor.fileAs == fileAsFor(actor.name) ? fileAsFor(name) : actor.fileAs)),
                      ),
                      AppTextField(
                        label: 'Nombre para ordenar',
                        value: actor.fileAs,
                        hint: 'Apellido, Nombre',
                        enabled: actor.name.trim().isNotEmpty,
                        onChanged: (v) => widget.onChanged(actor.copyWith(fileAs: v)),
                      ),
                      if (_script case final script?)
                        AppTextField(
                          label: 'Nombre en ${script.label.toLowerCase()}',
                          value: scriptText,
                          hint: 'Opcional; va como ruby en los créditos',
                          onChanged: (v) => _onScriptChanged(script, v),
                        ),
                    ],
                  ),
                ),
                widget.controls,
              ],
            ),
            FieldGroup(
              label: 'Funciones',
              child: Wrap(
                spacing: AppSpacing.small,
                runSpacing: AppSpacing.small,
                children: [
                  for (final role in [...MarcRelator.values.where((r) => r.creator), ...MarcRelator.values.where((r) => !r.creator)])
                    SelectionPill(
                      selected: actor.roles.contains(role),
                      color: role.creator ? null : theme.colorScheme.tertiary,
                      tooltip: '${role.creator ? 'Creador' : 'Colaborador'} · marc:relators ${role.code}',
                      // Siempre queda al menos una función.
                      onTap: () => actor.roles.contains(role) && actor.roles.length == 1 ? null : widget.onChanged(actor.copyWith(roles: actor.roles.toggled(role))),
                      child: Text(role.label),
                    ),
                ],
              ),
            ),
            if (actor.isTranslator)
              FieldGrid(
                columns: 4,
                minCellWidth: 180,
                children: [
                  OutlinedDropdown<String>(
                    label: 'Traducido del',
                    value: actor.fromLang,
                    onChanged: (v) => widget.onChanged(actor.copyWith(fromLang: v ?? '')),
                    items: languages,
                  ),
                  OutlinedDropdown<String>(
                    label: 'Traducido al',
                    value: actor.toLang,
                    onChanged: (v) => widget.onChanged(actor.copyWith(toLang: v ?? '')),
                    items: languages,
                  ),
                  InputDecorator(
                    decoration: const InputDecoration(labelText: 'En los créditos', border: InputBorder.none),
                    child: Text(translationCredit(actor)),
                  ),
                ],
              ),
            if (widget.showCredits)
              FieldGrid(
                columns: 4,
                minCellWidth: 180,
                spans: const [2, 2],
                children: [
                  AppTextField(
                    label: 'Enlace en los créditos',
                    value: actor.url,
                    hint: 'https://www.facebook.com/…',
                    onChanged: (v) => widget.onChanged(actor.copyWith(url: v.trim())),
                  ),
                  CheckboxListTile(
                    dense: true,
                    contentPadding: const EdgeInsets.symmetric(horizontal: AppPadding.small),
                    controlAffinity: ListTileControlAffinity.leading,
                    title: const Text('En los créditos'),
                    subtitle: switch ((otherLanguage, actor.roles.contains(MarcRelator.dst))) {
                      (true, _) => const Text('Solo en los créditos: no tradujo al idioma del libro.'),
                      (_, true) => const Text('Entre paréntesis tras el maquetador.'),
                      _ => null,
                    },
                    value: actor.credited || otherLanguage,
                    onChanged: otherLanguage ? null : (v) => widget.onChanged(actor.copyWith(credited: v ?? true)),
                  ),
                ],
              ),
          ],
        ),
      ),
    );
  }
}

// Hueco entre la persona [index] y la siguiente: una línea en blanco en los créditos tras la primera.
// Se añade con un clic y se arrastra a otro hueco; los créditos admiten como mucho [maxCreditSeparators].
class const _CreditGap({required final int index, required final List<Actor> actors, required final String bookLanguage, required final ValueChanged<List<Actor>> onChanged}) extends StatefulWidget {
  @override
  State<_CreditGap> createState() => _CreditGapState();
}

class _CreditGapState extends State<_CreditGap> {
  bool _hovered = false;

  List<Actor> _withSeparator({int? from, int? to}) => [
    for (final (i, a) in widget.actors.indexed)
      if (i == from) a.copyWith(separated: false) else if (i == to) a.copyWith(separated: true) else a,
  ];

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final actor = widget.actors[widget.index];
    final active = actor.separated;
    final holds = actor.credited || actor.translatesToOther(widget.bookLanguage);
    final canAdd = holds && widget.actors.where((a) => a.separated).length < maxCreditSeparators;
    final chip = InputChip(
      avatar: const Icon(Icons.drag_indicator, size: 18),
      label: const Text('Línea en blanco'),
      tooltip: 'Arrástrala a otro hueco para moverla',
      deleteButtonTooltipMessage: 'Quitar la línea en blanco',
      onDeleted: () => widget.onChanged(_withSeparator(from: widget.index)),
      onPressed: () {},
    );
    return DragTarget<int>(
      onWillAcceptWithDetails: (details) => holds && !active && details.data != widget.index,
      onAcceptWithDetails: (details) => widget.onChanged(_withSeparator(from: details.data, to: widget.index)),
      builder: (context, candidates, _) {
        final line = Expanded(child: Divider(color: candidates.isNotEmpty ? theme.colorScheme.primary : null, thickness: candidates.isNotEmpty ? 2 : null));
        return SizedBox(
          height: 32,
          child: active
              ? Row(
                  children: [
                    line,
                    Draggable<int>(
                      data: widget.index,
                      axis: Axis.vertical,
                      feedback: Material(type: MaterialType.transparency, child: chip),
                      childWhenDragging: Opacity(opacity: 0.4, child: chip),
                      child: chip,
                    ),
                    line,
                  ],
                )
              : MouseRegion(
                  onEnter: (_) => setState(() => _hovered = true),
                  onExit: (_) => setState(() => _hovered = false),
                  child: Row(
                    children: [
                      if (candidates.isNotEmpty) line else const Spacer(),
                      if (canAdd)
                        AnimatedOpacity(
                          opacity: _hovered ? 1 : 0.35,
                          duration: const Duration(milliseconds: 150),
                          child: TextButton.icon(
                            icon: const Icon(Icons.add, size: 18),
                            label: const Text('Línea en blanco'),
                            onPressed: () => widget.onChanged(_withSeparator(to: widget.index)),
                          ),
                        ),
                      if (candidates.isNotEmpty) line else const Spacer(),
                    ],
                  ),
                ),
        );
      },
    );
  }
}

// Solo se elige desde el calendario, que se despliega bajo el campo.
class const _DateField({required final String value, required final ValueChanged<String> onChanged, final String? hint, final String? error}) extends StatefulWidget {
  @override
  State<_DateField> createState() => _DateFieldState();
}

class _DateFieldState extends State<_DateField> {
  final _menu = MenuController();
  // Preferencia de la aplicación, no de la plantilla: restaurar la plantilla no la cambia.
  final _preferences = getIt.isRegistered<PreferencesRepository>() ? getIt<PreferencesRepository>() : null;
  late var _format = _preferences?.getDateFormat() ?? DateDisplayFormat.iso;

  @override
  Widget build(BuildContext context) {
    final date = DateTime.tryParse(widget.value);
    return MenuAnchor(
      controller: _menu,
      menuChildren: [
        SizedBox(
          width: 320,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(AppPadding.medium + AppPadding.small, AppPadding.small, AppPadding.small, 0),
            child: Row(
              spacing: AppSpacing.medium,
              children: [
                Text('Mostrar como', style: Theme.of(context).textTheme.labelLarge),
                Expanded(
                  child: DropdownButton<DateDisplayFormat>(
                    value: _format,
                    isExpanded: true,
                    underline: const SizedBox.shrink(),
                    items: [for (final f in DateDisplayFormat.values) DropdownMenuItem(value: f, child: Text(f.pattern))],
                    onChanged: (f) {
                      if (f == null) return;
                      setState(() => _format = f);
                      _preferences?.saveDateFormat(f);
                    },
                  ),
                ),
              ],
            ),
          ),
        ),
        SizedBox(
          width: 320,
          height: 340,
          // El menú ya usa el controlador de desplazamiento primario.
          child: PrimaryScrollController.none(
            child: CalendarDatePicker(
              initialDate: date != null && date.year >= 1900 && date.year <= 2100 ? date : DateTime.now(),
              firstDate: DateTime(1900),
              lastDate: DateTime(2100),
              onDateChanged: (picked) {
                widget.onChanged(picked.toIso8601String().substring(0, 10));
                _menu.close();
              },
            ),
          ),
        ),
      ],
      builder: (context, controller, _) => InkWell(
        borderRadius: BorderRadius.circular(AppRadius.small),
        onTap: () => controller.isOpen ? controller.close() : controller.open(),
        child: InputDecorator(
          isEmpty: date == null,
          decoration: InputDecoration(
            labelText: 'Fecha de publicación',
            hintText: widget.hint,
            errorText: widget.error,
            suffixIcon: date == null ? const Icon(Icons.calendar_today, size: 18) : IconButton(tooltip: 'Quitar fecha', icon: const Icon(Icons.close, size: 18), onPressed: () => widget.onChanged('')),
          ),
          child: Text(date == null ? '' : _format.format(date)),
        ),
      ),
    );
  }
}
