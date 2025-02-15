import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';

import '../../pdfrx.dart';

/// A widget that displays selectable text on a page.
class PdfPageTextOverlay extends StatefulWidget {
  const PdfPageTextOverlay({
    required this.registrar,
    required this.page,
    required this.pageRect,
    super.key,
  });

  final SelectionRegistrar? registrar;
  final PdfPage page;
  final Rect pageRect;

  @override
  State<PdfPageTextOverlay> createState() => _PdfPageTextOverlayState();
}

class _PdfPageTextOverlayState extends State<PdfPageTextOverlay> {
  PdfPageText? pageText;

  @override
  void initState() {
    super.initState();
    _initText();
  }

  @override
  void didUpdateWidget(PdfPageTextOverlay oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.page != oldWidget.page) {
      _initText();
    }
  }

  Future<void> _initText() async {
    pageText = await widget.page.loadText();
    if (mounted) {
      setState(() {});
    }
  }

  @override
  Widget build(BuildContext context) {
    if (pageText == null) return const SizedBox();
    return Positioned(
      left: widget.pageRect.left,
      top: widget.pageRect.top,
      width: widget.pageRect.width,
      height: widget.pageRect.height,
      child: MouseRegion(
        hitTestBehavior: HitTestBehavior.translucent,
        opaque: true,
        cursor: SystemMouseCursors.text,
        child: _PdfTextWidget(
          widget.registrar,
          this,
        ),
      ),
    );
  }
}

/// The code is based on the code on [Making a widget selectable](https://api.flutter.dev/flutter/widgets/SelectableRegion-class.html#widgets).SelectableRegion.2]
class _PdfTextWidget extends LeafRenderObjectWidget {
  const _PdfTextWidget(
    this.registrar,
    this.state,
  );

  final SelectionRegistrar? registrar;

  final _PdfPageTextOverlayState state;

  @override
  RenderObject createRenderObject(BuildContext context) => _PdfTextRenderBox(
      DefaultSelectionStyle.of(context).selectionColor!, this);

  @override
  void updateRenderObject(
      BuildContext context, _PdfTextRenderBox renderObject) {
    renderObject
      ..selectionColor = DefaultSelectionStyle.of(context).selectionColor!
      ..registrar = registrar;
  }
}

/// The code is based on the code on [Making a widget selectable](https://api.flutter.dev/flutter/widgets/SelectableRegion-class.html#widgets).SelectableRegion.2]
class _PdfTextRenderBox extends RenderBox with Selectable, SelectionRegistrant {
  _PdfTextRenderBox(
    this._selectionColor,
    this.widget,
  ) : _geometry = ValueNotifier<SelectionGeometry>(_noSelection) {
    registrar = widget.registrar;
    _geometry.addListener(markNeedsPaint);
  }

  final _PdfTextWidget widget;

  static const SelectionGeometry _noSelection =
      SelectionGeometry(status: SelectionStatus.none, hasContent: true);

  final ValueNotifier<SelectionGeometry> _geometry;

  Color _selectionColor;
  Color get selectionColor => _selectionColor;
  set selectionColor(Color value) {
    if (_selectionColor == value) return;
    _selectionColor = value;
    markNeedsPaint();
  }

  @override
  void dispose() {
    _geometry.dispose();
    super.dispose();
  }

  Rect get _pageRect => widget.state.widget.pageRect;
  PdfPage get _page => widget.state.widget.page;
  List<PdfPageTextFragment> get _fragments => widget.state.pageText!.fragments;

  @override
  bool get sizedByParent => true;
  @override
  double computeMinIntrinsicWidth(double height) => _pageRect.size.width;
  @override
  double computeMaxIntrinsicWidth(double height) => _pageRect.size.width;
  @override
  double computeMinIntrinsicHeight(double width) => _pageRect.size.height;
  @override
  double computeMaxIntrinsicHeight(double width) => _pageRect.size.height;
  @override
  Size computeDryLayout(BoxConstraints constraints) =>
      constraints.constrain(_pageRect.size);

  @override
  void addListener(VoidCallback listener) => _geometry.addListener(listener);

  @override
  void removeListener(VoidCallback listener) =>
      _geometry.removeListener(listener);

