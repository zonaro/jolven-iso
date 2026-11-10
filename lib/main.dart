import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import 'models/iso_project.dart';
import 'services/nobara_catalog.dart';
import 'services/iso_downloader.dart';
import 'services/iso_signature.dart';

void main() => runApp(const JolvenIsoApp());

class JolvenIsoApp extends StatelessWidget {
  const JolvenIsoApp({super.key});

  @override
  Widget build(BuildContext context) => MaterialApp(
        title: 'Jolven ISO Builder',
        debugShowCheckedModeBanner: false,
        theme: ThemeData(
          useMaterial3: true,
          colorScheme: ColorScheme.fromSeed(
            seedColor: const Color(0xFF9175D9),
            brightness: Brightness.dark,
          ),
        ),
        home: const BuilderScreen(),
      );
}

class BuilderScreen extends StatefulWidget {
  const BuilderScreen({super.key});

  @override
  State<BuilderScreen> createState() => _BuilderScreenState();
}

class _BuilderScreenState extends State<BuilderScreen> {
  NobaraEdition _edition = NobaraEdition.gnome;
  String? _isoPath;
  String? _actualHash;
  String _themeName = 'Jolven';
  String _accentHex = '#A78BFA';
  bool _working = false;
  String _status = 'Selecione uma ISO oficial do Nobara para começar.';
  final _expectedHash = TextEditingController();
  final _extras = <String>{};
  final _catalogService = NobaraCatalog();
  final _downloader = IsoDownloader();
  List<NobaraIso> _catalog = [];
  NobaraIso? _selectedOnline;
  double? _downloadProgress;
  DateTime _lastProgress = DateTime.fromMillisecondsSinceEpoch(0);

  static const _options = <String, String>{
    'sunshine': 'Sunshine',
    'retroarch': 'RetroArch',
    'uzdoom': 'UZDoom',
    'eden': 'Eden',
    'cemu': 'Cemu',
    'openrgb': 'OpenRGB',
  };

  @override
  void dispose() {
    _downloader.cancel();
    _expectedHash.dispose();
    super.dispose();
  }

  Future<void> _chooseIso() async {
    final file = await openFile(
      acceptedTypeGroups: [
        const XTypeGroup(label: 'Imagem ISO', extensions: ['iso']),
      ],
    );
    if (!mounted || file == null) return;
    setState(() {
      _isoPath = file.path;
      _actualHash = null;
      _expectedHash.clear();
      _status = 'ISO selecionada. Confira o SHA-256 com o publicado pelo Nobara.';
    });
  }


  Future<void> _loadCatalog() async {
    if (_working) return;
    setState(() {
      _working = true;
      _status = 'Consultando as edições publicadas no site oficial do Nobara...';
    });
    try {
      final entries = await _catalogService.load();
      if (!mounted) return;
      setState(() {
        _catalog = entries;
        _selectedOnline = entries.where((iso) => iso.edition == _edition).firstOrNull;
        _status = 'Catálogo oficial carregado. Selecione a edição e baixe a ISO.';
      });
    } catch (error) {
      if (mounted) {
        setState(() => _status = 'Não foi possível consultar o catálogo: $error');
      }
    } finally {
      if (mounted) setState(() => _working = false);
    }
  }

  Future<void> _downloadSelected() async {
    final selected = _selectedOnline;
    if (_working || selected == null || selected.edition != _edition) return;
    final destination = await getSaveLocation(
      suggestedName: selected.name,
      acceptedTypeGroups: [
        const XTypeGroup(label: 'Imagem ISO', extensions: ['iso']),
      ],
    );
    if (!mounted || destination == null) return;
    setState(() {
      _working = true;
      _downloadProgress = null;
      _actualHash = null;
      _status = 'Lendo checksum publicado no servidor oficial do Nobara...';
    });
    try {
      final expected = await _catalogService.expectedHash(selected);
      if (!mounted) return;
      _expectedHash.text = expected;
      final hash = await _downloader.download(
        selected,
        File(destination.path),
        expectedSha256: expected,
        onProgress: (received, total) {
          if (!mounted) return;
          final now = DateTime.now();
          if (received != total &&
              now.difference(_lastProgress).inMilliseconds < 250) {
            return;
          }
          _lastProgress = now;
          setState(() {
            _downloadProgress = total == null || total == 0
                ? null : received / total;
            _status = total == null
                ? 'Baixados ${received ~/ (1024 * 1024)} MiB...'
                : 'Baixados ${received ~/ (1024 * 1024)} de '
                  '${total ~/ (1024 * 1024)} MiB...';
          });
        },
      );
      if (!mounted) return;
      setState(() {
        _isoPath = destination.path;
        _actualHash = hash;
        _downloadProgress = 1;
        _status = 'ISO baixada e SHA-256 conferido com o checksum oficial.';
      });
    } on DownloadCancelled {
      if (mounted) setState(() => _status = 'Download interrompido. Arquivo .part pode ser retomado.');
    } catch (error) {
      if (mounted) setState(() => _status = 'Download não concluído: $error');
    } finally {
      if (mounted) setState(() => _working = false);
    }
  }

