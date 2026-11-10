# Roadmap — Jolven ISO Builder

- **M1 (agora):** #2 Flutter, modelo e testes; #3 ISO/sha catálogo oficial; #8 UI; #9 AppImage; #12 segurança e documentação; #13 build Windows x64 (ZIP portátil + instalador EXE).
- **M2:** #4 remasterização confiável de ISO oficial; #5 instalar Jolven system-wide e Jolven Session em todas as edições; #10 backend Linux e adaptação Windows/macOS.
- **M3:** #6 opcionais via DNF/Flatpak e first-boot; #7 integração segura de perfis e segredos pós-login.
- **M4:** #11 boot/install e drivers; fechar cobertura de #8, #9, #10; publicar ISO apenas depois de QA.

### Princípios de escopo

M1 **não** contém remasterização pronta. A função principal é conferir ISO, escolher opções e produzir um plano serializado. O compose só será liberado quando for compatível com a estrutura real da ISO oficial e existirem provas de instalação.

### Implementado (parcial, experimental)

- #3: parser do catálogo oficial, download retomável, checksum oficial via HTTPS; ainda faltam teste de download em rede real, persistência de catálogo e UX avançada.
- #4/#5: CLI de remasterização e extração segura de pacote Jolven, exige root na CLI tradicional, mas oferece alternativa rootless experimental via libguestfs, tarball local e opção `--experimental`; testes unitários não substituem QA da ISO real.
- #8: consulta/download pela interface Flutter; geração de ISO experimental agora disponível na UI apenas sem root e mediante confirmação; continua sem certificação de boot/instalação.

- #6: catálogo DNF restrito e instalador pós-instalação manual com confirmação, sem instalação automática no primeiro boot. Pendente validar nomes de pacotes por edição e adicionar Fluxo First-boot UI/Flatpak.
- #7: defaults reais de tema/acento via GSettings configurados na composição; export/import de configurações avançadas e secrets via keyring em primeira execução continuam pendentes.
- #5: fallback de construção de tarball Jolven por SHA exato de commit enquanto não houver release binária verificável.

- #4: adicionado teste smoke da transformação de ISO sintética no GitHub Actions; validação com ISO oficial, UEFI/BIOS, Secure Boot e instalação no disco continua pendente.

- #10: bridge Flutter/Python para diagnósticos, planos e composição experimental Linux/WSL2 usando libguestfs/FUSE; macOS ZIP da UI, mas VM ainda ausente.
- #11: testes existentes são sintéticos; habilitar validação oficial por edição e obter evidências reais de boot e instalação antes de completar a milestone.

- #6: adicionado first-run consentido GNOME/KDE via Zenity/KDialog e opções DNF/Flathub, sem executar em live ISO nem alterar autologin Steam; ainda falta QA em Nobara real e melhores explicações de disponibilidade.
