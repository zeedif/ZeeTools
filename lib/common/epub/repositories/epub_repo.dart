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

abstract interface class EpubRepository {
  Future<Either<EpubFailure, List<EpubManifestItem>>> loadEpub(String filePath);
  Future<Either<EpubFailure, String>> readTextFile(String epubPath, String archivePath);
  Future<Either<EpubFailure, void>> writeTextFile(String epubPath, String archivePath, String content);
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

  @override
  List<String> get loadedPaths => _archives.keys.toList();

  @override
  bool isLoaded(String epubPath) => _archives.containsKey(epubPath);

  @override
  Future<Either<EpubFailure, List<EpubManifestItem>>> loadEpub(String filePath) async {
    final cached = _manifests[filePath];
    if (cached != null) return Either.right(cached);

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
        if (!EpubMediaTypes.isTextType(mediaType)) continue;
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
    return Either.right(items);
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
  Future<Either<EpubFailure, void>> writeTextFile(
    String epubPath,
    String archivePath,
    String content,
  ) async {
    final archive = _archives[epubPath];
    if (archive == null) return Either.left(const EpubFailure.invalidContainer('No EPUB loaded'));
    archive.files.removeWhere((f) => f.name == archivePath);
    final bytes = utf8.encode(content);
    archive.addFile(ArchiveFile(archivePath, bytes.length, bytes));
    return const Either.right(null);
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
  }

  static Uint8List? _readBytes(String filePath) {
    try {
      return File(filePath).readAsBytesSync();
    } catch (_) {
      return null;
    }
  }
}
