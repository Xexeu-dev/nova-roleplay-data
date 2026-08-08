# Nova Roleplay - dados do jogo

Este repositorio contem apenas o manifesto publico dos dados. Os arquivos grandes ficam
nos assets do GitHub Releases, evitando colocar binarios pesados no historico do Git.

## Fluxo

- Uma instalacao nova baixa `nova-data-base-v1.zip` uma unica vez.
- Quem ja possui a data da versao 1.7 apenas registra a base local, sem baixar novamente.
- Atualizacoes futuras sao publicadas como patches contendo somente arquivos alterados.
- O APK valida tamanho e SHA-256 antes de aplicar qualquer pacote.
- `XEXEU_LOG.TXT`, configuracoes e demais arquivos locais nunca entram nos patches.

O manifesto publico e `manifest.json`. Nao altere hashes manualmente: use os scripts da
pasta `scripts`.

## Publicar a base inicial

```powershell
.\scripts\build-base.ps1 -InputZip 'C:\caminho\nova_data_padrao.zip'
git add manifest.json
git commit -m 'Atualiza manifesto da base'
git push
gh release create data-v1 .\release-assets\nova-data-base-v1.zip --title 'Data v1'
```

## Publicar apenas arquivos alterados

Informe a pasta raiz completa da data. O script compara tamanho e SHA-256, monta um ZIP
somente com arquivos novos/alterados, registra remocoes e avanca uma versao:

```powershell
.\scripts\build-patch.ps1 -DataDirectory 'C:\caminho\com.novaroleplay.game'
git add manifest.json
git commit -m 'Publica patch da data v2'
git push
gh release create data-v2 .\release-assets\nova-data-patch-v2.zip --title 'Data v2'
```