  @override
  SelectionGeometry get value => _geometry.value;

  Rect _getSelectionHighlightRect() => Offset.zero & size;

  Offset? _start;
  Offset? _end;
  String? _selectedText;
  Rect? _selectedRect;
  Size? _sizeOnSelection;

  void _updateGeometry() {
    if (_start == null || _end == null) {
      _geometry.value = _noSelection;
      return;
    }

    final renderObjectRect = Rect.fromLTWH(0, 0, size.width, size.height);
    var selectionRect = Rect.fromPoints(_start!, _end!);
    if (renderObjectRect.intersect(selectionRect).isEmpty) {
      _geometry.value = _noSelection;
      return;
    }
    selectionRect =
        !selectionRect.isEmpty ? selectionRect : _getSelectionHighlightRect();

    final selectionRects = <Rect>[];
    final sb = StringBuffer();
    _selectedRect = null;
    final scale = size.height / _page.height;

    int searchLineEnd(int start) {
      final lastIndex = _fragments.length - 1;
      var last = _fragments[start];
      for (int i = start; i < lastIndex; i++) {
        final next = _fragments[i + 1];
        if (last.bounds.bottom != next.bounds.bottom) {
          return i + 1;
        }
        last = next;
      }
      return _fragments.length;
    }

    Iterable<({Rect rect, String text})> enumerateCharRects(
        int start, int end) sync* {
      for (int i = start; i < end; i++) {
        final fragment = _fragments[i];
        if (fragment.charRects == null) {
          yield (
            rect: fragment.bounds.toRect(
              height: _page.height,
              scale: scale,
            ),
            text: fragment.text
          );
        } else {
          for (int j = 0; j < fragment.charRects!.length; j++) {
            yield (
              rect: fragment.charRects![j].toRect(
                height: _page.height,
                scale: scale,
              ),
              text: fragment.text.substring(j, j + 1)
            );
          }
        }
      }
    }

    ({Rect? rect, String text}) selectChars(
        int start, int end, Rect lineSelectRect) {
      Rect? rect;
      final sb = StringBuffer();
      for (final r in enumerateCharRects(start, end)) {
        if (!r.rect.intersect(lineSelectRect).isEmpty ||
            r.rect.bottom < lineSelectRect.bottom) {
          sb.write(r.text);
          if (rect == null) {
            rect = r.rect;
          } else {
            rect = rect.expandToInclude(r.rect);
          }
        }
      }
      return (rect: rect, text: sb.toString());
    }

    int? lastLineEnd;
    Rect? lastLineStartRect;
    for (int i = 0; i < _fragments.length;) {
      final bounds =
          _fragments[i].bounds.toRect(height: _page.height, scale: scale);
      if (lastLineEnd == null && selectionRect.intersect(bounds).isEmpty) {
        i++;
      } else {
        final lineEnd = searchLineEnd(i);
        final chars = selectChars(
            lastLineEnd ?? i,
            lineEnd,
            lastLineStartRect != null
                ? lastLineStartRect.expandToInclude(selectionRect)
                : selectionRect);
        lastLineStartRect = bounds;
        lastLineEnd = i = lineEnd;
        if (chars.rect == null) continue;
        sb.write(chars.text);
        selectionRects.add(chars.rect!);
      }
    }

    if (selectionRects.isEmpty) {
      _geometry.value = _noSelection;
      return;
    }

    final selectedBounds =
        selectionRects.reduce((a, b) => a.expandToInclude(b));
    _selectedRect = Rect.fromLTRB(
      _start?.dx ?? selectedBounds.left,
      selectedBounds.top,
      _end?.dx ?? selectedBounds.right,
      selectedBounds.bottom,
    );
    _selectedText = sb.toString();
    final firstSelectionPoint = SelectionPoint(
      localPosition: _selectedRect!.bottomLeft,
      lineHeight: _selectedRect!.height,
      handleType: TextSelectionHandleType.left,
    );
    final secondSelectionPoint = SelectionPoint(
      localPosition: _selectedRect!.bottomRight,
      lineHeight: _selectedRect!.height,
      handleType: TextSelectionHandleType.right,
    );
    final bool isReversed;
    if (_start!.dy > _end!.dy) {
      isReversed = true;
    } else if (_start!.dy < _end!.dy) {
      isReversed = false;
    } else {
      isReversed = _start!.dx > _end!.dx;
    }

    _sizeOnSelection = size;
    _geometry.value = SelectionGeometry(
      status: _selectedText!.isNotEmpty
          ? SelectionStatus.uncollapsed
          : SelectionStatus.collapsed,
      hasContent: true,
      startSelectionPoint:
          isReversed ? secondSelectionPoint : firstSelectionPoint,
      endSelectionPoint:
          isReversed ? firstSelectionPoint : secondSelectionPoint,
      selectionRects: selectionRects,
    );
  }

