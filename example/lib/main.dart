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
  var _title = '$_quickSshUsername@$_quickSshHost';
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
      appBar: AppBar(
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
      body: Column(
        children: [
          Expanded(
            child: TerminalView(
              key: _terminalViewKey,
              terminal,
              autofocus: true,
              keyboardType: TextInputType.visiblePassword,
              deleteDetection: true,
            ),
          ),
          _SshActionBar(
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
          if (!isDesktop)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: VirtualKeyboardView(keyboard),
            ),
        ],
      ),
    );
  }
}

class _SshActionBar extends StatelessWidget {
  const _SshActionBar({
    required this.onKey,
    required this.onCtrlChar,
    required this.onRequestKeyboard,
  });

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
    final items = <Widget>[
      _btn('Esc', () => onKey(TerminalKey.escape)),
      _btn('Tab', () => onKey(TerminalKey.tab)),
      _btn('Enter', () => onKey(TerminalKey.enter)),
      _btn('Up', () => onKey(TerminalKey.arrowUp)),
      _btn('Down', () => onKey(TerminalKey.arrowDown)),
      _btn('Left', () => onKey(TerminalKey.arrowLeft)),
      _btn('Right', () => onKey(TerminalKey.arrowRight)),
      _btn('Ctrl+C', () => onCtrlChar('c')),
      _btn('Ctrl+D', () => onCtrlChar('d')),
      _btn('Ctrl+L', () => onCtrlChar('l')),
      _btn('Ctrl+Z', () => onCtrlChar('z')),
      _btn('Kb', onRequestKeyboard),
    ];

    return Material(
      color: Theme.of(context).colorScheme.surfaceContainerHighest,
      child: SizedBox(
        height: 44,
        child: ListView.separated(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
          scrollDirection: Axis.horizontal,
          itemBuilder: (_, i) => items[i],
          separatorBuilder: (_, __) => const SizedBox(width: 6),
          itemCount: items.length,
        ),
      ),
    );
  }

  Widget _btn(String label, VoidCallback onPressed) {
    return OutlinedButton(
      onPressed: onPressed,
      style: OutlinedButton.styleFrom(
        padding: const EdgeInsets.symmetric(horizontal: 10),
        minimumSize: const Size(0, 32),
        visualDensity: VisualDensity.compact,
      ),
      child: Text(label),
    );
  }
}
