import 'css_rules.dart';

// Declaración que un libro cambió sobre el template con el que se hizo. [removed]: el libro
// la quitó y [value] es el valor al que vuelve.
typedef StyleDelta = ({String context, String selector, String property, String value, bool removed});

typedef StyleKey = (String context, String selector);

// Prefijos de motores que ningún lector de EPUB usa: su presencia o ausencia no es una decisión del libro.
const _noise = ['-ms-', '-moz-', '-epub-'];
const _sides = ['top', 'right', 'bottom', 'left'];
const _inherited = {
  'color',
  'font-family',
  'font-size',
  'font-style',
  'font-variant',
  'font-weight',
  'letter-spacing',
  'line-height',
  'list-style',
  'list-style-type',
  'list-style-position',
  'text-align',
  'text-indent',
  'text-transform',
  'hyphens',
  '-webkit-hyphens',
  'adobe-hyphenate',
  'orphans',
  'widows',
  'word-spacing',
  'white-space',
  'quotes',
};
const _initial = {
  'border': 'none',
  'border-top': 'none',
  'border-bottom': 'none',
  'border-left': 'none',
  'border-right': 'none',
  'opacity': '1',
  'max-height': 'none',
  'max-width': 'none',
  'width': 'auto',
  'height': 'auto',
  'background': 'none',
  'background-color': 'transparent',
  'vertical-align': 'baseline',
  'text-decoration': 'none',
  'object-fit': 'fill',
  'float': 'none',
  'clear': 'none',
  'page-break-before': 'auto',
  'page-break-after': 'auto',
  'page-break-inside': 'auto',
  'break-before': 'auto',
  'break-after': 'auto',
  'break-inside': 'auto',
  'margin-top': '0',
  'margin-right': '0',
  'margin-bottom': '0',
  'margin-left': '0',
  'padding-top': '0',
  'padding-right': '0',
  'padding-bottom': '0',
  'padding-left': '0',
};
const _blockElements = {
  'address',
  'article',
  'aside',
  'blockquote',
  'body',
  'dd',
  'details',
  'div',
  'dl',
  'dt',
  'figcaption',
  'figure',
  'footer',
  'h1',
  'h2',
  'h3',
  'h4',
  'h5',
  'h6',
  'header',
  'hr',
  'html',
  'main',
  'nav',
  'ol',
  'p',
  'pre',
  'section',
  'summary',
  'ul',
};
// Sin display propio, cada elemento se muestra como lo pone la hoja del lector, no con el valor inicial (inline).
final _userAgentDisplay = {
  'table': 'table',
  'tr': 'table-row',
  'td': 'table-cell',
  'th': 'table-cell',
  'thead': 'table-header-group',
  'tbody': 'table-row-group',
  'tfoot': 'table-footer-group',
  'caption': 'table-caption',
  'col': 'table-column',
  'colgroup': 'table-column-group',
  'li': 'list-item',
  'ruby': 'ruby',
  'rt': 'ruby-text',
  'rp': 'none',
  for (final element in _blockElements) element: 'block',
};

// display que da el lector al elemento del selector («table», «div.x» → block); null si el selector no nombra el elemento.
String? _userAgentDisplayOf(String selector) {
  final element = RegExp(r'^[a-zA-Z][\w-]*').firstMatch(selector.trim().split(RegExp(r'[\s>+~]+')).last)?.group(0)?.toLowerCase();
  return element == null ? null : _userAgentDisplay[element] ?? 'inline';
}

String normalizeSelector(String selector) => selector.replaceAllMapped(RegExp(r'\s*([>+~])\s*'), (m) => ' ${m[1]} ').replaceAll(RegExp(r'\s+'), ' ').trim();

// Forma comparable de un valor: sin diferencias de mayúsculas, comillas, espacios ni decimales de más.
String normalizeValue(String value) {
  var v = value.replaceAll("'", '"').trim();
  v = v.replaceAllMapped(RegExp(r'(?<![\w#-])(\d*\.?\d+)([a-zA-Z%]*)'), (m) {
    final number = double.parse(m[1]!);
    final text = number.toStringAsFixed(4).replaceFirst(RegExp(r'0+$'), '').replaceFirst(RegExp(r'\.$'), '');
    final unit = m[2]!.toLowerCase();
    return double.parse(text) == 0 && unit.isNotEmpty && unit != '%' ? '0' : '$text$unit';
  });
  v = v.replaceAllMapped(RegExp(r'"\s*(?=\d)'), (_) => '" ').replaceAll(RegExp(r'\s+'), ' ');
  return v.contains('"') || v.contains('url(') ? v : v.toLowerCase();
}

// margin y padding por lados, para comparar «margin: 1em 0» con «margin-top: 1em».
List<(String, String)> _expand(String property, String value) {
  if ((property != 'margin' && property != 'padding') || value.contains('(')) return [(property, value)];
  final important = value.contains('!important') ? ' !important' : '';
  final parts = value.replaceAll('!important', '').trim().split(RegExp(r'\s+'));
  if (parts.isEmpty || parts.length > 4 || parts.first.isEmpty) return [(property, value)];
  final values = switch (parts.length) {
    1 => [parts[0], parts[0], parts[0], parts[0]],
    2 => [parts[0], parts[1], parts[0], parts[1]],
    3 => [parts[0], parts[1], parts[2], parts[1]],
    _ => parts,
  };
  return [for (var i = 0; i < 4; i++) ('$property-${_sides[i]}', '${values[i]}$important')];
}

