# Roadmap — Jolven ISO Builder

- **M1 (agora):** #2 Flutter, modelo e testes; #3 ISO/sha catálogo oficial; #8 UI; #9 AppImage; #12 segurança e documentação; #13 build Windows x64 (ZIP portátil + instalador EXE).
- **M2:** #4 remasterização confiável de ISO oficial; #5 instalar Jolven system-wide e Jolven Session em todas as edições; #10 backend Linux e adaptação Windows/macOS.
- **M3:** #6 opcionais via DNF/Flatpak e first-boot; #7 integração segura de perfis e segredos pós-login.
- **M4:** #11 boot/install e drivers; fechar cobertura de #8, #9, #10; publicar ISO apenas depois de QA.

### Princípios de escopo

M1 **não** contém remasterização pronta. A função principal é conferir ISO, escolher opções e produzir um plano serializado. O compose só será liberado quando for compatível com a estrutura real da ISO oficial e existirem provas de instalação.

### Implementado (parcial, experimental)

- #3: parser do catálogo oficial, download retomável, checksum oficial via HTTPS; ainda faltam teste de download em rede real, persistência de catálogo e UX avançada.
- #4/#5: CLI de remasterização e extração segura de pacote Jolven, **exige root**, tarball local e opção `--experimental`; testes unitários não substituem QA da ISO real.
- #8: consulta/download pela interface Flutter; geração de ISO experimental deliberadamente mantida fora da UI.