  Future<void> _openOfficialSite() async {
    final url = Uri.parse('https://nobaraproject.org/');
    if (!await launchUrl(url, mode: LaunchMode.externalApplication) &&
        mounted) {
      setState(() => _status = 'Não foi possível abrir a página oficial.');
    }
  }

  Future<void> _calculateHash() async {
    final path = _isoPath;
    if (path == null || _working) return;
    setState(() {
      _working = true;
      _status = 'Calculando SHA-256. Uma ISO grande pode levar alguns minutos.';
    });
    try {
      final file = File(path);
      if (!await file.exists() || !path.toLowerCase().endsWith('.iso')) {
        throw const FormatException('Selecione um arquivo .iso existente.');
      }
      if (!await IsoSignature.isIso9660(file)) {
        throw const FormatException('Arquivo não possui assinatura ISO-9660.');
      }
      final digest = await sha256.bind(file.openRead()).first;
      if (!mounted) return;
      setState(() {
        _actualHash = digest.toString();
        _status = 'SHA-256 calculado. Compare com o hash da fonte oficial.';
      });
    } catch (error) {
      if (mounted) setState(() => _status = 'Falha na verificação: $error');
    } finally {
      if (mounted) setState(() => _working = false);
    }
  }

  bool get _verified =>
      _actualHash != null &&
      IsoProject.sha256Pattern.hasMatch(_expectedHash.text.trim()) &&
      _actualHash!.toLowerCase() == _expectedHash.text.trim().toLowerCase();

  Future<void> _saveProject() async {
    if (!_verified || _isoPath == null) {
      setState(() => _status = 'Informe o SHA-256 oficial e confira a ISO primeiro.');
      return;
    }
    final project = IsoProject(
      edition: _edition,
      sourceIso: _isoPath!,
      sourceSha256: _actualHash!,
      expectedSha256: _expectedHash.text.trim(),
      extras: _extras.toList(),
      theme: _themeName,
      accentHex: _accentHex,
    );
    try {
      final location = await getSaveLocation(
        suggestedName: 'jolven-iso-project.json',
        acceptedTypeGroups: [
          const XTypeGroup(label: 'Projeto JSON', extensions: ['json']),
        ],
      );
      if (location == null) return;
      final output = const JsonEncoder.withIndent('  ').convert(project.toJson());
      await File(location.path).writeAsString('$output\n', flush: true);
      if (mounted) {
        setState(() => _status =
            'Projeto salvo. O motor de remasterização ainda não está implementado.');
      }
    } catch (error) {
      if (mounted) setState(() => _status = 'Erro ao salvar: $error');
    }
  }

