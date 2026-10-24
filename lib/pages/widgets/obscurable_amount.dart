import 'package:flutter/material.dart';

/// Same mask everywhere so a hidden balance does not reveal its length.
const String kHiddenAmount = '••••';

/// Shows [amount], or a mask that keeps the real text's width.
class ObscurableAmount extends StatelessWidget {
  final String amount;
  final bool visible;
  final TextStyle? style;
  final TextAlign textAlign;
  final int? maxLines;
  final TextOverflow overflow;

  const ObscurableAmount({
    super.key,
    required this.amount,
    required this.visible,
    this.style,
    this.textAlign = TextAlign.start,
    this.maxLines = 1,
    this.overflow = TextOverflow.ellipsis,
  });

  @override
  Widget build(BuildContext context) {
    final shown = Text(
      visible ? amount : kHiddenAmount,
      style: style,
      textAlign: textAlign,
      maxLines: maxLines,
      overflow: overflow,
    );
    if (visible) return shown;

    return Stack(
      alignment: _alignmentFor(textAlign),
      children: [
        ExcludeSemantics(
          child: Opacity(
            opacity: 0,
            child: Text(
              amount,
              style: style,
              textAlign: textAlign,
              maxLines: maxLines,
              overflow: overflow,
            ),
          ),
        ),
        shown,
      ],
    );
  }

  Alignment _alignmentFor(TextAlign align) {
    switch (align) {
      case TextAlign.center:
        return Alignment.center;
      case TextAlign.end:
      case TextAlign.right:
        return Alignment.centerRight;
      default:
        return Alignment.centerLeft;
    }
  }
}
