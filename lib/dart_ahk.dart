import 'dart:ffi';

import 'package:ffi/ffi.dart';
import 'package:win32/win32.dart';

import 'instructions.dart';

// Global variables.
String targetProcessName = 'chrome';
Map<String, List<KeyStep>> keyMapping = {
  "2": [
    Press("1"),
    Wait(50, 20),
    Press("2"),
    Wait(45, 10),
    Press("3"),
    Wait(55, 15),
  ],
  "5": [
    Press("Q"),
    Wait(50, 20),
    Press("W"),
    Wait(45, 10),
  ],
};
int keyHook = 0;

void main() {
  // Create callable function for the hook.
  final lpfn = NativeCallable<HOOKPROC>.isolateLocal(
    lowLevelKeyboardHookProc,
    exceptionalReturn: 0,
  );

  // Install the hook.
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

  // Windows message loop.
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

    // Check if this is an injected input (from our own SendInput calls).
    if ((kbs.ref.flags & 0x00000010) == 0) {
      // LLKHF_INJECTED
      final keyChar = String.fromCharCode(kbs.ref.vkCode);

      // Only process keys in the global map.
      if (keyMapping.containsKey(keyChar)) {
        // Only process WM_KEYDOWN events.
        if (wParam == WM_KEYDOWN) {
          print('Intercepted key press: $keyChar');
          executeKeySequence(keyMapping[keyChar]!);
        }
        return -1; // Prevent the original key from being processed.
      }
    }
  }
  return CallNextHookEx(keyHook, code, wParam, lParam);
}