  @override
  Widget build(BuildContext context) {
    final matched = _verified;
    return Scaffold(
      appBar: AppBar(title: const Text('Jolven ISO Builder')),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 780),
          child: ListView(
            padding: const EdgeInsets.all(24),
            children: [
              const Text('Personalize uma ISO do Nobara',
                  style: TextStyle(fontSize: 27, fontWeight: FontWeight.w600)),
              const SizedBox(height: 8),
              const Text(
                'M1 · Pré-verificação e exportação do projeto. '
                'A injeção do Jolven e a geração de ISO estão em desenvolvimento.',
              ),
              const SizedBox(height: 24),
              _section('1 · Imagem base'),
              DropdownButton<NobaraEdition>(
                value: _edition,
                isExpanded: true,
                items: [
                  for (final edition in NobaraEdition.values)
                    DropdownMenuItem(
                      value: edition,
                      child: Text('Nobara ${edition.label}'),
                    ),
                ],
                onChanged: (value) {
                  if (value != null) {
                    setState(() {
                      _edition = value;
                      _selectedOnline = _catalog.where((iso) => iso.edition == value).firstOrNull;
                    });
                  }
                },
              ),
              const SizedBox(height: 8),
              Wrap(spacing: 12, runSpacing: 8, children: [
                OutlinedButton.icon(
                  onPressed: _working ? null : _chooseIso,
                  icon: const Icon(Icons.folder_open),
                  label: const Text('Selecionar ISO local'),
                ),
                TextButton.icon(
                  onPressed: _openOfficialSite,
                  icon: const Icon(Icons.open_in_new),
                  label: const Text('Baixar no site oficial'),
                ),
              ]),
              const SizedBox(height: 8),
              Text(_isoPath ?? 'Nenhum arquivo selecionado.',
                  maxLines: 2, overflow: TextOverflow.ellipsis),
              const SizedBox(height: 12),
              Wrap(spacing: 12, runSpacing: 8, children: [
                OutlinedButton.icon(
                  onPressed: _working ? null : _loadCatalog,
                  icon: const Icon(Icons.refresh),
                  label: const Text('Consultar catálogo oficial'),
                ),
                if (_selectedOnline != null)
                  FilledButton.tonalIcon(
                    onPressed: _working ? null : _downloadSelected,
                    icon: const Icon(Icons.download),
                    label: const Text('Baixar ISO com verificação'),
                  ),
                if (_working && _selectedOnline != null)
                  TextButton.icon(
                    onPressed: _downloader.cancel,
                    icon: const Icon(Icons.cancel_outlined),
                    label: const Text('Cancelar download'),
                  ),
              ]),
              if (_selectedOnline != null) ...[
                const SizedBox(height: 6),
                SelectableText('Disponível no site oficial: ${_selectedOnline!.name}'),
              ],
              if (_downloadProgress != null) ...[
                const SizedBox(height: 8),
                LinearProgressIndicator(value: _downloadProgress),
              ],
              const SizedBox(height: 14),
              TextField(
                controller: _expectedHash,
                autocorrect: false,
                decoration: const InputDecoration(
                  labelText: 'SHA-256 oficial esperado',
                  border: OutlineInputBorder(),
                  helperText: 'Cole o checksum publicado pelo Nobara. Nunca presuma autenticidade.',
                ),
                onChanged: (_) => setState(() {}),
              ),
              const SizedBox(height: 8),
              Row(children: [
                FilledButton.tonalIcon(
                  onPressed: _working || _isoPath == null ? null : _calculateHash,
                  icon: const Icon(Icons.verified_user_outlined),
                  label: const Text('Calcular SHA-256'),
                ),
                const SizedBox(width: 10),
                if (_working) const SizedBox(
                  width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2),
                ),
              ]),
              if (_actualHash != null) ...[
                const SizedBox(height: 8),
                SelectableText('SHA-256 calculado: $_actualHash'),
                Text(
                  matched ? 'Coincide com o hash informado.' : 'Não verificado: confira o valor esperado.',
                  style: TextStyle(color: matched ? Colors.greenAccent : Colors.orangeAccent),
                ),
              ],
              const SizedBox(height: 24),
              _section('2 · Sessão e aplicativos'),
              const CheckboxListTile(
                value: true,
                onChanged: null,
                title: Text('Jolven + Jolven Session'),
                subtitle: Text('Obrigatório na ISO personalizada final.'),
                controlAffinity: ListTileControlAffinity.leading,
              ),
              for (final option in _options.entries)
                CheckboxListTile(
                  value: _extras.contains(option.key),
                  title: Text(option.value),
                  subtitle: const Text('Planejado para first-boot, se disponível em DNF/Flatpak.'),
                  controlAffinity: ListTileControlAffinity.leading,
                  onChanged: (checked) => setState(() {
                    if (checked == true) {
                      _extras.add(option.key);
                    } else {
                      _extras.remove(option.key);
                    }
                  }),
                ),
              const SizedBox(height: 24),
              _section('3 · Aparência do Jolven'),
              DropdownButton<String>(
                value: _themeName,
                isExpanded: true,
                items: const [
                  DropdownMenuItem(value: 'Jolven', child: Text('Jolven')),
                  DropdownMenuItem(value: 'Adwaita', child: Text('Adwaita')),
                  DropdownMenuItem(value: 'Custom', child: Text('Personalizado')),
                ],
                onChanged: (value) {
                  if (value != null) setState(() => _themeName = value);
                },
              ),
              Wrap(spacing: 8, children: [
                for (final item in const ['#A78BFA', '#4285F4', '#22C55E', '#EF4444', '#F59E0B'])
                  IconButton(
                    tooltip: 'Cor $item',
                    onPressed: () => setState(() => _accentHex = item),
                    icon: Icon(
                      _accentHex == item ? Icons.check_circle : Icons.circle,
                      color: Color(int.parse('FF${item.substring(1)}', radix: 16)),
                      size: 30,
                    ),
                  ),
              ]),
              const Text('Chaves de API serão solicitadas após o primeiro login. Nunca serão incluídas na ISO.'),
              const SizedBox(height: 24),
              _section('4 · Exportar projeto'),
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Text(_status),
                ),
              ),
              const SizedBox(height: 8),
              FilledButton.icon(
                onPressed: matched && !_working ? _saveProject : null,
                icon: const Icon(Icons.save_alt),
                label: const Text('Exportar projeto JSON'),
              ),
              const SizedBox(height: 8),
              const OutlinedButton(
                onPressed: null,
                child: Text('Gerar ISO (em desenvolvimento)'),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _section(String title) => Padding(
        padding: const EdgeInsets.only(bottom: 12),
        child: Text(title,
            style: const TextStyle(fontSize: 19, fontWeight: FontWeight.w600)),
      );
}
