import 'dart:ffi';
import 'dart:io';
import 'dart:math';

import 'package:ffi/ffi.dart';
import 'package:win32/win32.dart';

// Abstract base class for key interaction steps.
abstract class KeyStep {
  void execute();
}

// Press a specific key.
class Press implements KeyStep {
  final String key;

  Press(this.key);

  @override
  void execute() {
    final keyCode = _getVirtualKeyCode(key);
    _sendKeyEvent(keyCode, isKeyUp: false);
    _sendKeyEvent(keyCode, isKeyUp: true);
  }

  int _getVirtualKeyCode(String key) {
    // Convert single character to its virtual key code.
    return key.toUpperCase().codeUnitAt(0);
  }

  void _sendKeyEvent(int keyCode, {required bool isKeyUp}) {
    final input = calloc<INPUT>();
    try {
      input.ref.type = INPUT_TYPE.INPUT_KEYBOARD;
      input.ref.ki.wVk = keyCode;
      input.ref.ki.dwFlags = isKeyUp ? KEYBD_EVENT_FLAGS.KEYEVENTF_KEYUP : 0;

      SendInput(1, input, sizeOf<INPUT>());
    } finally {
      free(input);
    }
  }
}

// Wait for a specified duration with optional random variation.
class Wait implements KeyStep {
  final int baseMs;
  final int varianceMs;

  Wait(this.baseMs, this.varianceMs);

  @override
  void execute() {
    final random = Random();
    final variance = random.nextInt(2 * varianceMs + 1) - varianceMs;
    final totalWaitTime = baseMs + variance;
    sleep(Duration(milliseconds: totalWaitTime));
  }
}
