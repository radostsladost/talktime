import 'package:flutter/material.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';

class ScreenWindowGridChooser extends StatefulWidget {
  final ValueChanged<DesktopCapturerSource> onSourceSelected;
  final double thumbnailWidth;
  final double thumbnailHeight;

  const ScreenWindowGridChooser({
    super.key,
    required this.onSourceSelected,
    this.thumbnailWidth = 180,
    this.thumbnailHeight = 120,
  });

  @override
  State<ScreenWindowGridChooser> createState() =>
      _ScreenWindowGridChooserState();
}

class _ScreenWindowGridChooserState extends State<ScreenWindowGridChooser> {
  List<DesktopCapturerSource> _sources = [];
  DesktopCapturerSource? _selectedSource;

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
          if (_selectedSource == null && sources.isNotEmpty) {
            _selectedSource = sources.first;
            widget.onSourceSelected(_selectedSource!);
          }
        });
      }
    } catch (e) {
      debugPrint('Failed to load desktop sources: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        // Responsive column count
        int crossAxisCount = 1;
        if (constraints.maxWidth >= 800)
          crossAxisCount = 3;
        else if (constraints.maxWidth >= 500)
          crossAxisCount = 2;

        return GridView.builder(
          padding: const EdgeInsets.all(8),
          gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: crossAxisCount,
            crossAxisSpacing: 12,
            mainAxisSpacing: 12,
            childAspectRatio: widget.thumbnailWidth / widget.thumbnailHeight,
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
                widget.onSourceSelected(source);
              },
              child: Card(
                shape: isSelected
                    ? RoundedRectangleBorder(
                        side: BorderSide(
                          color: Theme.of(context).colorScheme.primary,
                          width: 2,
                        ),
                        borderRadius: BorderRadius.circular(8),
                      )
                    : null,
                clipBehavior: Clip.hardEdge,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: source.thumbnail != null
                          ? Image.memory(
                              source.thumbnail!,
                              fit: BoxFit.cover,
                              width: null,
                            )
                          : Container(
                              color: Colors.grey[800],
                              child: const Center(
                                child: Icon(
                                  Icons.broken_image,
                                  color: Colors.white54,
                                ),
                              ),
                            ),
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 6,
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
                        style: TextStyle(
                          fontWeight: isSelected
                              ? FontWeight.bold
                              : FontWeight.normal,
                          color: isSelected
                              ? Theme.of(context).colorScheme.primary
                              : null,
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
    );
  }
}
