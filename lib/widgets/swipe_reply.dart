import 'package:flutter/material.dart';

class SwipeReply extends StatefulWidget {
  const SwipeReply({
    super.key,
    required this.isMine,
    required this.child,
    this.onReply,
  });

  final bool isMine;
  final Widget child;
  final VoidCallback? onReply;

  @override
  State<SwipeReply> createState() => _SwipeReplyState();
}

class _SwipeReplyState extends State<SwipeReply> {
  double _offset = 0;

  void _updateDrag(DragUpdateDetails details) {
    final next = _offset + details.delta.dx;
    final allowed = widget.isMine ? next <= 0 : next >= 0;
    if (!allowed) return;
    setState(() => _offset = next.clamp(-120.0, 120.0));
  }

  void _finishDrag() {
    if (_offset.abs() >= 60) widget.onReply?.call();
    setState(() => _offset = 0);
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onLongPress: widget.onReply,
      onHorizontalDragUpdate: widget.onReply == null ? null : _updateDrag,
      onHorizontalDragEnd: widget.onReply == null ? null : (_) => _finishDrag(),
      child: TweenAnimationBuilder<double>(
        tween: Tween(begin: 0, end: _offset),
        duration: const Duration(milliseconds: 120),
        curve: Curves.easeOut,
        builder: (context, offset, child) => Transform.translate(
          offset: Offset(offset, 0),
          child: child,
        ),
        child: widget.child,
      ),
    );
  }
}
