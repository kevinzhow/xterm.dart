import 'dart:async';
import 'dart:convert';

import 'package:dartssh2/dartssh2.dart';
import 'package:example/src/platform_menu.dart';
import 'package:example/src/virtual_keyboard.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:xterm/xterm.dart';

void main() {
  runApp(MyApp());
}

const _quickSshHost = 'k8-plus.tail4653d.ts.net';
const _quickSshPort = 22;
const _quickSshUsername = 'kevinzhow';
const _sshSessions = <SshSessionConfig>[
  SshSessionConfig(
    name: 'kevinzhow@k8-plus',
    host: _quickSshHost,
    port: _quickSshPort,
    username: _quickSshUsername,
    note: 'Tailnet',
  ),
];

bool get isDesktop {
  if (kIsWeb) return false;
  return [
    TargetPlatform.windows,
    TargetPlatform.linux,
    TargetPlatform.macOS,
  ].contains(defaultTargetPlatform);
}

class MyApp extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'xterm.dart demo',
      debugShowCheckedModeBanner: false,
      home: AppPlatformMenu(child: Home()),
      // shortcuts: ,
    );
  }
}

class Home extends StatefulWidget {
  Home({super.key});

  @override
  // ignore: library_private_types_in_public_api
  _HomeState createState() => _HomeState();
}

class _HomeState extends State<Home> {
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('SSH Sessions'),
      ),
      body: ListView.separated(
        padding: const EdgeInsets.all(12),
        itemCount: _sshSessions.length,
        separatorBuilder: (_, __) => const SizedBox(height: 8),
        itemBuilder: (context, index) {
          final session = _sshSessions[index];
          return Card(
            child: ListTile(
              leading: const CircleAvatar(
                child: Icon(Icons.terminal),
              ),
              title: Text(session.name),
              subtitle: Text(
                '${session.username}@${session.host}:${session.port}'
                '${session.note == null ? '' : ' · ${session.note}'}',
              ),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => _openQuickSsh(context, session),
            ),
          );
        },
      ),
    );
  }

  Future<void> _openQuickSsh(
    BuildContext context,
    SshSessionConfig session,
  ) async {
    final password = await _promptPassword(context, session);
    if (!mounted || password == null) return;

    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => QuickSshPage(
          host: session.host,
          port: session.port,
          username: session.username,
          password: password,
        ),
      ),
    );
  }

  Future<String?> _promptPassword(
    BuildContext context,
    SshSessionConfig session,
  ) async {
    var password = '';

    return showDialog<String>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('SSH Password'),
          content: TextField(
            autofocus: true,
            obscureText: true,
            decoration: const InputDecoration(
              labelText: 'Password',
            ).copyWith(
              helperText: '${session.username}@${session.host}:${session.port}',
            ),
            onChanged: (value) => password = value,
            onSubmitted: (value) => Navigator.of(context).pop(value),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () => Navigator.of(context).pop(password),
              child: const Text('Connect'),
            ),
          ],
        );
      },
    );
  }
}

class SshSessionConfig {
  const SshSessionConfig({
    required this.name,
    required this.host,
    required this.port,
    required this.username,
    this.note,
  });

  final String name;
  final String host;
  final int port;
  final String username;
  final String? note;
}

class QuickSshPage extends StatefulWidget {
  const QuickSshPage({
    super.key,
    required this.host,
    required this.port,
    required this.username,
    required this.password,
  });

  final String host;
  final int port;
  final String username;
  final String password;

  @override
  State<QuickSshPage> createState() => _QuickSshPageState();
}

class _QuickSshPageState extends State<QuickSshPage> {
  final _terminalViewKey = GlobalKey<TerminalViewState>();
  late final keyboard = VirtualKeyboard(defaultInputHandler);
  late final terminal = Terminal(
    maxLines: 10000,
    inputHandler: keyboard,
  );

