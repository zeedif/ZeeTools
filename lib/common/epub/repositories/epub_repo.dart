import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:xml/xml.dart';

import '../../utils/either.dart';
import '../models/epub_failure.dart';
import '../models/epub_manifest_item.dart';
import '../utils/epub_media_types.dart';
import '../utils/epub_path_utils.dart';
import '../utils/epub_reference_rewriter.dart';

abstract interface class EpubRepository {
  Future<Either<EpubFailure, List<EpubManifestItem>>> loadEpub(String filePath, {bool Function(String mediaType) include = EpubMediaTypes.isTextType});
  Future<Either<EpubFailure, String>> readTextFile(String epubPath, String archivePath);
  Future<Either<EpubFailure, Uint8List>> readBinaryFile(String epubPath, String archivePath);
  Future<Either<EpubFailure, void>> writeTextFile(String epubPath, String archivePath, String content);
  // Si cambia la extensión, renombra el recurso y actualiza el OPF y las referencias.
  Future<Either<EpubFailure, EpubManifestItem>> replaceResource(
    String epubPath,
    EpubManifestItem item, {
    required Uint8List bytes,
    required String extension,
    required String mediaType,
  });
  Future<Either<EpubFailure, void>> saveEpub(String epubPath);
  Future<Either<EpubFailure, Uint8List>> encodeEpub(String epubPath);
  Either<EpubFailure, List<String>> discoverEpubs(String directory, {bool recursive = false});
  void unloadEpub(String epubPath);
  List<String> get loadedPaths;
  bool isLoaded(String epubPath);
}

class EpubRepositoryImpl implements EpubRepository {
  final Map<String, Archive> _archives = {};
  final Map<String, List<EpubManifestItem>> _manifests = {};
  final Map<String, String> _opfPaths = {};

  static final _itemTag = RegExp(r'<item\b[^>]*>');
  static final _idAttr = RegExp(r'''\sid\s*=\s*(["'])(.*?)\1''');
  static final _hrefAttr = RegExp(r'''(\shref\s*=\s*)(["'])(.*?)\2''');
  static final _mediaTypeAttr = RegExp(r'''(\smedia-type\s*=\s*)(["'])(.*?)\2''');

  @override
  List<String> get loadedPaths => _archives.keys.toList();

  @override
  bool isLoaded(String epubPath) => _archives.containsKey(epubPath);

  @override
  Future<Either<EpubFailure, List<EpubManifestItem>>> loadEpub(String filePath, {bool Function(String mediaType) include = EpubMediaTypes.isTextType}) async {
    final cached = _manifests[filePath];
    if (cached != null) return Either.right(cached.where((i) => include(i.mediaType)).toList());

    final bytes = _readBytes(filePath);
    if (bytes == null) return Either.left(EpubFailure.fileNotFound(filePath));

    Archive archive;
    try {
      archive = ZipDecoder().decodeBytes(bytes);
    } catch (e) {
      return Either.left(EpubFailure.invalidContainer(e.toString()));
    }

    final containerEntry = archive.findFile('META-INF/container.xml');
    if (containerEntry == null) return Either.left(const EpubFailure.containerXmlMissing());

    String opfPath;
    try {
      final doc = XmlDocument.parse(utf8.decode(containerEntry.content));
      opfPath = doc.findAllElements('rootfile').first.getAttribute('full-path') ?? '';
    } catch (_) {
      return Either.left(const EpubFailure.containerXmlMissing());
    }

    if (opfPath.isEmpty) return Either.left(EpubFailure.opfMissing(opfPath));

    final opfEntry = archive.findFile(opfPath);
    if (opfEntry == null) return Either.left(EpubFailure.opfMissing(opfPath));

    final opfBase = EpubPathUtils.parentDir(opfPath);
    final items = <EpubManifestItem>[];
    try {
      final opfDoc = XmlDocument.parse(utf8.decode(opfEntry.content));
      for (final item in opfDoc.findAllElements('item')) {
        final mediaType = item.getAttribute('media-type') ?? '';
        final href = item.getAttribute('href') ?? '';
        items.add(
          EpubManifestItem(
            id: item.getAttribute('id') ?? '',
            href: href,
            archivePath: EpubPathUtils.resolve(opfBase, href),
            mediaType: mediaType,
            properties: item.getAttribute('properties') ?? '',
          ),
        );
      }
    } catch (e) {
      return Either.left(EpubFailure.opfMissing(opfPath));
    }

    _archives[filePath] = archive;
    _manifests[filePath] = items;
    _opfPaths[filePath] = opfPath;
    return Either.right(items.where((i) => include(i.mediaType)).toList());
  }

  @override
  Future<Either<EpubFailure, String>> readTextFile(String epubPath, String archivePath) async {
    final archive = _archives[epubPath];
    if (archive == null) return Either.left(EpubFailure.fileNotFound(epubPath));

    final entry = archive.findFile(archivePath);
    if (entry == null) return Either.left(EpubFailure.fileNotFound(archivePath));

    try {
      return Either.right(utf8.decode(entry.content));
    } catch (e) {
      return Either.left(EpubFailure.encodingError(archivePath: archivePath, details: e.toString()));
    }
  }

  @override
  Future<Either<EpubFailure, Uint8List>> readBinaryFile(String epubPath, String archivePath) async {
    final archive = _archives[epubPath];
    if (archive == null) return Either.left(EpubFailure.fileNotFound(epubPath));

    final entry = archive.findFile(archivePath);
    if (entry == null) return Either.left(EpubFailure.fileNotFound(archivePath));
    return Either.right(entry.content);
  }

