import 'package:flutter/material.dart';

/// A ListView that loops seamlessly: scrolling past the last item wraps
/// back around to the first, and scrolling back up wraps to the last —
/// matching the circular seating table in Blood on the Clocktower. Every
/// item in [itemCount] is still shown; nothing is hidden, limited, or
/// paginated — this only changes what happens when you scroll past either
/// end of the list, however many players there are.
///
/// Needs a fixed [itemExtent] (every row the same height) so the starting
/// scroll position can be calculated precisely — this matches the simple,
/// uniform rows already used in this app's player lists.
class CircularListView extends StatefulWidget {
  final int itemCount;
  final double itemExtent;
  final Widget Function(BuildContext context, int index) itemBuilder;

  const CircularListView({
    super.key,
    required this.itemCount,
    required this.itemExtent,
    required this.itemBuilder,
  });

  @override
  State<CircularListView> createState() => _CircularListViewState();
}

class _CircularListViewState extends State<CircularListView> {
  late final ScrollController _controller;

  // How the loop works: ListView.builder is handed no itemCount at all,
  // which Flutter treats as an endless list, and every real index is
  // reduced with `% widget.itemCount` down to an actual player. That
  // handles "scroll down forever" for free. "Scroll up forever" needs a
  // starting position far from index 0 (which IS a hard wall — indexes
  // can't go negative), so we start several thousand loops in. At normal
  // scroll speeds that's far more backward scrolling than anyone will ever
  // do in a real game — the wall is never actually felt.
  static const int _loopsOfSlack = 5000;

  @override
  void initState() {
    super.initState();
    final startIndex = _loopsOfSlack * widget.itemCount;
    _controller = ScrollController(
      initialScrollOffset: startIndex * widget.itemExtent,
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (widget.itemCount == 0) {
      return const SizedBox.shrink();
    }
    return ListView.builder(
      controller: _controller,
      itemExtent: widget.itemExtent,
      itemBuilder: (context, index) =>
          widget.itemBuilder(context, index % widget.itemCount),
    );
  }
}
