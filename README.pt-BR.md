# PowerKit

Mantido por **Elias Sabat**.

O projeto agora se chama **PowerKit** e o repositório é [`sabb4th/omarchy-powerkit`](https://github.com/sabb4th/omarchy-powerkit). Ele controla perfis de energia e cuidados com a bateria usando Rust, batctl e power-profiles-daemon, com interface inteiramente em inglês.

![Painel PowerKit com leituras simuladas](preview.png)

## Instalar

Instale no Omarchy Quattro com um comando:

```bash
omarchy plugin add https://github.com/sabb4th/omarchy-powerkit.git --enable
```

No primeiro uso, se faltar alguma dependência, uma janela de terminal mostra o que será instalado e pede confirmação. O PowerKit usa o gerenciador do Omarchy para instalar os pacotes necessários, incluindo `batctl-tui` pelo AUR. Não é necessário executar `install.sh` separadamente. O mesmo preparo está integrado nesse instalador.

Com sua confirmação, o preparo também ativa power-profiles-daemon se necessário, mas recusa trocar enquanto TLP, auto-cpufreq ou tuned estiver ativo. Não altera limites da bateria ou perfis de energia. Se cancelar ou ocorrer uma falha, execute `bash scripts/setup.sh` dentro da pasta do plugin para tentar novamente; a janela não se repete continuamente. O selo de instalação do marketplace depende da revisão dos mantenedores.

O backend compila uma vez no cache do usuário; Cargo pode precisar baixar as dependências travadas no lockfile. Atualizações de código são recompiladas automaticamente. Releases incluem um binário pronto e checksums para quem prefere instalar sem compilador.

## Usar

Clique esquerdo abre o painel; direito alterna a aparência da barra; meio atualiza. Capacity e Design foram substituídos por controles de governador e preferência de energia da CPU, com valores ativos e opções suportadas. No driver Intel, selecione Powersave para ajustar a preferência quando Performance a bloquear. As alterações são temporárias, valem para todas as políticas de CPU e podem ser substituídas pelo perfil de energia.

O painel não mostra mais janelas ao passar o mouse. O espaço do raio só aparece durante o carregamento, com expansão suave, e as mudanças de carga, formato e destaque usam transições curtas, sem animação contínua em repouso.

O rodapé mostra a saúde da bateria com um pequeno ícone preenchido proporcionalmente e a porcentagem na cor de destaque do tema. O clique do meio na barra continua atualizando os dados.

O painel oferece perfis Saver → Balanced → Performance, modos Auto / Inhibit charge / Force discharge, indicadores da bateria e limites em uma seção expansível. O raio de carregamento fica à esquerda do ícone, sem preenchimento cinza.

Os modos valem para a bateria selecionada; limites do batctl valem para todas. Force discharge usa a bateria mesmo conectado à tomada; Auto encerra essa descarga forçada. O plugin não salva nem reaplica o modo: a persistência cobre somente os limites. Alterações de carga solicitam autenticação do sistema.

```bash
omarchy plugin update io.github.sabb4th.powerkit
omarchy plugin remove io.github.sabb4th.powerkit
```

## Migrar a versão antiga

Para substituir Battery Studio preservando a posição da barra, execute no checkout:

```bash
bash install.sh --migrate
# Se já compilado:
bash install.sh --migrate --prebuilt target/release/powerkit
```

`--migrate` autoriza a alteração do ID antigo para `io.github.sabb4th.powerkit` com backup de `shell.json` e do plugin antigo. Dados históricos, helper TLP e configurações externas não são apagados. A desinstalação não muda bateria, serviços ou perfis.

Consulte [README.md](README.md) para dependências, arquivos persistentes, permissões, instalação por release e desenvolvimento. O [documento de segurança](SECURITY.md) descreve os comandos privilegiados.
