# Activity Logger — especificação técnica atual

Referência: código **0.3.5**. Este documento descreve a implementação atual em
[activity_logger.ps1](activity_logger.ps1), [lib/Kmao.Windows.cs](lib/Kmao.Windows.cs)
e nas bibliotecas compartilhadas. Substitui o desenho inicial de 2025.

## Finalidade e execução

O logger captura eventos globais de mouse e teclado na sessão de desktop Windows
e grava CSVs locais. Funciona separadamente do bot, com uma instância por sessão.
Use KMAO Bot - Gravar atividade no menu Iniciar ou, no pacote completo,
`init_recording.bat`/`activity_logger.ps1` em Windows PowerShell 5.1.

O uso instalado passa pelo lançador, que pode oferecer atualização. O logger não
tem interface própria de bandeja. Ctrl+C, a duração configurada e o pedido de
parada do atualizador encerram a gravação. Os lançadores preservam o código de
saída do script.

## Configuração

O arquivo atual é `%USERPROFILE%\.kmao-bot\config\application.conf`, comum ao bot
e ao logger. O template é [config/application.conf.example](config/application.conf.example).
Cada variável tem comentário em português na linha anterior.

| Parâmetro do logger | Padrão | Intervalo válido | Efeito |
| --- | --- | --- | --- |
| `MOUSE_SAMPLING_INTERVAL` | 200 | 1 a 60000 ms | Intervalo mínimo entre amostras de movimento |
| `RECORDING_DURATION_MINUTES` | 480 | 0 a 525600 min | Duração máxima; 0 grava até interrupção |

O arquivo é lido e validado ao iniciar uma gravação. Editá-lo não reconfigura uma
sessão em curso: encerre e inicie o logger para aplicar. Como a configuração é
unificada, campos inválidos de qualquer grupo impedem o início da gravação.

Na primeira criação, valores explícitos dos antigos `config/bot.conf` e
`config/kmao.conf` no perfil são importados e os originais permanecem intactos.
Um `application.conf` existente é preservado. O arquivo aceita inteiros sem aspas,
comentários `#` e linhas vazias; rejeita chaves desconhecidas/duplicadas, valores
fora dos limites e pares mínimo/máximo inconsistentes. Uma importação de legado
inválido falha com diagnóstico, sem modificar o original.

