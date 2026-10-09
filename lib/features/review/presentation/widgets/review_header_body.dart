import 'dart:math' as math;

import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';

/// A [header] pinned to the top and a [body] centred in the space below it.
/// When the card is no taller than its content nothing is centred; when an
/// equal-height row stretches it, the body sits in the middle of the free
/// space instead of leaving an empty band at the bottom.
class ReviewHeaderBody extends MultiChildRenderObjectWidget {
  ReviewHeaderBody({super.key, required Widget header, required Widget body})
    : super(children: [header, body]);

  @override
  RenderObject createRenderObject(BuildContext context) => _RenderHeaderBody();
}

class _HeaderBodyParentData extends ContainerBoxParentData<RenderBox> {}

class _RenderHeaderBody extends RenderBox
    with
        ContainerRenderObjectMixin<RenderBox, _HeaderBodyParentData>,
        RenderBoxContainerDefaultsMixin<RenderBox, _HeaderBodyParentData> {
  @override
  void setupParentData(RenderBox child) {
    if (child.parentData is! _HeaderBodyParentData) {
      child.parentData = _HeaderBodyParentData();
    }
  }

  @override
  void performLayout() {
    final header = firstChild!;
    final body = childAfter(header)!;
    final tight = BoxConstraints(
      minWidth: constraints.maxWidth,
      maxWidth: constraints.maxWidth,
    );
    header.layout(tight, parentUsesSize: true);
    body.layout(tight, parentUsesSize: true);
    final content = header.size.height + body.size.height;
    final height = math.max(content, constraints.minHeight);
    final free = height - content;
    (header.parentData! as _HeaderBodyParentData).offset = Offset.zero;
    (body.parentData! as _HeaderBodyParentData).offset = Offset(
      0,
      header.size.height + free / 2,
    );
    size = constraints.constrain(Size(constraints.maxWidth, height));
  }

  @override
  Size computeDryLayout(BoxConstraints constraints) {
    final header = firstChild!;
    final body = childAfter(header)!;
    final tight = BoxConstraints(
      minWidth: constraints.maxWidth,
      maxWidth: constraints.maxWidth,
    );
    final content =
        header.getDryLayout(tight).height + body.getDryLayout(tight).height;
    return constraints.constrain(
      Size(constraints.maxWidth, math.max(content, constraints.minHeight)),
    );
  }

  @override
  bool hitTestChildren(BoxHitTestResult result, {required Offset position}) =>
      defaultHitTestChildren(result, position: position);

  @override
  void paint(PaintingContext context, Offset offset) =>
      defaultPaint(context, offset);
}
