class EscapeEmitter {
  const EscapeEmitter();

  String primaryDeviceAttributes() {
    // Report as VT220 (62) with color (22) and other standard capabilities.
    // 1 = 132-column, 2 = printer port, 6 = selective erase, 22 = ANSI color.
    return '\x1b[?62;1;2;6;22c';
  }

  String secondaryDeviceAttributes() {
    const model = 0;
    const version = 0;
    return '\x1b[>$model;$version;0c';
  }

  String tertiaryDeviceAttributes() {
    return '\x1bP!|00000000\x1b\\';
  }

  String operatingStatus() {
    return '\x1b[0n';
  }

  String cursorPosition(int x, int y) {
    // CPR (CSI row ; col R) is 1-based.
    return '\x1b[${y + 1};${x + 1}R';
  }

  String bracketedPaste(String text) {
    return '\x1b[200~$text\x1b[201~';
  }

  String size(int rows, int cols) {
    return '\x1b[8;$rows;${cols}t';
  }

  /// OSC 10 response: report the current default foreground color.
  /// [r], [g], [b] are 8-bit (0-255) color components.
  String foregroundColor(int r, int g, int b) {
    // xterm uses 16-bit per component in the reply.
    final rs = (r * 257).toRadixString(16).padLeft(4, '0');
    final gs = (g * 257).toRadixString(16).padLeft(4, '0');
    final bs = (b * 257).toRadixString(16).padLeft(4, '0');
    return '\x1b]10;rgb:$rs/$gs/$bs\x1b\\';
  }

  /// OSC 11 response: report the current default background color.
  String backgroundColor(int r, int g, int b) {
    final rs = (r * 257).toRadixString(16).padLeft(4, '0');
    final gs = (g * 257).toRadixString(16).padLeft(4, '0');
    final bs = (b * 257).toRadixString(16).padLeft(4, '0');
    return '\x1b]11;rgb:$rs/$gs/$bs\x1b\\';
  }
}
