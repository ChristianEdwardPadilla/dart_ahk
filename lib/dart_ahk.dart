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

// Global variables for state management
int keyHook = 0;
String targetProcessName = '';
Map<String, List<KeyStep>> keyMapping = {};

bool isTargetWindowActive() {
  final hwnd = GetForegroundWindow();
  final pidPtr = calloc<DWORD>();

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
      final processName = getProcessNameFromHandle(processHandle);
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

String getProcessNameFromHandle(int processHandle) {
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

void executeKeySequence(List<KeyStep> sequence) {
  for (final step in sequence) {
    step.execute();
  }
}

int lowLevelKeyboardHookProc(int code, int wParam, int lParam) {
  if (code == HC_ACTION && isTargetWindowActive()) {
    final kbs = Pointer<KBDLLHOOKSTRUCT>.fromAddress(lParam);

    // Check if this is an injected input (from our own SendInput calls)
    if ((kbs.ref.flags & 0x00000010) == 0) {
      // LLKHF_INJECTED
      final keyChar = String.fromCharCode(kbs.ref.vkCode);

      // Check if this key is in our mapping
      if (keyMapping.containsKey(keyChar)) {
        if (wParam == WM_KEYDOWN) {
          print('Intercepted key press: $keyChar');
          executeKeySequence(keyMapping[keyChar]!);
        }
        return -1; // Prevent the original key from being processed
      }
    }

    // Small sleep to prevent high CPU usage
    sleep(const Duration(milliseconds: 10));
  }

  return CallNextHookEx(keyHook, code, wParam, lParam);
}

void main() {
  // Initialize key mappings
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

  keyMapping = {
    "2": outputA,
    "5": outputB,
  };

  targetProcessName = 'chrome';

  // Create callable function for the hook
  final lpfn = NativeCallable<HOOKPROC>.isolateLocal(
    lowLevelKeyboardHookProc,
    exceptionalReturn: 0,
  );

  // Install the hook
  keyHook = SetWindowsHookEx(
    WINDOWS_HOOK_ID.WH_KEYBOARD_LL,
    lpfn.nativeFunction,
    NULL,
    0,
  );

  if (keyHook == 0) {
    print('Failed to install keyboard hook');
    lpfn.close();
    return;
  }

  print('Keyboard hook installed. Listening for key interception...');

  // Message loop
  final msg = calloc<MSG>();
  try {
    while (GetMessage(msg, NULL, 0, 0) != 0) {
      TranslateMessage(msg);
      DispatchMessage(msg);
    }
  } finally {
    free(msg);
    lpfn.close();
    if (keyHook != 0) {
      UnhookWindowsHookEx(keyHook);
    }
  }
}
