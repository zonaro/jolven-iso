# Jolven ISO Builder

**Personalize uma ISO oficial do Nobara com Jolven.**

Projeto independente do [Jolven](https://github.com/zonaro/jolven) e do [Nobara](https://nobaraproject.org/). Não é uma ISO oficial ou endossada pelo Nobara.

> **Estado: M1 em desenvolvimento.** Esta versão oferece interface Flutter, seleção local de ISO, cálculo e conferência de SHA-256 e exportação de um projeto JSON. **Ainda NÃO injeta Jolven, NÃO gera uma ISO modificada e NÃO instala aplicativos extras.** Essas operações só serão habilitadas após implementação e testes de inicialização e instalação.

## Escopo

- Entrada: ISO oficial Nobara 44, uma de **Official, GNOME, KDE, Steam-HTPC ou Steam-Handheld**; versão futura exige adaptação e novos testes.
- Saída planejada: ISO derivada da ISO oficial, com Jolven instalado system-wide e **Jolven Session** selecionável no gerenciador de login sem remover as outras sessões.
- Extras planejados: Sunshine, RetroArch, UZDoom, Eden, Cemu e OpenRGB mediante disponibilidade comprovada no DNF/Flatpak e consentimento no first boot.
- Configuração: preferências não sensíveis, tema e cor. Tokens, senhas e chaves **não são incorporados à ISO**; configuração segura ocorre após login.
- Interface multiplataforma **Flutter** (Linux, Windows e macOS). O remasterizador, quando implementado, exigirá ambiente Linux (nativo, WSL2 ou VM).
- Distribuição do app: **AppImage no Linux** e **ZIP portátil + instalador EXE no Windows x64**, produzidos pelo CI. macOS permanece planejado.

## Desenvolvimento

Requisitos: Flutter estável, Dart, Git. No Linux, dependências de build GTK/Clang/CMake/Ninja. O repositório contém código portável; gere o runner local da plataforma no primeiro checkout:

```bash
flutter create --platforms=linux,windows,macos --project-name jolven_iso .
flutter pub get
flutter analyze
flutter test
flutter run -d linux
```

O comando acima cria os diretórios de runner que ainda não são versionados; o gerador Flutter oficial é a fonte deles. No Windows/macOS escolha o dispositivo correspondente.

### Motor de pré-verificação (Python 3.10+)

```bash
PYTHONPATH=engine python3 -m jolven_iso.cli inspect --iso /caminho/para/nobara.iso
PYTHONPATH=engine python3 -m jolven_iso.cli verify --iso /caminho/para/nobara.iso --sha256 HASH_OFICIAL
PYTHONPATH=engine python3 -m jolven_iso.cli plan --project /caminho/projeto.json
python3 -m unittest discover -s engine/tests
```

O comando `plan` **apenas valida e descreve a operação**; não modifica imagens.

### AppImage

O pipeline em `.github/workflows/ci.yml` executa testes, compila Flutter Linux e empacota usando `scripts/package-appimage.sh`. O AppImage é o formato pretendido de distribuição e será publicado automaticamente em releases marcadas com `v*` **quando o workflow passar**. A portabilidade e a execução real em múltiplas distros ainda precisam de validação; não há release pronta garantida neste estágio.

```bash
flutter build linux --release
bash scripts/package-appimage.sh
```

### Windows x64

O GitHub Actions compila a interface Flutter no runner Windows e gera dois pacotes em cada build:

- `Jolven-ISO-Builder-VERSAO-Windows-x64-Portable.zip`: extraia tudo e execute `jolven_iso.exe` na pasta. O EXE **não funciona isoladamente**: mantenha as DLLs e `data/` juntos.
- `Jolven-ISO-Builder-VERSAO-Windows-x64-Setup.exe`: instalador Inno Setup por usuário, com atalho e desinstalador.

Ambos incluem `.sha256`. Em um push para `main`, os arquivos são artefatos do [GitHub Actions](https://github.com/zonaro/jolven-iso/actions); em uma tag `v*`, serão anexados à release **se todos os jobs passarem**.

Para compilar localmente, use Windows com Flutter, Visual Studio C++ Desktop e Inno Setup 6 instalado:

```powershell
flutter create --platforms=windows --project-name jolven_iso .
flutter pub get
flutter analyze
flutter test
flutter build windows --release
./scripts/package-windows.ps1
```

Pacotes ainda **não são assinados digitalmente**: o Windows pode exibir alertas SmartScreen. O aplicativo requer o runtime Visual C++ adequado; o instalador atual não o provisiona automaticamente. Uma release estável exige testes reais de instalação e inicialização em Windows 10/11. A interface Windows **ainda não gera ISO**: futuramente o motor de remasterização precisará de Linux via WSL2 ou VM (issue #10).

## Segurança e limitações

- Sempre obter a ISO pelo site oficial do Nobara e conferir o hash publicado por fonte oficial. O aplicativo **não conhece magicamente o SHA oficial**: o campo é preenchido pelo usuário nesta fase.
- Uma ISO alterada terá **outro SHA-256** e poderá invalidar hipóteses de Secure Boot. Não anunciar suporte a Secure Boot para uma imagem modificada sem validação e assinatura legítima.
- Nunca executar uma ISO como programa, baixar scripts com privilégios ou inserir chaves secretas no perfil.
- Jogos/ROMs e emuladores continuam aplicativos independentes; Jolven não embute RetroArch.
- Edições Steam possuem autologin peculiar: preservar configuração original e adicionar opção Jolven somente quando testada.

## Roadmap

Veja [issues](https://github.com/zonaro/jolven-iso/issues) e [.agents/roadmap.md](.agents/roadmap.md). O trabalho é intencionalmente separado do repositório principal Jolven.
