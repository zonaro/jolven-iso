# Arquitetura

## Separação de responsabilidades

1. **Flutter**: estado do projeto, seleção local de ISO, edição Nobara, preferências, hash e exportação de manifesto sem segredos.
2. **Domínio**: `IsoProject` versionado, lista de edições e extras. Nenhuma dependência do processo de construção.
3. **Engine CLI (Python)**: comandos `inspect`, `verify` e `plan`; sem efeitos colaterais sobre imagens. Futuramente `compose` em Linux, isolado e com aprovação.
4. **Perfis por edição**: GDM/SDDM no GNOME/KDE/Official e autologin nas variantes Steam. Descobrir características da ISO, não presumir caminhos.
5. **AppImage**: empacotamento do bundle Flutter Linux. FUSE e bibliotecas do host precisam de testes reais.

## Pipeline planejado (NÃO IMPLEMENTADO)

ISO oficial -> checksum/autenticidade -> detectar layout -> extrair filesystem em sandbox -> instalar pacote Jolven verificado e dependências -> registrar entrada Jolven Session -> incluir first-boot extras e perfil sem segredos -> reempacotar preservando bootstrap/instalador -> auditar ISO saída -> boot/instalação VM.

Não basta inserir arquivos no live ISO: a instalação no disco deve herdá-los. Nunca modificar arquivos assinados de boot sem avaliar Secure Boot. O processo não deve tornar a ISO base não confiável.

## Contrato do projeto v1

`schema_version` = 1, `distribution` = "nobara", `edition`, `source_iso`, `source_sha256`, `expected_sha256`, `jolven_session` = true, `extras` = [], `appearance` = {theme, accent_hex}.

O manifest é um registro de intenção; não é uma ISO. `source_sha256` é hash calculado localmente; `expected_sha256` vem do hash oficial preenchido e verificado. A validação atual não confirma a procedência da URL: esta etapa requer catálogo oficial confiável (issue #3).

## Segurança

Chaves de APIs e senhas são proibidas no JSON. O setup após login deverá usar keyring e confirmação. Evitar credenciais em logs, arquivos temporários e parâmetros de linha de comando. A versão oficial do Jolven recusa `ID=nobara` no instalador de usuário; integração futura requer pacote system-wide adaptado, nunca rodar o install.sh sob root como atalho.

Licenças: MIT apenas para este gerador, não substitui as licenças de Nobara, Jolven ou software incluído.
