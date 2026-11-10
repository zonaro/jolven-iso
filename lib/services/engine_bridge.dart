import 'dart:convert';
import 'dart:io';

import '../models/iso_project.dart';

/// Runs the bundled, read-only ISO diagnostics without invoking a shell.
class EngineResult {
  const EngineResult(this.code, this.out, this.error);

  final int code;
  final String out;
  final String error;

  bool get ok => code == 0;

  Map<String, dynamic>? get json {
    try {
      final value = jsonDecode(out);
      if (value is Map<String, dynamic>) {
        return value;
      }
    } on FormatException {
      // Diagnostics may be plain stderr when Python or WSL is unavailable.
    }
    return null;
  }

  String get message => ok ? out.trim() : error.trim().isNotEmpty
      ? error.trim() : out.trim();
}

class EngineBridge {
  Process? _process;
  bool _composeRunning = false;

  bool get running => _process != null;

  void cancelReadOnlyCommand() {
    if (!_composeRunning) _process?.kill();
  }

  Future<String> _engineDirectory() async {
    final exe = File(Platform.resolvedExecutable).parent;
    final candidates = <Directory>[
      Directory('${Directory.current.path}/engine'),
      Directory('${exe.path}/engine'),
      Directory('${exe.path}/share/jolven-iso/engine'),
      Directory('${exe.parent.path}/share/jolven-iso/engine'),
      Directory('${exe.parent.path}/engine'),
    ];
    for (final candidate in candidates) {
      if (await File('${candidate.path}/jolven_iso/cli.py').exists()) {
        return candidate.absolute.path;
      }
    }
    throw const FileSystemException(
      'Motor Python não está no pacote. Reinstale o Jolven ISO Builder.');
  }

  Future<String> _wslPath(String windowsPath) async {
    final result = await Process.run(
      'wsl.exe', ['--exec', 'wslpath', '-a', windowsPath],
      runInShell: false,
    );
    final value = result.stdout.toString().trim();
    if (result.exitCode != 0 || !value.startsWith('/')) {
      throw ProcessException(
        'wsl.exe', ['wslpath', windowsPath],
        'Configure WSL2 com Python 3 ou use o gerador no Linux. '
        '${result.stderr}',
        result.exitCode,
      );
    }
    return value;
  }

  Future<EngineResult> _invoke(List<String> arguments, {bool compose = false}) async {
    if (_process != null) {
      throw StateError('Outra verificação ainda está em andamento.');
    }
    if (!Platform.isLinux && !Platform.isWindows) {
      throw UnsupportedError(
        'Motor de ISOs requer Linux ou WSL2; macOS será suportado via VM.');
    }
    final engine = await _engineDirectory();
    late String executable;
    late List<String> args;
    final env = <String, String>{};
    if (Platform.isWindows) {
      executable = 'wsl.exe';
      final root = await _wslPath(engine);
      args = ['--exec', 'env', 'PYTHONPATH=$root',
        'python3', '-m', 'jolven_iso.cli', ...arguments];
    } else {
      executable = 'python3';
      args = ['-m', 'jolven_iso.cli', ...arguments];
      env.addAll(Platform.environment);
      final prior = env['PYTHONPATH'];
      env['PYTHONPATH'] = prior == null || prior.isEmpty
          ? engine : '$engine:$prior';
    }

    final process = await Process.start(
      executable, args,
      environment: env.isEmpty ? null : env,
      runInShell: false,
    );
    _process = process;
    _composeRunning = compose;
    try {
      final stdoutFuture = process.stdout.transform(utf8.decoder).join();
      final stderrFuture = process.stderr.transform(utf8.decoder).join();
      final status = await process.exitCode;
      return EngineResult(
        status, await stdoutFuture, await stderrFuture);
    } finally {
      _process = null;
      _composeRunning = false;
    }
  }

  Future<EngineResult> requirements() => _invoke(['requirements']);

  Future<EngineResult> plan(IsoProject project) async {
    if (!project.hashMatches) {
      throw const FormatException('Confira o SHA-256 da ISO antes do preflight.');
    }
    final data = Map<String, dynamic>.from(project.toJson());
    if (Platform.isWindows) {
      data['source_iso'] = await _wslPath(project.sourceIso);
    }
    final dir = await Directory.systemTemp.createTemp('jolven-iso-plan-');
    try {
      final path = File('${dir.path}/project.json');
      await path.writeAsString(jsonEncode(data), flush: true);
      return await _invoke([
        'plan', '--project',
        Platform.isWindows ? await _wslPath(path.path) : path.path,
      ]);
    } finally {
      await dir.delete(recursive: true);
    }
  }

  /// Experiments only: requires user-space libguestfs, explicit confirmation
  /// in the UI and an independently provided SHA-256 for the Jolven artifact.
  /// Never elevates privileges or invokes sudo/pkexec automatically.
  Future<EngineResult> compose({
    required IsoProject project,
    required String jolvenArchive,
    required String jolvenSha256,
    required String outputIso,
  }) async {
    if (!project.hashMatches ||
        !IsoProject.sha256Pattern.hasMatch(jolvenSha256)) {
      throw const FormatException('Checksums de ISO/Jolven inválidos.');
    }
    if (!await File(jolvenArchive).exists()) {
      throw const FileSystemException('Pacote Jolven não encontrado.');
    }
    if (await File(outputIso).exists()) {
      throw const FileSystemException('Destino já existe; escolha outro arquivo.');
    }
    final diagnostics = await requirements();
    final info = diagnostics.json;
    if (!diagnostics.ok ||
        info?['ready_for_experimental_compose'] != true ||
        info?['mount_backend'] != 'libguestfs-fuse') {
      throw UnsupportedError(
        'É necessário Linux/WSL2 com libguestfs/FUSE funcionando '
        '(sem sudo). Diagnóstico: ${diagnostics.message}',
      );
    }

    final data = Map<String, dynamic>.from(project.toJson());
    final dir = await Directory.systemTemp.createTemp('jolven-iso-compose-');
    try {
      if (Platform.isWindows) {
        data['source_iso'] = await _wslPath(project.sourceIso);
      }
      final jsonFile = File('${dir.path}/project.json');
      await jsonFile.writeAsString(jsonEncode(data), flush: true);
      final args = [
        'compose',
        '--project',
        Platform.isWindows ? await _wslPath(jsonFile.path) : jsonFile.path,
        '--jolven-archive',
        Platform.isWindows ? await _wslPath(jolvenArchive) : jolvenArchive,
        '--jolven-sha256', jolvenSha256.toLowerCase(),
        '--output',
        Platform.isWindows ? await _wslPath(outputIso) : outputIso,
        if (Platform.isWindows) ...['--workspace-dir', '/tmp'],
        '--experimental',
        '--accept-unverified-provenance',
      ];
      return await _invoke(args, compose: true);
    } finally {
      await dir.delete(recursive: true);
    }
  }
}