  SSHClient? _client;
  SSHSession? _session;
  final List<StreamSubscription<dynamic>> _subscriptions = [];
  late String _title = '${widget.username}@${widget.host}';
  var _connected = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _terminalViewKey.currentState?.requestKeyboard();
    });
    _connect();
  }

  Future<void> _connect() async {
    terminal.write(
        'Connecting to ${widget.username}@${widget.host}:${widget.port}...\r\n');

    try {
      final client = SSHClient(
        await SSHSocket.connect(widget.host, widget.port),
        username: widget.username,
        onPasswordRequest: () => widget.password,
      );
      _client = client;

      final session = await client.shell(
        pty: SSHPtyConfig(
          width: terminal.viewWidth,
          height: terminal.viewHeight,
        ),
      );
      _session = session;

      if (!mounted) return;

      setState(() => _connected = true);

      terminal.buffer.clear();
      terminal.buffer.setCursor(0, 0);

      terminal.onTitleChange = (title) {
        if (!mounted) return;
        setState(() => _title = title.isEmpty ? _title : title);
      };

      terminal.onResize = (width, height, pixelWidth, pixelHeight) {
        _session?.resizeTerminal(width, height, pixelWidth, pixelHeight);
      };

      terminal.onOutput = (data) {
        final session = _session;
        if (session == null) return;
        session.write(Uint8List.fromList(utf8.encode(data)));
      };

      _subscriptions.add(
        session.stdout
            .cast<List<int>>()
            .transform(const Utf8Decoder())
            .listen(terminal.write),
      );
      _subscriptions.add(
        session.stderr
            .cast<List<int>>()
            .transform(const Utf8Decoder())
            .listen(terminal.write),
      );
      _subscriptions.add(
        session.done.asStream().listen((_) {
          terminal.write('\r\n[SSH session closed]\r\n');
          if (mounted) setState(() => _connected = false);
        }),
      );
    } catch (e) {
      terminal.write('SSH connection failed: $e\r\n');
    }
  }

  @override
  void dispose() {
    for (final sub in _subscriptions) {
      sub.cancel();
    }
    _session?.close();
    _client?.close();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Column(
        children: [
          AppBar(
            title: Text(_title),
            actions: [
              if (!_connected)
                IconButton(
                  icon: const Icon(Icons.refresh),
                  onPressed: _connect,
                  tooltip: 'Reconnect',
                ),
            ],
          ),
          Expanded(
            child: TerminalView(
              key: _terminalViewKey,
              terminal,
              autofocus: true,
              keyboardType: TextInputType.visiblePassword,
              deleteDetection: true,
            ),
          ),
          SafeArea(
            top: false,
            child: _SshToolbar(
              title: _title,
              connected: _connected,
              keyboard: keyboard,
              onBack: () => Navigator.of(context).maybePop(),
              onReconnect: _connect,
              onKey: (key, {shift = false, alt = false, ctrl = false}) {
                terminal.keyInput(key, shift: shift, alt: alt, ctrl: ctrl);
                _terminalViewKey.currentState?.requestKeyboard();
              },
              onCtrlChar: (char) {
                terminal.charInput(char.codeUnitAt(0), ctrl: true);
                _terminalViewKey.currentState?.requestKeyboard();
              },
              onRequestKeyboard: () =>
                  _terminalViewKey.currentState?.requestKeyboard(),
            ),
          ),
        ],
      ),
    );
  }
}

class _SshToolbar extends StatelessWidget {
  const _SshToolbar({
    required this.title,
    required this.connected,
    required this.keyboard,
    required this.onBack,
    required this.onReconnect,
    required this.onKey,
    required this.onCtrlChar,
    required this.onRequestKeyboard,
  });

