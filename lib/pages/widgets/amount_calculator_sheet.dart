import 'package:flutter/material.dart';

/// A small calculator-style keypad for entering money amounts.
///
/// Usage:
/// ```dart
/// final amount = await showAmountCalculatorSheet(context, title: 'Amount');
/// if (amount != null) ...
/// ```
Future<double?> showAmountCalculatorSheet(
  BuildContext context, {
  required String title,
  double? initialValue,
  String? prefixText,
  double? maxAmount,
  bool allowZero = false,
}) {
  return showModalBottomSheet<double>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    backgroundColor: Colors.transparent,
    builder: (sheetCtx) => _AmountCalculatorSheet(
      title: title,
      initialValue: initialValue,
      prefixText: prefixText,
      maxAmount: maxAmount,
      allowZero: allowZero,
    ),
  );
}

class _AmountCalculatorSheet extends StatefulWidget {
  final String title;
  final double? initialValue;
  final String? prefixText;
  final double? maxAmount;
  final bool allowZero;

  const _AmountCalculatorSheet({
    required this.title,
    this.initialValue,
    this.prefixText,
    this.maxAmount,
    required this.allowZero,
  });

  @override
  State<_AmountCalculatorSheet> createState() => _AmountCalculatorSheetState();
}

class _AmountCalculatorSheetState extends State<_AmountCalculatorSheet> {
  // Full expression the user is typing (e.g. "12.5+3*2").
  // We keep it as a string so the display can show the whole equation.
  late String _expr;
  String? _error;

  // What we show in the display (after '=' we show only the computed value).
  bool _showingResult = false;

  @override
  void initState() {
    super.initState();
    final init = widget.initialValue;
    if (init == null) {
      _expr = '0';
    } else {
      // Keep a clean representation (no scientific).
      _expr = init.toStringAsFixed(2);
      _expr = _trimTrailingZeros(_expr);
    }
  }

  String _trimTrailingZeros(String s) {
    if (!s.contains('.')) return s;
    // Remove any trailing zeros after the decimal point, then remove the decimal
    // point if it ends up being the last character.
    //
    // This avoids using replacement backrefs like "$1" which can show up
    // literally if something goes wrong with regex substitution.
    s = s.replaceFirst(RegExp(r'0+$'), '');
    if (s.endsWith('.')) s = s.substring(0, s.length - 1);
    if (s.isEmpty) return '0';
    return s;
  }

  double _parsedNumber(String s) => double.tryParse(s) ?? 0.0;

  static const _ops = <String>{'+', '-', '*', '/'};

  bool _isOp(String c) => _ops.contains(c);

  String _lastChar() => _expr.isEmpty ? '' : _expr[_expr.length - 1];

  bool _endsWithOp() => _expr.isNotEmpty && _isOp(_lastChar());

  bool _currentNumberHasDot() {
    // Look back to the last operator; if there's a dot after it, we already have one.
    final last = _expr.isEmpty ? -1 : _expr.length - 1;
    for (var i = last; i >= 0; i--) {
      final ch = _expr[i];
      if (_isOp(ch)) break;
      if (ch == '.') return true;
    }
    return false;
  }

  int _currentFractionLength() {
    // Count digits after '.' in the current number; if no '.', return 0.
    final last = _expr.isEmpty ? -1 : _expr.length - 1;
    var dotIndex = -1;
    for (var i = last; i >= 0; i--) {
      final ch = _expr[i];
      if (_isOp(ch)) break;
      if (ch == '.') {
        dotIndex = i;
        break;
      }
    }
    if (dotIndex == -1) return 0;
    return _expr.length - dotIndex - 1;
  }

  // Evaluate an expression with + - * /, left-to-right for same precedence,
  // respecting standard precedence: * and / before + and -.
  double? _evalExpr(String expr) {
    var s = expr.replaceAll(' ', '');
    if (s.isEmpty) return 0.0;

    // Trim trailing operators/dots to avoid parse errors.
    while (s.isNotEmpty) {
      final last = s[s.length - 1];
      if (_isOp(last) || last == '.') {
        s = s.substring(0, s.length - 1);
      } else {
        break;
      }
    }
    if (s.isEmpty) return 0.0;

    final nums = <double>[];
    final ops = <String>[];

    var i = 0;
    while (i < s.length) {
      // Parse number.
      var start = i;
      while (i < s.length && !_isOp(s[i])) {
        i++;
      }
      final token = s.substring(start, i);
      final n = double.tryParse(token);
      if (n == null) return null;
      nums.add(n);

      if (i < s.length) {
        ops.add(s[i]);
        i++;
      }
    }

    // First pass: handle * and /.
    var idx = 0;
    while (idx < ops.length) {
      final op = ops[idx];
      if (op == '*' || op == '/') {
        final a = nums[idx];
        final b = nums[idx + 1];
        if (op == '/' && b.abs() < 0.0000001) return null;
        final r = op == '*' ? a * b : a / b;
        nums[idx] = r;
        nums.removeAt(idx + 1);
        ops.removeAt(idx);
      } else {
        idx++;
      }
    }

    // Second pass: handle + and -.
    var res = nums.isEmpty ? 0.0 : nums[0];
    for (var j = 0; j < ops.length; j++) {
      final op = ops[j];
      final b = nums[j + 1];
      if (op == '+') {
        res += b;
      } else if (op == '-') {
        res -= b;
      }
    }
    return res;
  }

