# QA manual — Nobara + Jolven Session

**Esta matriz é obrigatória antes de chamar qualquer ISO de pronta.** Os testes
sintéticos do CI confirmam somente reempacotamento e metadados. Não testam
desempenho, inicialização real, GPUs NVIDIA nem instalação pelo Calamares.

## Preparar ambiente descartável

1. Obtenha a ISO Nobara oficial e confira SHA-256 no site do Nobara.
2. No Jolven ISO Builder selecione a edição correspondente e confira o hash.
3. Prepare o arquivo Jolven `usr/` tar.gz de um commit fixo (ou release confiável)
   e seu SHA-256. Nunca incorpore tokens ou senhas pessoais.
4. Gere a ISO experimental. Execute:
   `PYTHONPATH=engine python3 -m jolven_iso.cli audit --source original.iso --output modificada.iso`
5. Inicie a VM isolada com:
   `bash scripts/qa-nobara-vm.sh /caminho/modificada.iso /caminho/vm-testes`

O script cria **disco qcow2 virtual e esparso de 40 GiB**, nunca usa SSD físico.
Faça boot, instale no disco virtual e reinicie sem o boot pela mídia ISO.

## Matriz por edição

| Edição | Sessão original | O que confirmar |
| --- | --- | --- |
| Official | KDE/SDDM personalizado | Jolven no seletor; KDE intacto |
| GNOME | GDM | Jolven selecionável; GNOME e Polkit intactos |
| KDE | SDDM | Jolven selecionável; Plasma intacto |
| Steam-HTPC | Steam/autologin | Autologin preservado; Jolven selecionável quando o greeter aparecer |
| Steam-Handheld | Steam/autologin | Autologin preservado; controles e tela portátil |

- [ ] ISO personalizada dá boot em UEFI (e BIOS, quando suportado)
- [ ] Instalador funciona e instala no disco virtual
- [ ] SO instalado reinicia sem a ISO
- [ ] GNOME/KDE/Steam original continua funcionando
- [ ] Jolven Session aparece no gerenciador compatível
- [ ] Sessão Gamescope inicia com controle, áudio e tela cheia
- [ ] Sair do Jolven retorna ao gerenciador de login
- [ ] Jogos Steam/Proton e emuladores externos iniciam corretamente
- [ ] Tema/cor predefinidos e perfil de usuário preservado
- [ ] Setup DNF/Flatpak exige consentimento e não roda no live ISO
- [ ] Não há tokens/senhas no conteúdo da imagem
- [ ] Atualizar o Nobara mantém a sessão

## Hardware real e Secure Boot

VM não substitui testes com GTX 1660 Ti e AMD real: validar Gamescope, Vulkan,
VRR, OBS/NVENC, suspensão, controles e `journalctl --user`. Usar segundo SSD
ou backup, nunca substituir a máquina principal sem validação.

Secure Boot só deve ser marcado suportado após cadeia de assinatura legítima
e testes reais. Nunca usar chaves privadas do Nobara sem autorização.

## Evidências e acompanhamento

Comentar no issue #11 cada edição: versão exata, SHA-256 original e modificado,
commit Jolven, arquitetura, GPU, screenshots do boot/greeter e logs de erro.

**Sem evidências, o issue #11 permanece aberto.** AppImage, Windows EXE/ZIP e
macOS ZIP podem ser previews do gerador com avisos, não ISOs certificadas.
