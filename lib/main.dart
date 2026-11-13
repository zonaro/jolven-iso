import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:file_selector/file_selector.dart';
// Flutter 3.50 flags this legacy import while the Material UI split settles.
// Keep migration separate from the multi-distro ISO changes.
// ignore: deprecated_member_use
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import 'models/iso_project.dart';
import 'services/nobara_catalog.dart';
import 'services/iso_downloader.dart';
import 'services/iso_signature.dart';
import 'services/engine_bridge.dart';
import 'services/jolven_artifact_service.dart';

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
  final _jolvenArchiveSha = TextEditingController();
  String? _jolvenArchivePath;
  bool _confirmExperimental = false;
  final _extras = <String>{};
  final _catalogService = NobaraCatalog();
  final _downloader = IsoDownloader();
  final _engine = EngineBridge();
  final _jolvenArtifacts = JolvenArtifactService();
  double? _jolvenProgress;
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
    _engine.cancelReadOnlyCommand();
    _expectedHash.dispose();
    _jolvenArchiveSha.dispose();
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
      _isoPath != null &&
      IsoProject.filenameMatchesEdition(_isoPath!, _edition) &&
      _actualHash != null &&
      IsoProject.sha256Pattern.hasMatch(_expectedHash.text.trim()) &&
      _actualHash!.toLowerCase() == _expectedHash.text.trim().toLowerCase();




  Future<void> _downloadJolvenRelease() async {
    if (_working) return;
    setState(() {
      _working = true;
      _jolvenProgress = null;
      _status = 'Consultando pacote Jolven publicado nas releases do Builder...';
    });
    try {
      final release = await _jolvenArtifacts.latest();
      final expected = await _jolvenArtifacts.expectedSha256(release);
      if (!mounted) return;
      final destination = await getSaveLocation(
        suggestedName: release.name,
        acceptedTypeGroups: [
          const XTypeGroup(label: 'Pacote Jolven', extensions: ['gz']),
        ],
      );
      if (!mounted || destination == null) return;
      _lastProgress = DateTime.fromMillisecondsSinceEpoch(0);
      final hash = await _jolvenArtifacts.download(
        release: release,
        destination: File(destination.path),
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
            _jolvenProgress = total == null || total == 0
                ? null : received / total;
            _status = 'Baixando Jolven: ${received ~/ (1024 * 1024)} MiB...';
          });
        },
      );
      if (!mounted) return;
      setState(() {
        _jolvenArchivePath = destination.path;
        _jolvenArchiveSha.text = hash;
        _jolvenProgress = 1;
        _status = 'Pacote Jolven ${release.version} baixado e verificado.';
      });
    } catch (error) {
      if (mounted) {
        setState(() => _status =
            'Pacote automático indisponível: $error. '
            'Use um arquivo local ou consulte o GitHub Actions.');
      }
    } finally {
      if (mounted) setState(() => _working = false);
    }
  }

  Future<void> _openJolvenArtifacts() async {
    final url = Uri.parse(
      'https://github.com/zonaro/jolven-iso/actions/workflows/jolven-artifact.yml',
    );
    if (!await launchUrl(url, mode: LaunchMode.externalApplication) &&
        mounted) {
      setState(() => _status = 'Não foi possível abrir o workflow Jolven.');
    }
  }

  Future<void> _chooseJolvenArchive() async {
    final file = await openFile(
      acceptedTypeGroups: [
        const XTypeGroup(
          label: 'Pacote Jolven (.tar.gz)',
          extensions: ['gz', 'tgz'],
        ),
      ],
    );
    if (!mounted || file == null) return;
    setState(() {
      _jolvenArchivePath = file.path;
      _jolvenArchiveSha.clear();
      _status = 'Pacote escolhido. Informe o SHA-256 de uma fonte confiável.';
    });
  }

  Future<void> _composeExperimental() async {
    if (_working || !_verified || _jolvenArchivePath == null ||
        !_confirmExperimental ||
        !IsoProject.sha256Pattern.hasMatch(_jolvenArchiveSha.text.trim())) {
      return;
    }
    final accepted = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Gerar ISO experimental?'),
        content: const Text(
          'Esta imagem ainda NÃO foi validada para inicialização, '
          'instalação no disco, NVIDIA ou Secure Boot. '
          'Use apenas em máquina virtual ou ambiente de testes. '
          'O sistema oficial não será modificado. '
          'O processo exige libguestfs/FUSE no Linux ou WSL2, '
          'e nunca solicitará privilégios de administrador automaticamente.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Gerar para testes'),
          ),
        ],
      ),
    );
    if (accepted != true || !mounted) return;
    final destination = await getSaveLocation(
      suggestedName: 'Nobara-Jolven-experimental.iso',
      acceptedTypeGroups: [
        const XTypeGroup(label: 'Imagem ISO', extensions: ['iso']),
      ],
    );
    if (!mounted || destination == null) return;
    setState(() {
      _working = true;
      _status = 'Construindo ISO experimental. Não feche o programa; '
          'a preparação pode demorar vários minutos.';
    });
    try {
      final result = await _engine.compose(
        project: _currentProject(),
        jolvenArchive: _jolvenArchivePath!,
        jolvenSha256: _jolvenArchiveSha.text.trim(),
        outputIso: destination.path,
      );
      if (!mounted) return;
      final data = result.json;
      setState(() {
        _status = result.ok
            ? 'ISO experimental criada: ${destination.path}. '
              'SHA-256: ${data?['sha256'] ?? 'veja o relatório do motor'}. '
              'Não use em produção antes de testar boot e instalação.'
            : 'Falha na geração experimental: ${result.message}';
      });
    } catch (error) {
      if (mounted) {
        setState(() => _status = 'Falha na geração experimental: $error');
      }
    } finally {
      if (mounted) setState(() => _working = false);
    }
  }

  IsoProject _currentProject() {
    if (!_verified || _isoPath == null || _actualHash == null) {
      throw const FormatException('Verifique a ISO e o SHA-256 primeiro.');
    }
    return IsoProject(
      edition: _edition,
      sourceIso: _isoPath!,
      sourceSha256: _actualHash!,
      expectedSha256: _expectedHash.text.trim(),
      extras: _extras.toList(),
      theme: _themeName,
      accentHex: _accentHex,
    );
  }

  Future<void> _engineRequirements() async {
    if (_working) return;
    setState(() {
      _working = true;
      _status = 'Verificando requisitos do motor Python no sistema...';
    });
    try {
      final result = await _engine.requirements();
      if (!mounted) return;
      final data = result.json;
      setState(() {
        _status = result.ok && data != null
            ? 'Backend: ${data['mount_backend']}. '
              'Pronto para composição experimental: '
              '${data['ready_for_experimental_compose']}. '
              'Ferramentas ausentes: '
              '${(data['missing_tools'] as List<dynamic>?)?.join(', ') ?? '?'}'
            : 'Backend não disponível: ${result.message}';
      });
    } catch (error) {
      if (mounted) setState(() => _status = 'Diagnóstico falhou: $error');
    } finally {
      if (mounted) setState(() => _working = false);
    }
  }

  Future<void> _enginePlan() async {
    if (_working || !_verified) return;
    setState(() {
      _working = true;
      _status = 'Validando projeto e ISO pelo motor Python...';
    });
    try {
      final result = await _engine.plan(_currentProject());
      if (!mounted) return;
      setState(() {
        _status = result.ok
            ? 'Pré-verificação aprovada. SHA-256 e layout básico confirmados; '
              'a procedência não está assinada e o boot ainda não foi testado.'
            : 'Pré-verificação falhou: ${result.message}';
      });
    } catch (error) {
      if (mounted) setState(() => _status = 'Pré-verificação falhou: $error');
    } finally {
      if (mounted) setState(() => _working = false);
    }
  }

  Future<void> _saveProject() async {
    if (!_verified || _isoPath == null) {
      setState(() => _status = 'Informe o SHA-256 oficial e confira a ISO primeiro.');
      return;
    }
    final project = _currentProject();
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
                'Personalize a ISO oficial do Nobara e prepare o Jolven. '
                'A geração de ISO ainda é experimental: exige validação em máquina virtual e não é recomendada para instalação principal.',
              ),
              const SizedBox(height: 24),
              const _ExternalIsoInspector(),
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
                onChanged: _working ? null : (value) {
                  if (value != null) {
                    setState(() {
                      _edition = value;
                      _selectedOnline = _catalog.where((iso) => iso.edition == value).firstOrNull;
                      if (_isoPath != null &&
                          !IsoProject.filenameMatchesEdition(_isoPath!, value)) {
                        _status = 'A ISO selecionada pertence a outra edição do Nobara. Selecione a imagem correta.';
                      }
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
              const SizedBox(height: 10),
              Wrap(spacing: 8, runSpacing: 8, children: [
                OutlinedButton.icon(
                  onPressed: _working ? null : _engineRequirements,
                  icon: const Icon(Icons.fact_check_outlined),
                  label: const Text('Verificar motor de ISO'),
                ),
                FilledButton.tonalIcon(
                  onPressed: matched && !_working ? _enginePlan : null,
                  icon: const Icon(Icons.playlist_add_check),
                  label: const Text('Validar projeto no motor'),
                ),
              ]),
              const SizedBox(height: 24),
              _section('5 · ISO experimental (Linux/WSL2)'),
              const Text(
                'A geração é opcional, sem sudo automático, e exige '
                'libguestfs/FUSE. Nenhuma imagem final foi certificada '
                'para instalação. Selecione um pacote Jolven confiável.',
              ),
              const SizedBox(height: 10),
              Wrap(spacing: 8, runSpacing: 8, children: [
                OutlinedButton.icon(
                  onPressed: _working ? null : _chooseJolvenArchive,
                  icon: const Icon(Icons.folder_zip_outlined),
                  label: const Text('Selecionar pacote local'),
                ),
                FilledButton.tonalIcon(
                  onPressed: _working ? null : _downloadJolvenRelease,
                  icon: const Icon(Icons.download_outlined),
                  label: const Text('Baixar Jolven da release'),
                ),
                TextButton.icon(
                  onPressed: _openJolvenArtifacts,
                  icon: const Icon(Icons.open_in_new),
                  label: const Text('Ver artefatos do CI'),
                ),
              ]),
              if (_jolvenProgress != null) ...[
                const SizedBox(height: 8),
                LinearProgressIndicator(value: _jolvenProgress),
              ],
              const SizedBox(height: 8),
              Text(_jolvenArchivePath ?? 'Nenhum pacote selecionado.',
                  maxLines: 2, overflow: TextOverflow.ellipsis),
              const SizedBox(height: 10),
              TextField(
                controller: _jolvenArchiveSha,
                autocorrect: false,
                decoration: const InputDecoration(
                  labelText: 'SHA-256 do pacote Jolven',
                  border: OutlineInputBorder(),
                  helperText: 'Obtenha o hash de fonte confiável e cole aqui.',
                ),
                onChanged: (_) => setState(() {}),
              ),
              CheckboxListTile(
                value: _confirmExperimental,
                onChanged: _working ? null : (value) =>
                    setState(() => _confirmExperimental = value == true),
                title: const Text('Entendo que a ISO não foi certificada'),
                subtitle: const Text(
                  'É apenas para testes. Não substitua seu sistema principal.',
                ),
                controlAffinity: ListTileControlAffinity.leading,
              ),
              FilledButton.icon(
                onPressed: matched && !_working &&
                    _confirmExperimental && _jolvenArchivePath != null &&
                    IsoProject.sha256Pattern.hasMatch(
                      _jolvenArchiveSha.text.trim(),
                    )
                    ? _composeExperimental : null,
                icon: const Icon(Icons.disc_full_outlined),
                label: const Text('Gerar ISO experimental'),
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

 
/// Read-only source selector. Non-Nobara ISO remastering is intentionally locked
/// until the real installer and installed-system persistence have been tested.
class _ExternalIsoInspector extends StatefulWidget {
  const _ExternalIsoInspector();

  @override
  State<_ExternalIsoInspector> createState() => _ExternalIsoInspectorState();
}

class _ExternalIsoInspectorState extends State<_ExternalIsoInspector> {
  static const _sources = <String, String>{
    'cachyos': 'CachyOS',
    'biglinux': 'BigLinux',
    'ubuntu': 'Ubuntu',
    'fedora': 'Fedora',
  };
  static const _official = <String, String>{
    'cachyos': 'https://cachyos.org/download/',
    'biglinux': 'https://www.biglinux.com.br/',
    'ubuntu': 'https://ubuntu.com/download/desktop',
    'fedora': 'https://fedoraproject.org/',
  };
  String _distribution = 'cachyos';
  String? _path;
  String? _hash;
  String? _message;
  bool _busy = false;

  Future<void> _pickIso() async {
    final selected = await openFile(
      acceptedTypeGroups: [
        const XTypeGroup(label: 'Imagem ISO', extensions: ['iso']),
      ],
    );
    if (!mounted || selected == null) return;
    setState(() {
      _path = selected.path;
      _hash = null;
      _message = null;
    });
  }

  Future<void> _inspectIso() async {
    final path = _path;
    if (path == null || _busy) return;
    setState(() {
      _busy = true;
      _hash = null;
      _message = 'Inspecionando arquivo local sem executar o conteúdo...';
    });
    try {
      final source = File(path);
      if (!await source.exists() ||
          !path.toLowerCase().endsWith('.iso') ||
          !await IsoSignature.isIso9660(source)) {
        throw const FormatException('Selecione uma ISO-9660 válida.');
      }
      final digest = await sha256.bind(source.openRead()).first;
      if (!mounted) return;
      setState(() {
        _hash = digest.toString();
        _message =
            'ISO-9660 detectada. Compare este SHA-256 com a fonte oficial. '
            'A distribuição escolhida ainda não foi validada dentro da imagem.';
      });
    } catch (error) {
      if (mounted) setState(() => _message = 'Inspeção recusada: $error');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _openOfficial() async {
    final uri = Uri.parse(_official[_distribution]!);
    if (!await launchUrl(uri, mode: LaunchMode.externalApplication) &&
        mounted) {
      setState(() => _message = 'Não foi possível abrir o site oficial.');
    }
  }

  @override
  Widget build(BuildContext context) => Card(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Outras ISOs oficiais — inspeção somente',
                  style: Theme.of(context).textTheme.titleMedium),
              const SizedBox(height: 8),
              const Text(
                'CachyOS, BigLinux, Ubuntu e Fedora já podem ser '
                'selecionados e verificados como arquivos locais. '
                'A injeção do Jolven nessas ISOs ainda não está disponível: '
                'os instaladores e layouts precisam de adaptadores próprios.',
              ),
              const SizedBox(height: 12),
              DropdownButton<String>(
                value: _distribution,
                isExpanded: true,
                items: [
                  for (final source in _sources.entries)
                    DropdownMenuItem(
                      value: source.key,
                      child: Text(source.value),
                    ),
                ],
                onChanged: _busy
                    ? null
                    : (value) {
                        if (value != null) {
                          setState(() {
                            _distribution = value;
                            _path = null;
                            _hash = null;
                            _message = null;
                          });
                        }
                      },
              ),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  OutlinedButton(
                    onPressed: _busy ? null : _openOfficial,
                    child: const Text('Abrir site oficial'),
                  ),
                  OutlinedButton(
                    onPressed: _busy ? null : _pickIso,
                    child: const Text('Selecionar ISO local'),
                  ),
                  FilledButton.tonal(
                    onPressed: _busy || _path == null ? null : _inspectIso,
                    child: const Text('Inspecionar e calcular SHA-256'),
                  ),
                ],
              ),
              if (_path != null) ...[
                const SizedBox(height: 8),
                SelectableText(_path!),
              ],
              if (_hash != null) ...[
                const SizedBox(height: 8),
                SelectableText('SHA-256: $_hash'),
              ],
              if (_message != null) ...[
                const SizedBox(height: 8),
                Text(_message!),
              ],
            ],
          ),
        ),
      );
}
