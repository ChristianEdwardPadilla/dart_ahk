import 'dart:ffi';
import 'dart:io';

import 'package:ffi/ffi.dart';
import 'package:win32/win32.dart';

class KeyInterceptor {
  final String targetProcessName;
  final int originalKeyCode;
  final List<int> simulatedKeyCodes;

  KeyInterceptor({
    required this.targetProcessName,
    required this.originalKeyCode,
    required this.simulatedKeyCodes,
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

  void _simulateKeyPress(List<int> keyCodes) {
    for (final keyCode in keyCodes) {
      // Key down events
      _sendKeyEvent(keyCode, isKeyUp: false);
    }

    // Brief pause
    sleep(const Duration(milliseconds: 10));

    for (final keyCode in keyCodes) {
      // Key up events
      _sendKeyEvent(keyCode, isKeyUp: true);
    }
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

  void startListening() {
    print('Listening for key interception...');
    while (true) {
      // Check for key state
      if (_isTargetWindowActive()) {
        final keyState = GetAsyncKeyState(originalKeyCode);

        // Check if the key is newly pressed (most significant bit is 1)
        if ((keyState & 0x8000) != 0) {
          print('Intercepted key press');
          _simulateKeyPress(simulatedKeyCodes);

          // Brief pause to prevent multiple triggers
          sleep(const Duration(milliseconds: 200));
        }
      }

      // Small sleep to prevent high CPU usage
      sleep(const Duration(milliseconds: 10));
    }
  }
}

void main() {
  final interceptor = KeyInterceptor(
    targetProcessName: 'PathOfExile', // Target process name
    originalKeyCode: 0x32, // Virtual key code for '2'
    simulatedKeyCodes: [
      0x31, // '1' key
      0x32, // '2' key
      0x33, // '3' key
    ],
  );

  try {
    interceptor.startListening();
  } catch (e) {
    print('Error: $e');
  }
}
