import 'dart:ffi';
import 'dart:io';
import 'dart:math';

import 'package:ffi/ffi.dart';
import 'package:win32/win32.dart';

// Abstract base class for key interaction steps
abstract class KeyStep {
  void execute();
}

// Press a specific key
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
    // Convert single character to its virtual key code
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

// Wait for a specified duration with optional random variation
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

class KeyInterceptor {
  final String targetProcessName;
  final Map<String, List<KeyStep>> inputMapping;

  KeyInterceptor({
    required this.targetProcessName,
    required this.inputMapping,
  });

  bool _isTargetWindowActive() {
    final hwnd = GetForegroundWindow();
    final pidPtr = calloc<Uint32>();

    try {
      GetWindowThreadProcessId(hwnd, pidPtr);
      final pid = pidPtr.value;

      final processHandle = OpenProcess(
        PROCESS_ACCESS_RIGHTS.PROCESS_QUERY_INFORMATION |
            PROCESS_ACCESS_RIGHTS.PROCESS_VM_READ,
        FALSE,
        pid,
      );

      if (processHandle == 0) return false;

      try {
        final processName = _getProcessNameFromHandle(processHandle);
        return processName
            .toLowerCase()
            .contains(targetProcessName.toLowerCase());
      } finally {
        CloseHandle(processHandle);
      }
    } finally {
      free(pidPtr);
    }
  }

  String _getProcessNameFromHandle(int processHandle) {
    final processNameBuffer = wsalloc(MAX_PATH);
    try {
      final processNameLength = GetProcessImageFileName(
        processHandle,
        processNameBuffer,
        MAX_PATH,
      );

      if (processNameLength > 0) {
        final processName = processNameBuffer.toDartString();
        return processName.split(r'\').last;
      }
      return '';
    } finally {
      free(processNameBuffer);
    }
  }

  void _executeKeySequence(List<KeyStep> sequence) {
    for (final step in sequence) {
      step.execute();
    }
  }

  void startListening() {
    print('Listening for key interception...');
    while (true) {
      if (_isTargetWindowActive()) {
        // Check each mapped input key
        for (final entry in inputMapping.entries) {
          final keyChar = entry.key;
          final sequence = entry.value;

          // Convert key string to virtual key code
          final keyCode = keyChar.toUpperCase().codeUnitAt(0);

          // Check if the key is newly pressed
          final keyState = GetAsyncKeyState(keyCode);
          if ((keyState & 0x8000) != 0) {
            print('Intercepted key press: $keyChar');
            _executeKeySequence(sequence);

            // Brief pause to prevent multiple triggers
            sleep(const Duration(milliseconds: 200));
          }
        }
      }

      // Small sleep to prevent high CPU usage
      sleep(const Duration(milliseconds: 10));
    }
  }
}

void main() {
  final outputA = [
    Press("1"),
    Wait(50, 20),
    Press("2"),
    Wait(45, 10),
    Press("3"),
    Wait(55, 15),
  ];

  final outputB = [
    Press("Q"),
    Wait(50, 20),
    Press("W"),
    Wait(45, 10),
  ];

  final inputMap = {
    "2": outputA,
    "5": outputB,
  };

  final interceptor = KeyInterceptor(
    targetProcessName: 'chrome',
    inputMapping: inputMap,
  );

  try {
    interceptor.startListening();
  } catch (e) {
    print('Error: $e');
  }
}
