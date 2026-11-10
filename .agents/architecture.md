# Arquitetura

## Separação de responsabilidades

1. **Flutter**: estado do projeto, seleção local de ISO, edição Nobara, preferências, hash e exportação de manifesto sem segredos.
2. **Domínio**: `IsoProject` versionado, lista de edições e extras. Nenhuma dependência do processo de construção.
3. **Engine CLI (Python)**: comandos `inspect`, `verify` e `plan`; sem efeitos colaterais sobre imagens. Futuramente `compose` em Linux, isolado e com aprovação.
4. **Perfis por edição**: GDM/SDDM no GNOME/KDE/Official e autologin nas variantes Steam. Descobrir características da ISO, não presumir caminhos.
5. **AppImage**: empacotamento do bundle Flutter Linux. FUSE e bibliotecas do host precisam de testes reais.
6. **Windows x64**: runner Flutter nativo empacotado em ZIP com DLLs/data e instalador EXE por usuário via Inno Setup. Ainda sem assinatura digital; requer validação real. Não confundir distribuição da interface com execução do motor Linux de remasterização.

## Pipeline planejado (NÃO IMPLEMENTADO)

ISO oficial -> checksum/autenticidade -> detectar layout -> extrair filesystem em sandbox -> instalar pacote Jolven verificado e dependências -> registrar entrada Jolven Session -> incluir first-boot extras e perfil sem segredos -> reempacotar preservando bootstrap/instalador -> auditar ISO saída -> boot/instalação VM.

Não basta inserir arquivos no live ISO: a instalação no disco deve herdá-los. Nunca modificar arquivos assinados de boot sem avaliar Secure Boot. O processo não deve tornar a ISO base não confiável.

## Contrato do projeto v1

`schema_version` = 1, `distribution` = "nobara", `edition`, `source_iso`, `source_sha256`, `expected_sha256`, `jolven_session` = true, `extras` = [], `appearance` = {theme, accent_hex}.

O manifest é um registro de intenção; não é uma ISO. `source_sha256` é hash calculado localmente; `expected_sha256` vem do hash oficial preenchido e verificado. A validação atual não confirma a procedência da URL: esta etapa requer catálogo oficial confiável (issue #3).

## Segurança

Chaves de APIs e senhas são proibidas no JSON. O setup após login deverá usar keyring e confirmação. Evitar credenciais em logs, arquivos temporários e parâmetros de linha de comando. A versão oficial do Jolven recusa `ID=nobara` no instalador de usuário; integração futura requer pacote system-wide adaptado, nunca rodar o install.sh sob root como atalho.

Licenças: MIT apenas para este gerador, não substitui as licenças de Nobara, Jolven ou software incluído.

## M2 experimental (não certificado)

- `engine/jolven_iso/overlay.py`: checa SHA-256 do tarball Jolven, rejeita caminhos fora de `usr/`, links, arquivos especiais e permite apenas entradas regulares; registra Jolven Session sem modificar o greeter original.
- `engine/jolven_iso/remaster.py`: com root explícito, clona `LiveOS/squashfs.img`, edita o rootfs em cópia e tenta reproduzir boot metadata via `xorriso -boot_image any replay`.
- Não existe evidência de que ISOs reais das cinco edições resultam instaláveis; não habilitar na interface nem entregar como estável. Faltam dependências completas via DNF, first-boot opcional, compatibilidade Secure Boot e QA físico/VM.
- A origem de ISO local é verificada por hash fornecido; apenas downloads iniciados pelo catálogo oficial possuem checksum recuperado da página oficial. HTTPS não equivale a verificação de assinatura criptográfica.

## Perfis e extras (protótipos M3)

- `profile.py`: instala `99_jolven_iso.gschema.override` em `/usr/share/glib-2.0/schemas` e recompila schemas com GLib. Baseia-se em `theme-slug` e `theme-accent-custom` reais do Jolven; não altera usuário existente nem grava segredos. Em `Custom`, mantém tema Jolven com cor personalizada.
- `extras.py`: prepara plano local de pacotes selecionados e script de consentimento explícito após instalar a distro. O instalador verifica a disponibilidade com `dnf repoquery` antes de instalar; não executa nada automaticamente no live boot. Flatpak e firstboot UI ainda faltam.
- `scripts/build-jolven-archive.sh`: gera tarball de commit exato do Jolven, com SHA-256, sem sudo ou instalação host. Depende de toolchain e dependências Meson já preparadas.

## Entrega do motor por plataforma

- AppImage: motor Python incluído como dados em `usr/share/jolven-iso/engine`; não há auto-elevação nem alteração no host.
- Windows: motor Python incluído em `engine/` dentro do bundle portátil/instalador. Interface nativa disponível, mas o compose requer um backend Linux/WSL2/VM, ainda sem integração de execução pela UI.

## Rootless e interface experimental

- `EngineBridge` invoca CLI Python por `Process.start` sem shell; Windows usa `wsl.exe --exec` e `wslpath` para mapear caminhos. Diagnóstico e plano são read-only. `compose` exige confirmação de riscos e libguestfs FUSE sem root; não aceita `pkexec/sudo` na interface.
- Para rootfs.ext4 aninhado, o compositor usa `guestmount --format=raw` e `guestunmount`, aguardando o encerramento do processo FUSE. A CLI mantém fallback root loop mount explícito; squashfs direto não recebe operação rootless.
- No WSL2, usar `/tmp` para área de trabalho e copiar o resultado para `/mnt/c/...` de forma controlada e com arquivo temporário de destino. Não confiar que WSL2 possui FUSE; validar requisitos antes da execução.
- Mac `.app` em ZIP com assinatura ad hoc e backend incluído apenas como código fonte: integração VM, notarização e QA pendentes.

## Setup inicial opcional, consentimento e emuladores

- `extras.py` gera plano JSON permitido, helper root exclusivo DNF/Flatpak, desktop launcher e autostart GNOME/KDE. Primeiro login verifica que não está no live ISO e abre Zenity/KDialog quando disponível, sem pacotes instalados sem consentimento explícito.
- O usuário escolhe o que instalar, Polkit solicita autenticação apenas após confirmação; se o pacote não existir no DNF/Flathub configurados, mostra indisponível. Não existe auto-adição de repositórios.
- Steam-HTPC/Handheld preservam autologin e não recebem o autostart GNOME/KDE; configuração manual pelo desktop, pois o overlay não pressupõe um compositor/greeter específico.
