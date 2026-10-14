# Validação · Battery Studio 1.1.0

## Executado

| Verificação | Resultado |
|---|---|
| 42 testes Python com sysfs/TLP simulados | Passaram |
| Validador oficial omarchy-plugin-validate, obtido do código do Omarchy | Passou |
| Compilação dos fontes Python | Passou |
| Sintaxe dos três scripts Bash | Passou |
| XML da política polkit | Válido |
| Coletor real sem hardware de bateria | Fluxo JSON, consulta de histórico, retenção, erro de entrada e encerramento passaram |
| Dashboard QML em Qt 6.12 | 64 renderizações sem erros de QML; português e inglês |
| Apresentação JavaScript | Sete modos, onze níveis, unidades e traduções passaram |
| Preferências | Migração da versão anterior, cliques rápidos, idioma, formato e retenção persistidos |
| Card TLP e sistema | Preservado, alterando somente os textos por tradução |
| Paletas | Escura, clara e verde |
| Geometria | Largura normal e largura reduzida com fonte ampliada |
| Adaptadores QML de barra/painel com interfaces simuladas do Omarchy/Quickshell | Abrir, fechar, trocar painel, alternar os sete formatos com botão direito e mudar idioma passaram |
| qmllint com as interfaces simuladas | Código de saída 0; avisos sobre propriedades dinâmicas do Loader e dos objetos do host |

Os testes verificam unidades de energia/corrente/tensão, autonomia até o limite,
sensores ausentes, saúde sem capacidade de fábrica, USB-C, baterias múltiplas,
capacidades TLP por fabricante, versões/status antigos e atuais, retenção,
exportação, tratamento de parâmetros e conflitos.

Também cobrem recusa de comandos/configurações não autorizados, links simbólicos,
precedência de configuração, reversão quando o firmware rejeita um ajuste e
preservação do plugin anterior quando uma reinstalação falha.

## Ainda depende do notebook

Este ambiente não contém uma sessão Omarchy Quattro, TLP instalado nem a bateria
do usuário. Não foi feita uma alteração real no firmware ou nas configurações
do notebook. A autenticação polkit, os limites aceitos pelo hardware, os comandos
TLP e os imports da versão instalada do shell precisam ser conferidos nele.

O painel foi executado no Qt; as interfaces específicas de Omarchy/Quickshell
foram simuladas nos testes de adaptação. Isso não equivale a uma execução completa
na sessão Omarchy.

## Conferência no sistema de destino

1. Instale com a opção --with-controls e abra o widget.
2. Na aba Carga, confira os recursos e a leitura atual do limite.
3. Aplique um limite suportado e compare a leitura atual do painel.
4. Teste Automático, Equilibrado e Desempenho; Economia exige TLP 1.9+.
5. Conecte/remova o carregador e confira o estado e a política automática.
6. Confira que o gráfico começa a acumular dados reais por minuto.
7. Execute o check.sh --qml no diretório extraído.

Essas etapas conferem a integração no hardware; as prévias do pacote usam
dados simulados e não são evidência de autonomia ou consumo do notebook.

## English summary

42 Python tests passed. Native Qt layouts were rendered 64 times across both languages, three palettes and a smaller screen/font configuration. Bar-mode cycles, language changes, data flow and persistence passed. The TLP/system card was preserved.

Omarchy/Quickshell-specific interfaces were simulated in adapter tests. Firmware, real TLP commands and authentication must still be verified on the target notebook. These results do not claim a real-device test.