  @override
  Future<Either<EpubFailure, void>> writeTextFile(
    String epubPath,
    String archivePath,
    String content,
  ) async {
    final archive = _archives[epubPath];
    if (archive == null) return Either.left(const EpubFailure.invalidContainer('No EPUB loaded'));
    final bytes = utf8.encode(content);
    archive.addFile(ArchiveFile(archivePath, bytes.length, bytes));
    return const Either.right(null);
  }

  @override
  Future<Either<EpubFailure, EpubManifestItem>> replaceResource(
    String epubPath,
    EpubManifestItem item, {
    required Uint8List bytes,
    required String extension,
    required String mediaType,
  }) async {
    final archive = _archives[epubPath];
    final manifest = _manifests[epubPath];
    final opfPath = _opfPaths[epubPath];
    if (archive == null || manifest == null || opfPath == null) {
      return Either.left(const EpubFailure.invalidContainer('No EPUB loaded'));
    }

    final suffix = _freeSuffix(archive, item.archivePath, extension);
    String rename(String segment) => EpubPathUtils.withExtension(segment, extension, suffix: suffix);
    final newPath = EpubPathUtils.renameLastSegment(item.archivePath, rename);

    if (newPath != item.archivePath) {
      final old = archive.findFile(item.archivePath);
      if (old != null) archive.removeFile(old);
    }
    archive.addFile(ArchiveFile.noCompress(newPath, bytes.length, bytes));

    final updated = item.copyWith(href: EpubPathUtils.renameLastSegment(item.href, rename), archivePath: newPath, mediaType: mediaType);
    if (updated == item) return Either.right(item);

    final opfResult = await readTextFile(epubPath, opfPath);
    final opfFailure = opfResult.mapOrNull(left: (l) => l.value);
    if (opfFailure != null) return Either.left(opfFailure);
    await writeTextFile(
      epubPath,
      opfPath,
      opfResult.getOrElse((_) => '').replaceAllMapped(_itemTag, (m) {
        final tag = m[0]!;
        if (_idAttr.firstMatch(tag)?[2] != item.id) return tag;
        return tag.replaceFirstMapped(_hrefAttr, (h) => '${h[1]}${h[2]}${EpubPathUtils.renameLastSegment(h[3]!, rename)}${h[2]}').replaceFirstMapped(_mediaTypeAttr, (t) => '${t[1]}${t[2]}$mediaType${t[2]}');
      }),
    );

    if (newPath != item.archivePath) {
      for (final doc in manifest) {
        if (!EpubMediaTypes.isTextType(doc.mediaType) || doc.mediaType.contains('javascript')) continue;
        final content = (await readTextFile(epubPath, doc.archivePath)).mapOrNull(right: (r) => r.value);
        if (content == null) continue;
        final rewritten = EpubReferenceRewriter.rewrite(
          content,
          fileDir: EpubPathUtils.parentDir(doc.archivePath),
          oldPath: item.archivePath,
          renameSegment: rename,
        );
        if (rewritten != null) await writeTextFile(epubPath, doc.archivePath, rewritten);
      }
    }

    final index = manifest.indexWhere((i) => i.id == item.id);
    if (index >= 0) manifest[index] = updated;
    return Either.right(updated);
  }

  @override
  Future<Either<EpubFailure, void>> saveEpub(String epubPath) async {
    final encoded = await encodeEpub(epubPath);
    return encoded.fold(Either.left, (bytes) {
      try {
        File(epubPath).writeAsBytesSync(bytes);
        return const Either.right(null);
      } catch (e) {
        return Either.left(EpubFailure.writeError(e.toString()));
      }
    });
  }

  @override
  Future<Either<EpubFailure, Uint8List>> encodeEpub(String epubPath) async {
    final archive = _archives[epubPath];
    if (archive == null) return Either.left(const EpubFailure.invalidContainer('No EPUB loaded'));
    try {
      return Either.right(ZipEncoder().encodeBytes(archive));
    } catch (e) {
      return Either.left(EpubFailure.writeError(e.toString()));
    }
  }

  @override
  Either<EpubFailure, List<String>> discoverEpubs(
    String directory, {
    bool recursive = false,
  }) {
    try {
      final dir = Directory(directory);
      if (!dir.existsSync()) return Either.left(EpubFailure.fileNotFound(directory));
      final epubs = dir.listSync(recursive: recursive, followLinks: false).whereType<File>().where((f) => f.path.toLowerCase().endsWith('.epub')).map((f) => f.path).toList();
      return Either.right(epubs);
    } catch (e) {
      return Either.left(EpubFailure.unexpected(e.toString()));
    }
  }

  @override
  void unloadEpub(String epubPath) {
    _archives.remove(epubPath);
    _manifests.remove(epubPath);
    _opfPaths.remove(epubPath);
  }

  // '' si el nombre con la nueva extensión está libre; si no, '-1', '-2'...
  static String _freeSuffix(Archive archive, String archivePath, String extension) {
    for (var n = 0; ; n++) {
      final suffix = n == 0 ? '' : '-$n';
      final candidate = EpubPathUtils.renameLastSegment(archivePath, (s) => EpubPathUtils.withExtension(s, extension, suffix: suffix));
      if (candidate == archivePath || archive.findFile(candidate) == null) return suffix;
    }
  }

  static Uint8List? _readBytes(String filePath) {
    try {
      return File(filePath).readAsBytesSync();
    } catch (_) {
      return null;
    }
  }
}
