# Jolven ISO Builder

**Personalize uma ISO oficial do Nobara com Jolven.**

Projeto independente do [Jolven](https://github.com/zonaro/jolven) e do [Nobara](https://nobaraproject.org/). Não é uma ISO oficial ou endossada pelo Nobara.

> **Estado: M1/M2 experimental.** A interface Flutter pode consultar o catálogo oficial, baixar e conferir ISO, e exportar um projeto. Há também um protótipo de injeção/remasterização **somente pela CLI Linux**, ainda sem testes reais de boot/instalação. Não anunciar ISOs geradas por este protótipo como prontas.

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

### Injeção e remasterização EXPERIMENTAIS (Linux)

Este estágio usa `xorriso`, `unsquashfs`, `mksquashfs`, `mount`, `umount`, `e2fsck` e `resize2fs`, com permissões de root **explicitamente fornecidas** pelo operador. **Não é acessível pelo botão “Gerar ISO” do Flutter.**

Pré-condições: baixar ISO oficial do Nobara e conferir seu checksum, obter um arquivo Jolven `usr/` tar.gz de uma versão conhecida e seu SHA-256 independente, reservar no mínimo três vezes o tamanho da ISO + 2 GiB livres. O compositor **nunca** altera a ISO de entrada: gera um novo arquivo e recusa sobrescrita.

```bash
PYTHONPATH=engine python3 -m jolven_iso.cli requirements
PYTHONPATH=engine python3 -m jolven_iso.cli plan --project projeto.json
sudo env PYTHONPATH=engine python3 -m jolven_iso.cli compose \
  --project projeto.json \
  --jolven-archive /caminho/jolven-linux-x86_64.tar.gz \
  --jolven-sha256 <HASH_CONHECIDO_DO_JOLVEN> \
  --output /caminho/jolven-nobara-experimental.iso \
  --experimental --accept-unverified-provenance
```

O compositor reconhece preliminarmente `LiveOS/squashfs.img` com raiz diretamente no SquashFS ou imagem ext4 aninhada `LiveOS/rootfs.img`; recusa layouts desconhecidos. Insere o tarball validado em `/usr` e registra `/usr/share/wayland-sessions/io.github.zonaro.Jolven.GameMode.desktop` (sem trocar o login padrão). Se faltar Gamescope, o processo falha em vez de prometer uma sessão utilizável. Dependências adicionais do Jolven ainda não são instaladas automaticamente; elas precisam estar presentes no sistema-base para a sessão funcionar.

**Limitações críticas:** ainda não executamos o ciclo boot live → instalar → reiniciar nas cinco edições; a saída pode não ser inicializável nem persistir corretamente no sistema instalado. Secure Boot **não está validado**. Não distribuir a ISO produzida como release estável. O modo experimental aceita checksum informado pelo operador e **não** prova a procedência criptográfica da ISO. Builds oficiais futuros exigem catálogo autenticado, dependências, QA e assinatura conforme aplicável.

Para criar o tarball Jolven a partir de um commit conhecido sem instalar nada no computador de construção (exige toolchain Meson e dependências de desenvolvimento previamente instaladas):

```bash
bash scripts/build-jolven-archive.sh <SHA_GIT_COMPLETO_DO_JOLVEN> ./dist
```

A saída `jolven-linux-x86_64-<SHA>.tar.gz` e seu arquivo `.sha256` servem como entradas do compositor experimental. Não há download de binários arbitrários nem execução automática de scripts via curl.

As preferências de tema/cor são aplicadas como **defaults system-wide GSettings** em `/usr/share/glib-2.0/schemas/99_jolven_iso.gschema.override`, sem sobrescrever os ajustes feitos por cada usuário. Os extras solicitados pelo gerador entram num plano local de pacotes. Após instalar o Nobara no disco e obter conexão à internet, o usuário decide se quer executá-lo:

```bash
sudo /usr/libexec/jolven-iso-install-extras
```

O script consulta DNF/repositórios habilitados e só instala nomes de pacotes conhecidos e disponíveis, mediante confirmação explícita. **Não há autoinstalação no live boot.** Emuladores são aplicativos independentes; nada é embutido no Jolven. A instalação opcional automatizada via first-boot com UI e integração Flatpak continua planejada (#6).

A publicação do tarball binário Jolven também precisa ser confirmada: o endpoint `releases/latest` do projeto não retornou um artefato verificável na inspeção atual; por isso o protótipo exige um arquivo local com hash conhecido.

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

- Sempre obter a ISO pelo site oficial do Nobara e conferir o hash publicado por fonte oficial. O aplicativo busca no catálogo oficial e usa o checksum do servidor do Nobara nos downloads internos; se a ISO for local, o hash esperado pode ser preenchido pelo usuário.
- Uma ISO alterada terá **outro SHA-256** e poderá invalidar hipóteses de Secure Boot. Não anunciar suporte a Secure Boot para uma imagem modificada sem validação e assinatura legítima.
- Nunca executar uma ISO como programa, baixar scripts com privilégios ou inserir chaves secretas no perfil.
- Jogos/ROMs e emuladores continuam aplicativos independentes; Jolven não embute RetroArch.
- Edições Steam possuem autologin peculiar: preservar configuração original e adicionar opção Jolven somente quando testada.

## Roadmap

Veja [issues](https://github.com/zonaro/jolven-iso/issues) e [.agents/roadmap.md](.agents/roadmap.md). O trabalho é intencionalmente separado do repositório principal Jolven.