// Valores de cada selector tras aplicar la cascada de la hoja. Una propiedad repetida dentro
// de una regla es un respaldo (1em y luego 1lh) y se conservan todos sus valores.
class StyleSheetValues {
  StyleSheetValues(String css) {
    for (final rule in parseCss(css)) {
      if (rule.prelude.startsWith('@') || (rule.context.isNotEmpty && !rule.context.startsWith('@media'))) continue;
      for (final selector in selectorsOf(rule.prelude)) {
        final slot = rules.putIfAbsent((rule.context, normalizeSelector(selector)), () => {});
        final seen = <String>{};
        for (final (name, value) in declarations(rule.body)) {
          if (_noise.any(name.startsWith)) continue;
          for (final (property, v) in _expand(name, value)) {
            if (seen.add(property)) {
              slot[property] = [v];
            } else {
              slot[property]!.add(v);
            }
          }
        }
      }
    }
  }

  // Hoja de la versión anterior a [newer]. [changes] trae enteras las reglas que eran distintas; una regla vacía no existía.
  StyleSheetValues.before(StyleSheetValues newer, String changes) {
    rules.addAll(newer.rules);
    for (final MapEntry(:key, value: slot) in StyleSheetValues(changes).rules.entries) {
      if (slot.isEmpty) {
        rules.remove(key);
      } else {
        rules[key] = slot;
      }
    }
  }

  final rules = <StyleKey, Map<String, List<String>>>{};

  // Selector menos específico que da el valor cuando este no lo declara: «h2.subtitulo» → «h2», «.nota p» → «p».
  static String? fallbackOf(String selector) {
    final element = RegExp(r'^[a-zA-Z][\w-]*').firstMatch(selector.split(' ').last)?.group(0);
    return element == null || element == selector ? null : element;
  }

  List<String>? own(StyleKey key, String property) => rules[key]?[property];

  List<String>? values(StyleKey key, String property) {
    final declared = own(key, property);
    if (declared != null || key.$1.isNotEmpty) return declared;
    final fallback = fallbackOf(key.$2);
    return fallback == null ? null : own(('', fallback), property);
  }

  String? value(StyleKey key, String property) => values(key, property)?.last;
}

bool _same(String? a, String? b) => a == null || b == null ? a == b : normalizeValue(a) == normalizeValue(b);

List<StyleDelta> diffStyles(StyleSheetValues book, StyleSheetValues base) {
  final out = <StyleDelta>[];
  for (final key in [...book.rules.keys, ...base.rules.keys.where((k) => !book.rules.containsKey(k))]) {
    final fallback = StyleSheetValues.fallbackOf(key.$2);
    // Una regla de clase que el libro quitó deja la clase sin efecto: no hay nada que trasladar.
    if (!book.rules.containsKey(key) && fallback == null) continue;
    final mineRule = book.rules[key] ?? const <String, List<String>>{};
    final baseRule = base.rules[key] ?? const <String, List<String>>{};
    for (final property in [...mineRule.keys, ...baseRule.keys.where((k) => !mineRule.containsKey(k))]) {
      var mine = book.value(key, property);
      final theirs = base.value(key, property);
      // Un valor propio que coincide con lo que el template heredaba deja de coincidir si el libro cambió ese origen.
      final reasserts = key.$1.isEmpty && fallback != null && mineRule.containsKey(property) && !baseRule.containsKey(property) && !_same(book.value(('', fallback), property), base.value(('', fallback), property));
      if (_same(mine, theirs) && !reasserts) continue;
      final removed = mine == null;
      // Solo cuenta como decisión del libro quitar una declaración de una regla que conserva.
      if (removed && !book.rules.containsKey(key)) continue;
      if (removed) {
        mine = _inherited.contains(property)
            ? 'inherit'
            : property == 'display'
            ? _userAgentDisplayOf(key.$2)
            : _initial[property];
        if (mine == null || _same(mine, theirs)) continue;
      }
      out.add((context: key.$1, selector: key.$2, property: property, value: mine, removed: removed));
    }
  }
  return out;
}

// Hojas del template anterior: la última versión entera y, de la más reciente a la más antigua,
// lo que cada versión previa tenía distinto de la que le sigue.
typedef LegacyTemplates = ({String latest, String earlier});

final _versionMark = RegExp(r'/\*\s*Versión [^*]*\*/');

// Diferencias del libro con la versión del template de la que parte: la que menos diferencias deja.
List<StyleDelta> legacyDeltas(String bookCss, LegacyTemplates templates) {
  final book = StyleSheetValues(bookCss);
  var template = StyleSheetValues(templates.latest);
  var best = diffStyles(book, template);
  for (final changes in templates.earlier.split(_versionMark).skip(1)) {
    if (best.isEmpty) break;
    template = StyleSheetValues.before(template, changes);
    final deltas = diffStyles(book, template);
    if (deltas.length < best.length) best = deltas;
  }
  return best;
}
