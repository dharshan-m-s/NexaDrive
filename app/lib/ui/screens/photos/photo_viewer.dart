import 'dart:typed_data';
import 'dart:ui';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import '../../../core/models/file_entry.dart';
import '../../../services/api.dart';
import '../files/file_share_sheet.dart';

class PhotoViewer extends StatefulWidget {
  final List<Map<String, dynamic>> photos;
  final int initialIndex;
  final Api api;
  const PhotoViewer({
    super.key,
    required this.photos,
    required this.initialIndex,
    required this.api,
  });

  @override
  State<PhotoViewer> createState() => _PhotoViewerState();
}

class _PhotoViewerState extends State<PhotoViewer> {
  late PageController _controller;
  late int _current;
  final Map<String, Uint8List> _fullCache = {};

  // Paging through a big library must not accumulate every original in RAM.
  // Hold at most a few full-resolution images (current page + near neighbors).
  static const _maxCached = 5;

  @override
  void initState() {
    super.initState();
    _current = widget.initialIndex;
    _controller = PageController(initialPage: widget.initialIndex);
    _ensureCached(widget.initialIndex);
  }

  @override
  void dispose() {
    _controller.dispose();
    _fullCache.clear();
    super.dispose();
  }

  void _cacheInsert(String path, Uint8List bytes) {
    _fullCache[path] = bytes;
    if (_fullCache.length <= _maxCached) return;
    // Evict the cached entry furthest from the current page.
    String? evict;
    var furthest = -1;
    for (final entry in _fullCache.entries) {
      final idx = widget.photos.indexWhere((p) => p['path'] == entry.key);
      if (idx == -1) continue;
      final dist = (idx - _current).abs();
      if (dist > furthest) {
        furthest = dist;
        evict = entry.key;
      }
    }
    if (evict != null) _fullCache.remove(evict);
  }

  Future<void> _ensureCached(int index) async {
    if (index < 0 || index >= widget.photos.length) return;
    final path = widget.photos[index]['path'] as String;
    if (_fullCache.containsKey(path)) return;
    try {
      final bytes = await widget.api.download(path);
      if (mounted) setState(() => _cacheInsert(path, bytes));
    } catch (_) {}
  }

  void _onPageChanged(int index) {
    setState(() => _current = index);
    for (final offset in [-1, 0, 1]) {
      _ensureCached(index + offset);
    }
  }

  Future<void> _downloadCurrent() async {
    try {
      final p = widget.photos[_current];
      final name = p['name'] as String? ?? (p['path'] as String).split('/').last;
      final uri = await FilePicker.saveFile(
        dialogTitle: 'Save $name',
        fileName: name,
        bytes: Uint8List(0),
      );
      final outPath = uri?.toFilePath();
      if (outPath == null) return;
      await widget.api.downloadToFile(p['path'] as String, outPath);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Saved to $outPath')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(e.toString())),
        );
      }
    }
  }

  void _shareCurrent() {
    final p = widget.photos[_current];
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (_) => FileShareSheet(
        api: widget.api,
        files: [FileEntry.fromJson(Map<String, dynamic>.from(p))],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF000000),
      extendBodyBehindAppBar: true,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        foregroundColor: Colors.white,
        elevation: 0,
        title: Text('${_current + 1} of ${widget.photos.length}'),
      ),
      body: Stack(
        children: [
          PageView.builder(
            controller: _controller,
            onPageChanged: _onPageChanged,
            itemCount: widget.photos.length,
            itemBuilder: (context, i) {
              final p = widget.photos[i];
              final bytes = _fullCache[p['path']];
              if (bytes == null) {
                _ensureCached(i);
                return const Center(
                  child: CircularProgressIndicator(color: Colors.white54, strokeWidth: 2),
                );
              }
              return InteractiveViewer(
                maxScale: 5,
                child: Center(child: Image.memory(bytes, fit: BoxFit.contain)),
              );
            },
          ),
          // Bottom bar (translucent — One UI photo viewer keeps controls low).
          Positioned(
            left: 0,
            right: 0,
            bottom: 0,
            child: BackdropFilter(
              filter: ImageFilter.blur(sigmaX: 12, sigmaY: 12),
              child: Container(
                color: Colors.white.withValues(alpha: 0.06),
                child: SafeArea(
                  top: false,
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                    children: [
                      IconButton(
                        tooltip: 'Download',
                        icon: const Icon(Icons.download_outlined, color: Colors.white),
                        onPressed: _downloadCurrent,
                      ),
                      IconButton(
                        tooltip: 'Save to My files',
                        icon: const Icon(Icons.save_alt_rounded, color: Colors.white),
                        onPressed: _downloadCurrent,
                      ),
                      IconButton(
                        tooltip: 'Share',
                        icon: const Icon(Icons.share_outlined, color: Colors.white),
                        onPressed: _shareCurrent,
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}