# Instruções para agentes

- Código simples e testável. Flutter/Dart para UI, engine de remasterização isolado e invocável por CLI.
- **Nunca alegar que uma ISO foi modificada/testada sem evidência.** O protótipo permite composição experimental, mas não há imagem Nobara real validada.
- Manter a entrada uma ISO oficial do Nobara; não substituir o processo por uma distro derivada reconstruída sem solicitação.
- Não invocar comandos de root/sudo automaticamente; executar operações perigosas somente mediante confirmação e isolamento.
- Nenhum segredo (tokens, senhas, credenciais) em perfil JSON, ISO, logs, artefatos ou workflows.
- Verificar a disponibilidade de pacotes extras no sistema de pacotes específico da edição; não usar downloads arbitrários como fallback silencioso.
- Testar as cinco edições (Official, GNOME, KDE, Steam-HTPC, Steam-Handheld), respeitando logins automáticos e uso de GDM/SDDM.
- Preferir dependências mínimas, documentação pt-BR, análise estática e testes automatizados.
- Distribuir Linux em AppImage; Windows x64 em ZIP portátil e instalador EXE, ambos no CI, com checksums. macOS é distribuído como .app em ZIP sem notarização (UI experimental).
- Antes de concluir issue, comentar o commit, evidências dos testes e limitações remanescentes.
- Leia .agents/architecture.md e .agents/roadmap.md antes de alterar o motor de imagens.

- O comando `compose` é experimental: exige `--experimental` e `--accept-unverified-provenance`. Flutter pode acionar apenas o modo não-privilegiado com confirmação explícita e aviso de não certificação. Jamais tratá-lo como release estável sem boot/instalação real.
- Verifique a presença e a integridade de tarball local do Jolven; a API `releases/latest` pode estar indisponível. Não invente versão ou artefato.

- O perfil de tema usa somente GSettings defaults; não preconfigure senhas/chaves em ISO, nem force alteração dos usuários após o login.
- Extras opcionalmente solicitados usam um script pós-instalação invocado manualmente com autenticação; não habilitar serviço silencioso de instalação no boot.

- O modo rootless usa guestmount/guestunmount FUSE; não executa código do AppImage como root. WSL2 requer FUSE e workspace Linux, e a compatibilidade real ainda precisa ser testada.
- Validar os três builds Linux AppImage/Windows EXE+ZIP/macOS .app ZIP no CI; confirmar execução real antes de release estável.