  void _setError(String? e) {
    if (_error == e) return;
    setState(() => _error = e);
  }

  void _appendDigit(String d) {
    setState(() {
      _error = null;
      _showingResult = false;

      // Basic max length guard.
      if (_expr.length >= 24) return;

      // If we're at the start with 0, replace it (unless it's "0." or after an operator).
      if (_expr == '0') {
        _expr = d;
        return;
      }
      if (_endsWithOp()) {
        _expr += d;
        return;
      }

      // Decimal precision: 2 digits max for the current number.
      if (_currentFractionLength() >= 2) return;
      _expr += d;
    });
  }

  void _appendDot() {
    setState(() {
      _error = null;
      _showingResult = false;
      if (_expr.length >= 24) return;
      if (_endsWithOp()) {
        _expr += '0.';
        return;
      }
      if (_expr.isEmpty) {
        _expr = '0.';
        return;
      }
      if (_currentNumberHasDot()) return;
      _expr += '.';
    });
  }

  void _backspace() {
    setState(() {
      _error = null;
      _showingResult = false;
      if (_expr.length <= 1) {
        _expr = '0';
        return;
      }
      _expr = _expr.substring(0, _expr.length - 1);
      if (_expr.isEmpty) _expr = '0';
      if (_expr == '-') _expr = '0';
    });
  }

  void _pressOperator(String op) {
    setState(() {
      _error = null;
      _showingResult = false;

      // Replace operator if user taps operators repeatedly.
      if (_endsWithOp()) {
        _expr = _expr.substring(0, _expr.length - 1) + op;
        return;
      }
      _expr += op;
    });
  }

  void _equals() {
    setState(() {
      _error = null;

      final res = _evalExpr(_expr);
      if (res == null) {
        _setError('Invalid equation');
        return;
      }
      _expr = _trimTrailingZeros(res.toStringAsFixed(2));
      _showingResult = true;
    });
  }

  void _clear() {
    setState(() {
      _error = null;
      _expr = '0';
      _showingResult = false;
    });
  }

