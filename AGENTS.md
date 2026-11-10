# Instruções para agentes

- Código simples e testável. Flutter/Dart para UI, engine de remasterização isolado e invocável por CLI.
- **Nunca alegar que uma ISO foi modificada/testada sem evidência.** M1 prepara, verifica e exporta somente o projeto.
- Manter a entrada uma ISO oficial do Nobara; não substituir o processo por uma distro derivada reconstruída sem solicitação.
- Não invocar comandos de root/sudo automaticamente; executar operações perigosas somente mediante confirmação e isolamento.
- Nenhum segredo (tokens, senhas, credenciais) em perfil JSON, ISO, logs, artefatos ou workflows.
- Verificar a disponibilidade de pacotes extras no sistema de pacotes específico da edição; não usar downloads arbitrários como fallback silencioso.
- Testar as cinco edições (Official, GNOME, KDE, Steam-HTPC, Steam-Handheld), respeitando logins automáticos e uso de GDM/SDDM.
- Preferir dependências mínimas, documentação pt-BR, análise estática e testes automatizados.
- Distribuir Linux em AppImage; Windows x64 em ZIP portátil e instalador EXE, ambos no CI, com checksums. macOS futuro permanece aplicativo nativo.
- Antes de concluir issue, comentar o commit, evidências dos testes e limitações remanescentes.
- Leia .agents/architecture.md e .agents/roadmap.md antes de alterar o motor de imagens.

- O comando `compose` é experimental: exige `--experimental` e `--accept-unverified-provenance`. Nunca habilite no Flutter sem boot e instalação validada em VM e dispositivo real.
- Verifique a presença e a integridade de tarball local do Jolven; a API `releases/latest` pode estar indisponível. Não invente versão ou artefato.

- O perfil de tema usa somente GSettings defaults; não preconfigure senhas/chaves em ISO, nem force alteração dos usuários após o login.
- Extras opcionalmente solicitados usam um script pós-instalação invocado manualmente com autenticação; não habilitar serviço silencioso de instalação no boot.