A abertura de Configurações na bandeja pausa somente o bot, não uma gravação já
em andamento. Veja [TRAY_BOT.md](TRAY_BOT.md#configuração) para o arquivo completo.

## Captura nativa

`Kmao.WindowsInput` instala os hooks em uma thread C# dedicada, com processamento
de mensagens do Windows. Os callbacks não executam scriptblocks PowerShell nem
escrevem no disco: colocam registros em uma fila concorrente.

Os dois hooks são instalados dentro da região protegida por `try/finally`. Uma
falha parcial também tenta remover o hook instalado. A captura sinaliza falhas
de instalação, callbacks, fila e limpeza; não trata indiscriminadamente qualquer
exceção como interrupção do usuário.

São observados:

- Cliques esquerdo, direito, central e auxiliares, sem distinguir o botão no CSV.
- Scroll vertical/horizontal, sem direção ou intensidade no registro.
- Movimento, somente quando a posição mudou e o intervalo mínimo foi atingido.
- Teclas pressionadas/liberadas, incluindo mensagens de sistema
  `WM_SYSKEYDOWN`/`WM_SYSKEYUP`; sem amostragem de teclado.

A entrada sintetizada também pode ser capturada. Movimentos marcados do bot são
registráveis; seus cliques e texto enviados diretamente ao editor do Notepad não
geram eventos globais de mouse/teclado. A marca exclui entrada própria do cálculo
de inatividade do bot, não da captura do logger.

## Fila, escrita e encerramento

A fila comporta até **100000 eventos**. Ao exceder o limite, registra falha e
encerra para evitar perda silenciosa. O consumidor PowerShell drena lotes de até
1000 e verifica a saúde do produtor entre as esperas. O polling de escrita é de
25 ms; o flush ocorre após 100 registros pendentes ou quando 10 segundos passaram
até a próxima passagem pelo consumidor. Esses são limites internos, não opções
adicionais aceitas no arquivo de configuração.

Os nomes numéricos das teclas nativas são convertidos para `System.Windows.Forms.Keys`
antes da escrita. O CSV usa UTF-8 sem BOM, cabeçalho e compartilhamento de leitura.
`FileMode.CreateNew` impede sobrescrever uma gravação existente.

No encerramento, o script tenta, de forma independente:

1. Parar o produtor e remover hooks.
2. Consumir os registros restantes, mesmo após o produtor parar.
3. Descarregar e fechar o arquivo.
4. Liberar os eventos/mutexes da sessão.

Falhas de limpeza são registradas e tornam a saída um erro. O término forçado do
processo, queda de energia ou erro de disco pode impedir essa sequência e perder
eventos ainda em memória. Não há recuperação automática de hooks removidos pelo
Windows nem garantia de gravação após falha de escrita.

## Diretórios e nomes

```text
%USERPROFILE%\.kmao-bot\
├── config\application.conf
├── data\2026-11-12-10-30-45-123-4567-<identificador>-recording.csv
└── logs\logger-<data-hora>-<pid>-<identificador>.log
```

O nome do CSV usa `yyyy-MM-dd-HH-mm-ss-fff`, PID e identificador de sessão.
A data/hora do nome é local; o timestamp de cada evento é Unix em segundos UTC.
O diretório é obtido pelo perfil do Windows, independentemente do diretório de
execução. Não são criados CSVs no checkout por padrão.

Cada execução cria um arquivo próprio; não há rotação por tamanho, retenção,
compressão de gravações antigas ou limpeza automática. Estimativas de volume
precisam de medição no uso real, pois dependem dos eventos e da amostragem.

## Formato CSV

```csv
t,e,x,y,k
1727621415,mc,1920,540,
1727621416,mm,1925,545,
1727621417,kd,,,A
1727621418,ku,,,A
```

| Campo | Conteúdo |
| --- | --- |
| `t` | Timestamp Unix, segundos UTC |
| `e` | `mc`: clique; `mm`: movimento; `sc`: scroll; `kd`: tecla pressionada; `ku`: tecla liberada |
| `x`, `y` | Coordenadas de tela do mouse; vazias para teclado |
| `k` | Nome da tecla virtual; vazio para mouse |

O arquivo não informa títulos de janela, nomes de processos, texto do documento,
botão clicado ou intensidade do scroll. O nome de tecla não equivale a texto
Unicode final nem registra composição/idioma como uma mensagem textual.

## Logs, prontidão e privacidade

Diagnósticos operacionais ficam em `logs/`, separados dos eventos. Incluem nível,
timestamp, exceções e contagem final de registros, sem duplicar o CSV. A prontidão
para o atualizador é sinalizada após configuração, hooks e arquivo abertos.
O protocolo aguarda até 20 segundos pela limpeza ao atualizar.

Eventos de teclado podem permitir reconstruir informações sensíveis. Use o
logger apenas com autorização adequada. O KMAO mantém os eventos localmente;
o lançador instalado consulta o GitHub para atualizações, mas não envia CSVs.

## Validação

`Test-Core.ps1` exercita a escrita/limpeza reais com produtor simulado, incluindo
falhas parciais. `Test-Configuration.ps1` cobre importação e validação;
`Test-Lifecycle.ps1` cobre eventos/mutexes. `Test-Windows.ps1` exige desktop
interativo e move o cursor em um pixel para verificar hooks e cancelamento.

Testes prolongados, Ctrl+C real, gravação durante atualização, falhas de disco e
políticas de segurança em outras máquinas continuam no [roadmap](ROADMAP.md).
Análise estatística, painéis de produtividade e recuperação de hooks não fazem
parte da implementação atual.
