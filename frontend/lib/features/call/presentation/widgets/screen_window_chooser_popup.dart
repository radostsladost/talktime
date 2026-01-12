import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';

class ScreenWindowPopupChooser {
  /// Shows a popup dialog with a grid of screen/window sources.
  /// Returns the selected [DesktopCapturerSource], or null if canceled.
  static Future<DesktopCapturerSource?> show({
    required BuildContext context,
    String title = 'Select Screen or Window',
    double thumbnailWidth = 180,
    double thumbnailHeight = 80,
  }) async {
    return await showDialog<DesktopCapturerSource>(
      context: context,
      builder: (context) {
        return _ScreenWindowGridDialog(
          title: title,
          thumbnailWidth: thumbnailWidth,
          thumbnailHeight: thumbnailHeight,
        );
      },
    );
  }
}

// Internal dialog widget
class _ScreenWindowGridDialog extends StatefulWidget {
  final String title;
  final double thumbnailWidth;
  final double thumbnailHeight;

  const _ScreenWindowGridDialog({
    required this.title,
    required this.thumbnailWidth,
    required this.thumbnailHeight,
  });

  @override
  State<_ScreenWindowGridDialog> createState() =>
      _ScreenWindowGridDialogState();
}

class _ScreenWindowGridDialogState extends State<_ScreenWindowGridDialog> {
  List<DesktopCapturerSource> _sources = [];
  DesktopCapturerSource? _selectedSource;
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadSources();
  }

  Future<void> _loadSources() async {
    try {
      final sources = await desktopCapturer.getSources(
        types: [SourceType.Screen, SourceType.Window],
        thumbnailSize: ThumbnailSize(
          widget.thumbnailWidth.toInt(),
          widget.thumbnailHeight.toInt(),
        ),
      );
      if (mounted) {
        setState(() {
          _sources = sources;
          _isLoading = false;
          if (_selectedSource == null && sources.isNotEmpty) {
            _selectedSource = sources.first;
          }
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
      debugPrint('Failed to load sources: $e');
    }
  }

  void _confirmSelection() {
    if (_selectedSource != null) {
      Navigator.of(context).pop(_selectedSource);
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(widget.title),
      content: SizedBox(
        width: min(MediaQuery.sizeOf(context).width * 0.9, 800),
        height: 500,
        child: _isLoading
            ? const Center(child: CircularProgressIndicator())
            : _sources.isEmpty
            ? const Center(child: Text('No screens or windows found.'))
            : LayoutBuilder(
                builder: (context, constraints) {
                  int crossAxisCount = 1;
                  if (constraints.maxWidth >= 700)
                    crossAxisCount = 3;
                  else if (constraints.maxWidth >= 450)
                    crossAxisCount = 2;

                  return GridView.builder(
                    padding: const EdgeInsets.all(4),
                    gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                      crossAxisCount: crossAxisCount,
                      crossAxisSpacing: 10,
                      mainAxisSpacing: 10,
                      childAspectRatio:
                          widget.thumbnailWidth / widget.thumbnailHeight,
                    ),
                    itemCount: _sources.length,
                    itemBuilder: (context, index) {
                      final source = _sources[index];
                      final isSelected = _selectedSource?.id == source.id;

                      return GestureDetector(
                        onTap: () {
                          setState(() {
                            _selectedSource = source;
                          });
                        },
                        child: Card(
                          shape: isSelected
                              ? RoundedRectangleBorder(
                                  side: BorderSide(
                                    color: Theme.of(
                                      context,
                                    ).colorScheme.primary,
                                    width: 2,
                                  ),
                                  borderRadius: BorderRadius.circular(6),
                                )
                              : null,
                          clipBehavior: Clip.hardEdge,
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              buildSourcePreview(source),
                              Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 6,
                                  vertical: 4,
                                ),
                                color: isSelected
                                    ? Theme.of(
                                        context,
                                      ).colorScheme.primary.withOpacity(0.1)
                                    : null,
                                child: Text(
                                  source.name,
                                  maxLines: 2,
                                  overflow: TextOverflow.ellipsis,
                                  textAlign: TextAlign.center,
                                  style: TextStyle(
                                    fontWeight: isSelected
                                        ? FontWeight.bold
                                        : FontWeight.normal,
                                    color: isSelected
                                        ? Theme.of(context).colorScheme.primary
                                        : null,
                                    fontSize: 12,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      );
                    },
                  );
                },
              ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: _selectedSource == null ? null : _confirmSelection,
          child: const Text('Select'),
        ),
      ],
    );
  }

  Widget buildSourcePreview(DesktopCapturerSource source) {
    if (source.thumbnail != null) {
      return Expanded(
        child: Image.memory(source.thumbnail!, fit: BoxFit.cover),
      );
    }

    // Fallback icons based on source type
    final isScreen =
        source.id.toLowerCase().contains('screen') ||
        source.name.toLowerCase().contains('screen');

    return Expanded(
      child: Container(
        alignment: Alignment.center,
        child: Icon(
          isScreen ? Icons.monitor : Icons.apps,
          color: Colors.white54,
        ),
      ),
    );
  }
}
