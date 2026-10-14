# Battery Studio · TLP

Versão **1.1.0**. Plugin nativo para **Omarchy Quattro (4.x)**. Um widget na barra abre um painel
em português e inglês com oito abas: **Visão geral**, **Carga**, **Perfis**, **Histórico**, **Bateria**,
**Sistema**, **Ajustes** e **Carga extra**. Cores, fonte e escala acompanham o tema ativo do Omarchy.

## Instalação completa

Ao atualizar uma instalação da versão 1.0, reinicie o shell após instalar:

    omarchy-restart-shell

Isso garante que o novo modelo compartilhado seja carregado. O histórico e
os ajustes do TLP são preservados.


1. Extraia o ZIP e abra um terminal na pasta **omarchy-battery-studio**.
2. Se ainda não usa TLP, instale os pacotes oficiais do Arch:

       sudo pacman -S --needed tlp tlp-pd
       sudo systemctl enable --now tlp.service tlp-pd.service

   O tlp-pd é opcional para este plugin, mas mantém a API de perfis usada por
   outros componentes do desktop. A instalação de TLP pode pedir a remoção
   de power-profiles-daemon, pois ele conflita com TLP.

3. Instale o plugin e seus controles:

       bash install.sh --with-controls

O instalador valida o formato Quattro, guarda uma cópia anterior caso você
reinstale, coloca o widget à direita e instala um pequeno controle autenticado
por polkit. Durante essa instalação ele verifica os recursos de carga do TLP.
Não instala pacotes, não troca seu tema e não desativa gerenciadores automaticamente.

Somente leitura, sem instalar controles de administrador:

    bash install.sh --monitor-only

**Omarchy 3.x / Waybar não usa este contrato de plugins.** O instalador recusa
esse ambiente; este pacote não é uma extensão para Waybar.

## Recursos

| Área | O que oferece |
|---|---|
| Barra | Sete formatos; clique abre, botão direito alterna e clique do meio atualiza |
| Visão geral | Estado da bateria, energia na tomada/bateria, watts, autonomia, saúde e ciclos |
| Carga | Limites de início/fim, presets 60/80/95%, valor personalizado e persistência opcional |
| Carga extra | 100% uma vez, retomar limite salvo e carga até o limite quando o hardware suporta |
| Perfis | Automático, Economia, Equilibrado e Desempenho |
| Alternância | Perfis personalizados para tomada/bateria e política sempre/smart no TLP 1.10+ |
| Histórico | Gráficos de porcentagem, potência e saúde; 1h, 6h, 24h, 7d e 30d |
| Dados | Média/pico de descarga, eventos de energia, exportação CSV, retenção 7/30/90 dias |
| Sistema | Versão/serviços TLP, conflitos, carregador, temperatura CPU e bateria, driver, governor e EPP |
| CPU | Ativar/desativar turbo por perfil, quando o driver oferece suporte |
| Diagnóstico | Relatório local sem número de série; restauração dos ajustes gerenciados |
| Hardware | BAT0/BAT1 e outras baterias expostas pelo kernel; visão combinada e seleção individual |

Os botões só ficam disponíveis quando os pré-requisitos são detectados.
Limites não são presumidos apenas pela marca do notebook: o controle verifica
novamente os recursos e os valores aceitos pelo TLP antes de cada alteração.
Lenovo com conservação fixa usa liga/desliga, em vez de um percentual fictício.

## Como interpretar as medições

- **Watts são o fluxo da bateria**, não a potência total do notebook na tomada.
  Em descarga, representam a energia saindo da bateria. Em carga, representam
  a energia entrando nela. Sem fluxo, podem ser zero mesmo com o computador ligado.
- O gráfico usa **valores positivos para descarga e negativos para carga**.
- A autonomia é uma estimativa pelo fluxo atual. Ela varia com seu trabalho.
  Não é exibida quando a medição é ausente ou a corrente é pequena demais.
- Durante a carga, o tempo estimado considera o limite máximo da bateria.
- Saúde = capacidade máxima atual / capacidade de fábrica. Ciclos e temperaturas
  aparecem somente quando o hardware informa esses dados.
- Baterias com charge_now usam a corrente para a estimativa; capacidades em Wh
  derivadas de Ah são identificadas no painel.
- Dados indisponíveis aparecem como um traço, sem valores inventados.
- Um limite abaixo da carga atual não força uma descarga.
- A opção “100% uma vez” conserva as configurações salvas. A restauração
  automática depende da versão/configuração TLP; “Retomar limite” a faz na hora.

## TLP e configurações existentes

O plugin salva seus ajustes em:

    /etc/tlp.d/99-battery-studio.conf

O TLP lê /etc/tlp.conf depois dos drop-ins; por isso esse arquivo tem
precedência. Antes de aplicar uma mudança permanente, o controle lê
tlp-stat -c e verifica os valores efetivos. Se outra configuração os sobrepõe,
o painel informa o conflito e restaura o arquivo gerenciado.

Ele detecta serviços ativos power-profiles-daemon, auto-cpufreq, tuned
e tuned-ppd. Corrija o gerenciador conflitante no sistema antes de usar os
controles. O plugin não decide qual pacote remover por você.

As consultas de bateria do TLP exigem root. O resultado de “Verificar recursos”
é guardado localmente e associado à versão do kernel, do TLP e ao modelo das
baterias. Mudanças nesses itens pedem uma nova verificação. Esse cache serve
à interface; o controle de administrador não confia nele para alterar hardware.