  void _confirm() {
    // Confirm does NOT need to force '='. We accept the currently shown value.
    // If the user is still typing an equation, evaluate it.
    final amount = _showingResult ? _parsedNumber(_expr) : (_evalExpr(_expr) ?? double.nan);

    if (amount.isNaN) {
      _setError('Invalid equation');
      return;
    }

    if (!widget.allowZero && amount <= 0) {
      _setError('Amount must be > 0');
      return;
    }

    final max = widget.maxAmount;
    if (max != null && amount > max + 0.0000001) {
      _setError('Max ${max.toStringAsFixed(2)}');
      return;
    }

    Navigator.of(context).pop(amount);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return SafeArea(
      child: Padding(
        padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
        child: Container(
          margin: const EdgeInsets.fromLTRB(12, 0, 12, 12),
          decoration: BoxDecoration(
            color: theme.colorScheme.surface,
            borderRadius: BorderRadius.circular(20),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.12),
                blurRadius: 20,
                offset: const Offset(0, 10),
              ),
            ],
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 14, 10, 8),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        widget.title,
                        style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800),
                      ),
                    ),
                    TextButton(
                      onPressed: () => Navigator.of(context).pop(),
                      child: const Text('Cancel'),
                    ),
                  ],
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                  decoration: BoxDecoration(
                    color: theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.55),
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(color: theme.dividerColor.withValues(alpha: 0.4)),
                  ),
                  child: Row(
                    children: [
                      if ((widget.prefixText ?? '').isNotEmpty)
                        Text(
                          widget.prefixText!,
                          style: theme.textTheme.titleMedium?.copyWith(
                            fontWeight: FontWeight.w900,
                            color: theme.colorScheme.onSurfaceVariant,
                          ),
                        ),
                      if ((widget.prefixText ?? '').isNotEmpty) const SizedBox(width: 6),
                      Expanded(
                        child: Text(
                          _showingResult
                              ? _expr
                              : _expr,
                          textAlign: TextAlign.right,
                          style: theme.textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w900),
                        ),
                      ),
                      const SizedBox(width: 8),
                      IconButton(
                        tooltip: 'Backspace',
                        onPressed: _backspace,
                        icon: const Icon(Icons.backspace_outlined),
                      ),
                    ],
                  ),
                ),
              ),
              if (_error != null)
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                  child: Align(
                    alignment: Alignment.centerLeft,
                    child: Text(
                      _error!,
                      style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.error, fontWeight: FontWeight.w700),
                    ),
                  ),
                ),
              Padding(
                padding: const EdgeInsets.fromLTRB(14, 4, 14, 14),
                child: _Keypad(
                  onDigit: _appendDigit,
                  onDot: _appendDot,
                  onClear: _clear,
                  onOperator: _pressOperator,
                  onEquals: _equals,
                  onConfirm: _confirm,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _Keypad extends StatelessWidget {
  final void Function(String) onDigit;
  final VoidCallback onDot;
  final VoidCallback onClear;
  final void Function(String) onOperator;
  final VoidCallback onEquals;
  final VoidCallback onConfirm;

  const _Keypad({
    required this.onDigit,
    required this.onDot,
    required this.onClear,
    required this.onOperator,
    required this.onEquals,
    required this.onConfirm,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    Widget key(
      String label, {
      VoidCallback? onTap,
      bool filled = false,
      bool isFunction = false,
    }) {
      final bg = filled
          ? theme.colorScheme.primary
          : (isFunction
              ? theme.colorScheme.surfaceContainerHighest
              : theme.colorScheme.surface);
      final fg = filled
          ? theme.colorScheme.onPrimary
          : (isFunction
              ? theme.colorScheme.secondary
              : theme.colorScheme.onSurface);

      return SizedBox(
        height: 48,
        child: Material(
          color: bg,
          borderRadius: BorderRadius.circular(12),
          child: InkWell(
            borderRadius: BorderRadius.circular(12),
            onTap: onTap,
            child: Center(
              child: Text(
                label,
                style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w900, color: fg),
              ),
            ),
          ),
        ),
      );
    }

    return LayoutBuilder(
      builder: (ctx, c) {
        final w = c.maxWidth;
        final gap = w < 340 ? 8.0 : 10.0;
        final keyH = w < 340 ? 44.0 : 48.0;

        Widget gridKey(
          String label, {
          VoidCallback? onTap,
          bool filled = false,
          bool isFunction = false,
        }) {
          return SizedBox(
            height: keyH,
            child: key(label, onTap: onTap, filled: filled, isFunction: isFunction),
          );
        }

        final gridItems = <Widget>[
          gridKey('7', onTap: () => onDigit('7')),
          gridKey('8', onTap: () => onDigit('8')),
          gridKey('9', onTap: () => onDigit('9')),
          gridKey('÷', onTap: () => onOperator('/'), isFunction: true),

          gridKey('4', onTap: () => onDigit('4')),
          gridKey('5', onTap: () => onDigit('5')),
          gridKey('6', onTap: () => onDigit('6')),
          gridKey('×', onTap: () => onOperator('*'), isFunction: true),

          gridKey('1', onTap: () => onDigit('1')),
          gridKey('2', onTap: () => onDigit('2')),
          gridKey('3', onTap: () => onDigit('3')),
          gridKey('−', onTap: () => onOperator('-'), isFunction: true),

          gridKey('C', onTap: onClear, isFunction: true),
          gridKey('0', onTap: () => onDigit('0')),
          gridKey('.', onTap: onDot, isFunction: true),
          gridKey('+', onTap: () => onOperator('+'), isFunction: true),
        ];

        // Use a fixed 4-column grid to prevent any Row overflow on narrow widths.
        return Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.35),
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: theme.dividerColor.withValues(alpha: 0.25)),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              GridView.count(
                crossAxisCount: 4,
                mainAxisSpacing: gap,
                crossAxisSpacing: gap,
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                childAspectRatio: (w / 4) / keyH,
                children: gridItems,
              ),
              SizedBox(height: gap),
              Row(
                children: [
                  Expanded(child: SizedBox(height: keyH, child: key('=', onTap: onEquals, isFunction: true))),
                  SizedBox(width: gap),
                  Expanded(child: SizedBox(height: keyH, child: key('Confirm', onTap: onConfirm, filled: true))),
                ],
              ),
            ],
          ),
        );
      },
    );
  }
}








