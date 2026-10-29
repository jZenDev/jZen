import 'dart:async';
import 'package:flutter/material.dart';

/// Pauses a message's countdown while it is being used.
class ZenMessageTimer extends StatefulWidget {
  const ZenMessageTimer({
    required this.duration,
    required this.onExpire,
    required this.child,
    this.parentNode,
    super.key,
  });
  final Duration? duration;
  final VoidCallback onExpire;
  final Widget child;
  final FocusNode? parentNode;

  @override
  State<ZenMessageTimer> createState() => _ZenMessageTimerState();
}

class _ZenMessageTimerState extends State<ZenMessageTimer> {
  Timer? _timer;
  final FocusNode _focusNode = FocusNode();
  FocusNode? _parentNode;
  late Duration? _remaining = widget.duration;
  final Stopwatch _elapsed = Stopwatch();
  bool _hover = false;
  bool _focus = false;
  final Set<int> _pointers = <int>{};

  @override
  void initState() {
    super.initState();
    _parentNode = widget.parentNode;
    if (_parentNode != null) FocusManager.instance.addListener(_updateFocusParent);
    _resume();
  }

  void _updateFocusParent() {
    final FocusNode? focused = FocusManager.instance.primaryFocus;
    if (focused == null || focused == _focusNode || focused.ancestors.contains(_focusNode)) return;
    final FocusScopeNode? scope = focused is FocusScopeNode ? focused : focused.enclosingScope;
    if (scope != null && scope != _parentNode && mounted) {
      setState(() => _parentNode = scope);
    }
  }

  void _pause() {
    if (_timer == null) return;
    _timer!.cancel();
    _timer = null;
    _elapsed.stop();
    _remaining = _remaining! - _elapsed.elapsed;
    _elapsed.reset();
  }

  void _resume() {
    if (_remaining == null || _hover || _focus || _pointers.isNotEmpty || _timer != null) return;
    _elapsed.start();
    _timer = Timer(_remaining!, widget.onExpire);
  }

  @override
  void dispose() {
    _timer?.cancel();
    if (widget.parentNode != null) FocusManager.instance.removeListener(_updateFocusParent);
    _focusNode.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => MouseRegion(
    onEnter: (_) {
      _hover = true;
      _pause();
    },
    onExit: (_) {
      _hover = false;
      _resume();
    },
    child: Listener(
      onPointerDown: (event) {
        _pointers.add(event.pointer);
        _pause();
      },
      onPointerUp: (event) {
        _pointers.remove(event.pointer);
        _resume();
      },
      onPointerCancel: (event) {
        _pointers.remove(event.pointer);
        _resume();
      },
      child: Focus(
        canRequestFocus: false,
        focusNode: _focusNode,
        parentNode: _parentNode,
        onFocusChange: (focused) {
          _focus = focused;
          if (focused) {
            _pause();
          } else {
            _resume();
          }
        },
        child: widget.child,
      ),
    ),
  );
}