  void _selectFragment(Offset point) {
    for (final fragment in _fragments) {
      final bounds = fragment.bounds
          .toRect(height: _page.height, scale: size.height / _page.height);
      if (bounds.contains(point)) {
        _start = bounds.topLeft;
        _end = bounds.bottomRight;
        _selectedRect = bounds;
        _selectedText = fragment.text;
        _sizeOnSelection = size;
        _geometry.value = SelectionGeometry(
          status: _selectedText!.isNotEmpty
              ? SelectionStatus.uncollapsed
              : SelectionStatus.collapsed,
          hasContent: true,
          startSelectionPoint: SelectionPoint(
            localPosition: _selectedRect!.bottomLeft,
            lineHeight: _selectedRect!.height,
            handleType: TextSelectionHandleType.left,
          ),
          endSelectionPoint: SelectionPoint(
            localPosition: _selectedRect!.bottomRight,
            lineHeight: _selectedRect!.height,
            handleType: TextSelectionHandleType.right,
          ),
          selectionRects: [bounds],
        );
        return;
      }
    }
    _geometry.value = _noSelection;
  }

  @override
  SelectionResult dispatchSelectionEvent(SelectionEvent event) {
    var result = SelectionResult.none;
    switch (event.type) {
      case SelectionEventType.startEdgeUpdate:
      case SelectionEventType.endEdgeUpdate:
        final renderObjectRect = Rect.fromLTWH(0, 0, size.width, size.height);
        final point =
            globalToLocal((event as SelectionEdgeUpdateEvent).globalPosition);
        final adjustedPoint =
            SelectionUtils.adjustDragOffset(renderObjectRect, point);
        if (event.type == SelectionEventType.startEdgeUpdate) {
          _start = adjustedPoint;
        } else {
          _end = adjustedPoint;
        }
        result = SelectionUtils.getResultBasedOnRect(renderObjectRect, point);
        break;
      case SelectionEventType.clear:
        _start = _end = null;
      case SelectionEventType.selectAll:
        _start = Offset.zero;
        _end = Offset.infinite;
      case SelectionEventType.selectWord:
        _selectFragment(
          globalToLocal(
            (event as SelectWordSelectionEvent).globalPosition,
          ),
        );
      case SelectionEventType.granularlyExtendSelection:
        result = SelectionResult.end;
        final extendSelectionEvent = event as GranularlyExtendSelectionEvent;
        // Initialize the offset it there is no ongoing selection.
        if (_start == null || _end == null) {
          if (extendSelectionEvent.forward) {
            _start = _end = Offset.zero;
          } else {
            _start = _end = Offset.infinite;
          }
        }
        // Move the corresponding selection edge.
        final newOffset =
            extendSelectionEvent.forward ? Offset.infinite : Offset.zero;
        if (extendSelectionEvent.isEnd) {
          if (newOffset == _end) {
            result = extendSelectionEvent.forward
                ? SelectionResult.next
                : SelectionResult.previous;
          }
          _end = newOffset;
        } else {
          if (newOffset == _start) {
            result = extendSelectionEvent.forward
                ? SelectionResult.next
                : SelectionResult.previous;
          }
          _start = newOffset;
        }
      case SelectionEventType.directionallyExtendSelection:
        result = SelectionResult.end;
        final extendSelectionEvent = event as DirectionallyExtendSelectionEvent;
        // Convert to local coordinates.
        final horizontalBaseLine = globalToLocal(Offset(event.dx, 0)).dx;
        final Offset newOffset;
        final bool forward;
        switch (extendSelectionEvent.direction) {
          case SelectionExtendDirection.backward:
          case SelectionExtendDirection.previousLine:
            forward = false;
            // Initialize the offset it there is no ongoing selection.
            if (_start == null || _end == null) {
              _start = _end = Offset.infinite;
            }
            // Move the corresponding selection edge.
            if (extendSelectionEvent.direction ==
                    SelectionExtendDirection.previousLine ||
                horizontalBaseLine < 0) {
              newOffset = Offset.zero;
            } else {
              newOffset = Offset.infinite;
            }
          case SelectionExtendDirection.nextLine:
          case SelectionExtendDirection.forward:
            forward = true;
            // Initialize the offset it there is no ongoing selection.
            if (_start == null || _end == null) {
              _start = _end = Offset.zero;
            }
            // Move the corresponding selection edge.
            if (extendSelectionEvent.direction ==
                    SelectionExtendDirection.nextLine ||
                horizontalBaseLine > size.width) {
              newOffset = Offset.infinite;
            } else {
              newOffset = Offset.zero;
            }
        }
        if (extendSelectionEvent.isEnd) {
          if (newOffset == _end) {
            result = forward ? SelectionResult.next : SelectionResult.previous;
          }
          _end = newOffset;
        } else {
          if (newOffset == _start) {
            result = forward ? SelectionResult.next : SelectionResult.previous;
          }
          _start = newOffset;
        }
    }
    _updateGeometry();
    return result;
  }

