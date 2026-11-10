# Pin do código-fonte do Jolven para construir tarballs

O gerador obtém a ISO de uma fonte oficial Nobara, porém o Jolven é
produzido separadamente do repositório `zonaro/jolven`. Não usar branch
`main` flutuante no artefato: a saída precisa ser reproduzível
e rastreável a um commit explícito.

- Commit usado pelo CI de artefato: `dbac3872f85983bea2c85e6d4c69f78f0ccf2265`
- Workflow: `.github/workflows/jolven-artifact.yml`
- Produção local: `bash scripts/build-jolven-archive.sh SHA ./dist`
- Validação: `PYTHONPATH=engine python3 -m unittest discover -s engine/tests`
- O arquivo resultante inclui a árvore `usr/`, e um
  `.sha256` correspondente que deve ser copiado na GUI.

Não substituir uma release do Jolven por arquivos obtidos de fontes
desconhecidas. O artefato do Actions ainda precisa ser testado em uma
ISO Nobara real; um build tarball bem-sucedido não garante que seus
módulos Python e dependências executam dentro de todas as edições.

## Compatibilidade Python

A imagem base atual é **Nobara 44**, então o workflow de artefatos usa contêiner **Fedora 44** (não Fedora 45), para evitar que módulos Jolven sejam instalados num `python3.X/site-packages` diferente do Python do alvo. O injetor valida o diretório de versão Python no rootfs do Nobara **antes de escrever**, e recusa mismatch. Quando o Nobara atualizar de versão-base, é obrigatório ajustar o ambiente de construção e renovar o pin com testes reais.