  final String title;
  final bool connected;
  final VirtualKeyboard keyboard;
  final VoidCallback onBack;
  final VoidCallback onReconnect;
  final void Function(
    TerminalKey key, {
    bool shift,
    bool alt,
    bool ctrl,
  }) onKey;
  final void Function(String char) onCtrlChar;
  final VoidCallback onRequestKeyboard;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Material(
      color: colorScheme.surface.withValues(alpha: 0.96),
      elevation: 1,
      child: SizedBox(
        height: 52,
        child: Row(
          children: [
            Expanded(
              child: ListView(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
                children: [
                  _iconBtn(Icons.arrow_back, onBack, tooltip: 'Back'),
                  const SizedBox(width: 6),
                  _statusChip(context),
                  const SizedBox(width: 6),
                  _modifierGroup(context),
                  const SizedBox(width: 6),
                  _btn('Esc', () => onKey(TerminalKey.escape)),
                  _btn('Tab', () => onKey(TerminalKey.tab)),
                  _btn('Enter', () => onKey(TerminalKey.enter)),
                  _btn('Up', () => onKey(TerminalKey.arrowUp)),
                  _btn('Down', () => onKey(TerminalKey.arrowDown)),
                  _btn('Left', () => onKey(TerminalKey.arrowLeft)),
                  _btn('Right', () => onKey(TerminalKey.arrowRight)),
                  _btn('C+C', () => onCtrlChar('c')),
                  _btn('C+D', () => onCtrlChar('d')),
                  _btn('C+L', () => onCtrlChar('l')),
                  _btn('C+Z', () => onCtrlChar('z')),
                  _btn('Kb', onRequestKeyboard),
                  if (!connected)
                    _btn('Reconnect', onReconnect, prominent: true),
                  const SizedBox(width: 4),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _modifierGroup(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return AnimatedBuilder(
      animation: keyboard,
      builder: (context, _) {
        return Container(
          decoration: BoxDecoration(
            color: colorScheme.surfaceContainerHighest,
            borderRadius: BorderRadius.circular(999),
            border: Border.all(color: colorScheme.outlineVariant),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              _modifierPill(
                'Ctrl',
                keyboard.ctrl,
                () => keyboard.ctrl = !keyboard.ctrl,
              ),
              _divider(colorScheme),
              _modifierPill(
                'Alt',
                keyboard.alt,
                () => keyboard.alt = !keyboard.alt,
              ),
              _divider(colorScheme),
              _modifierPill(
                'Shift',
                keyboard.shift,
                () => keyboard.shift = !keyboard.shift,
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _statusChip(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final color = connected ? Colors.green : colorScheme.error;
    final fg = colorScheme.onSurface;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: colorScheme.outlineVariant),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 8,
            height: 8,
            decoration: BoxDecoration(
              color: color,
              shape: BoxShape.circle,
            ),
          ),
          const SizedBox(width: 8),
          ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 220),
            child: Text(
              title,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: fg,
                fontSize: 12,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _modifierPill(String label, bool selected, VoidCallback onTap) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(999),
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
          decoration: BoxDecoration(
            color: selected ? Colors.white.withValues(alpha: 0.08) : null,
            borderRadius: BorderRadius.circular(999),
          ),
          child: Text(
            label,
            style: TextStyle(
              fontSize: 12,
              fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
            ),
          ),
        ),
      ),
    );
  }

  Widget _divider(ColorScheme colorScheme) {
    return Container(
      width: 1,
      height: 20,
      color: colorScheme.outlineVariant,
    );
  }

  Widget _iconBtn(
    IconData icon,
    VoidCallback onPressed, {
    required String tooltip,
  }) {
    return SizedBox(
      width: 34,
      height: 34,
      child: IconButton(
        onPressed: onPressed,
        tooltip: tooltip,
        iconSize: 18,
        padding: EdgeInsets.zero,
        visualDensity: VisualDensity.compact,
        style: IconButton.styleFrom(
          backgroundColor: Colors.transparent,
          side: const BorderSide(width: 0.8),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(10),
          ),
        ),
        icon: Icon(icon),
      ),
    );
  }

  Widget _btn(
    String label,
    VoidCallback onPressed, {
    bool prominent = false,
  }) {
    final style = prominent
        ? FilledButton.styleFrom(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            minimumSize: const Size(0, 34),
            visualDensity: VisualDensity.compact,
          )
        : OutlinedButton.styleFrom(
            padding: const EdgeInsets.symmetric(horizontal: 10),
            minimumSize: const Size(0, 34),
            visualDensity: VisualDensity.compact,
            side: const BorderSide(width: 0.8),
          );

    final child = Text(label, style: const TextStyle(fontSize: 12));

    if (prominent) {
      return Padding(
        padding: const EdgeInsets.only(right: 6),
        child: FilledButton(
          onPressed: onPressed,
          style: style,
          child: child,
        ),
      );
    }

    return Padding(
      padding: const EdgeInsets.only(right: 6),
      child: OutlinedButton(
        onPressed: onPressed,
        style: style,
        child: child,
      ),
    );
  }
}