  @override
  SelectedContent? getSelectedContent() =>
      value.hasSelection && _selectedText != null
          ? SelectedContent(plainText: _selectedText!)
          : null;

  LayerLink? _startHandle;
  LayerLink? _endHandle;

  @override
  void pushHandleLayers(LayerLink? startHandle, LayerLink? endHandle) {
    if (_startHandle == startHandle && _endHandle == endHandle) {
      return;
    }
    _startHandle = startHandle;
    _endHandle = endHandle;
    // FIXME: pushHandleLayers sometimes called after dispose...
    if (debugDisposed != true) {
      markNeedsPaint();
    }
  }

  @override
  void paint(PaintingContext context, Offset offset) {
    super.paint(context, offset);

    if (!_geometry.value.hasSelection) {
      return;
    }

    if (_start == null || _end == null || _selectedRect == null) {
      return;
    }

    final scale = size.width / _sizeOnSelection!.width;
    for (final rect in _geometry.value.selectionRects) {
      context.canvas.drawRect(
        (rect * scale).shift(offset),
        Paint()
          ..style = PaintingStyle.fill
          ..color = _selectionColor,
      );
    }

    if (_startHandle != null) {
      context.pushLayer(
        LeaderLayer(
          link: _startHandle!,
          offset: offset + (value.startSelectionPoint!.localPosition * scale),
        )..applyTransform(null, Matrix4.diagonal3Values(scale, scale, 1.0)),
        (context, offset) {},
        Offset.zero,
      );
    }
    if (_endHandle != null) {
      context.pushLayer(
        LeaderLayer(
          link: _endHandle!,
          offset: offset + (value.endSelectionPoint!.localPosition * scale),
        )..applyTransform(null, Matrix4.diagonal3Values(scale, scale, 1.0)),
        (context, offset) {},
        Offset.zero,
      );
    }

    if (size != _sizeOnSelection) {
      Future.microtask(
        () {
          final sp = _geometry.value.startSelectionPoint;
          final ep = _geometry.value.endSelectionPoint;
          if (sp == null || ep == null) return;
          _sizeOnSelection = size;
          _selectedRect = _selectedRect! * scale;
          _geometry.value = _geometry.value.copyWith(
            startSelectionPoint: SelectionPoint(
                handleType: sp.handleType,
                lineHeight: sp.lineHeight * scale,
                localPosition: sp.localPosition * scale),
            endSelectionPoint: SelectionPoint(
                handleType: ep.handleType,
                lineHeight: ep.lineHeight * scale,
                localPosition: ep.localPosition * scale),
            selectionRects:
                _geometry.value.selectionRects.map((r) => r * scale).toList(),
          );
          markNeedsPaint();
        },
      );
      return;
    }
  }
}