## Aparência e consumo do próprio plugin

Usa os tokens Color.popups, Color.accent, Color.muted, Color.urgent e Style
do Omarchy, sem substituir a barra ou abrir outro processo Quickshell.

Há um único coletor compartilhado entre monitores. Ele consulta dados a cada
3 segundos com o painel aberto e 15 segundos com o painel fechado. O histórico
é registrado uma vez por minuto. Diagnósticos mais caros têm um intervalo maior.
Ao desabilitar o último widget, a coleta para.

A janela usa até **500 × 560** pixels lógicos e reduz a altura nas abas mais curtas.
O bloco TLP e sistema conserva seus dados e sua organização. Controles avançados
de turbo ficam recolhidos até você escolher Mostrar.

Escolha português, inglês ou detecção automática na aba Ajustes. A preferência
é salva. O botão direito na barra percorre estes formatos, também salvos:

| Modo | Dados ao lado do ícone |
|---|---|
| Completo | Porcentagem e watts |
| Porcentagem | Porcentagem |
| Ícone | Nenhum texto |
| Watts | Fluxo em watts |
| Autonomia | Tempo estimado |
| Porcentagem + autonomia | Carga e tempo |
| Porcentagem + perfil | Carga e PRF/BAL/SAV |

O ícone tem níveis de vazio a cheio e indica quando a bateria está carregando.
A escolha pode ser feita diretamente em Ajustes → Formato da barra.

Mover ou abrir pelo terminal:

    omarchy bar move local.battery-studio --section right
    omarchy-shell shell summon local.battery-studio '{}'
    omarchy-shell shell hide local.battery-studio

As prévias na pasta previews são renderizações do QML com **dados simulados**
para mostrar o layout. Seus valores não representam uma medição de hardware.

## Dados, permissões e dependências

Dependências: Omarchy Quattro/Quickshell, QtQuick/QtQuick Controls, Python 3
com a biblioteca padrão, TLP e polkit/pkexec para controles.
TLP 1.8 permite os perfis tradicionais; Economia exige 1.9 e alternância
personalizada exige 1.10. O hardware/kernel determina os recursos de carga.

O monitor lê sysfs e os estados/configurações do TLP sem administrador.
O controle em /usr/local/lib/omarchy-battery-studio pertence a root.
Seu Python roda em modo isolado. Operações e argumentos são restritos; não
aceita comandos de shell, caminhos arbitrários nem arquivos de configuração do usuário.
Polkit autentica um administrador da sessão ativa e pode reutilizar a autorização
por alguns minutos. Não há regra de sudo sem senha.

O plugin não acessa a rede. Seus arquivos:

    ~/.config/omarchy/plugins/local.battery-studio/       plugin
    ~/.local/state/omarchy-battery-studio/               histórico/cache/backups
    ~/Downloads/Battery-Studio-*.csv ou *.txt             exportações
    /usr/local/lib/omarchy-battery-studio/               controle root
    /usr/share/polkit-1/actions/local.battery-studio.policy
    /etc/tlp.d/99-battery-studio.conf                    ajustes opcionais
    /var/lib/omarchy-battery-studio/original.json        limites anteriores

Respeita XDG_CONFIG_HOME, XDG_STATE_HOME e o diretório de downloads
configurado pelo sistema. Reduzir a retenção remove registros mais antigos.
Notificações críticas continuam a cargo do serviço de bateria do Omarchy.

## Verificação e limitações

O pacote inclui testes Python e testes de apresentação em JavaScript (estes
últimos rodam se Node.js estiver instalado).

    bash check.sh
    bash check.sh --qml

A opção --qml usa qmllint e os imports do Omarchy instalado.
Os testes Python usam sysfs e TLP simulados; não alteram hardware.
Consulte **VALIDACAO.md** para o que foi efetivamente executado.

Este pacote foi validado por testes de cálculos, histórico, controle, fluxo
de dados e renderização Qt. O ambiente de criação não possui seu notebook,
TLP instalado ou a sessão Omarchy real. O teste final de firmware, polkit
e integração no seu notebook ainda é necessário.

## Remoção

Remover o widget, mantendo os controles e os ajustes TLP:

    bash uninstall.sh

Remover também os controles e restaurar as configurações anteriores disponíveis:

    bash uninstall.sh --remove-controls

O histórico e os backups permanecem. TLP e tlp-pd não são desinstalados.
Se executou a remoção genérica pelo Omarchy, os arquivos de administrador
continuam separados; este desinstalador faz a limpeza completa.

## Fontes e publicação

- [Guia de desenvolvimento Omarchy Plugins](https://plugins.omarchy.org/develop.html)
- [Contrato oficial do shell](https://github.com/omacom/omarchy/blob/quattro/docs/omarchy-shell.md)
- [Documentação TLP](https://linrunner.de/tlp/index.html)
- [Comandos de controle](https://linrunner.de/tlp/usage/tlp.html)
- [Recursos por fabricante](https://linrunner.de/tlp/settings/bc-vendors.html)
- [Perfis e alternância](https://linrunner.de/tlp/settings/operation.html)
- [Unidades da classe power_supply do Linux](https://docs.kernel.org/power/power_supply_class.html)

O diretório é um projeto de plugin com manifesto na raiz. Para publicar no
catálogo, hospede os fontes em um repositório e siga o guia do marketplace.
Não foi publicado nem enviado a uma conta GitHub.
Os adaptadores de barra/painel seguem o contrato dos exemplos MIT do Omarchy.
