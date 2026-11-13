# Bandeja, Notepad e configuração — 0.3.5

## Iniciar e reconhecer a versão

Abra KMAO Bot pelo menu Iniciar da instalação. O cabeçalho da bandeja mostra
`KMAO 0.3.5` para esse código; o ícone pode estar na área de ícones ocultos.
O build Windows usa `Kmao.Bot.exe`, com descrição KMAO Bot e identidade `Kmao.Bot`.
O PowerShell 5.1 e o código da interface/automação rodam nesse processo.

A interface começa cinza até a validação. Com configuração válida e foco
confirmado, habilita Running e digita no seu Notepad maximizado:

```text
KMAO BOT is running...
```

A mensagem entra caractere por caractere, usando os parâmetros `STARTUP_*`.
Atividade durante a abertura pode manter o bot em pausa; a mensagem continua do
ponto em que parou ao retomar. O cabeçalho do documento faz parte da identificação
de propriedade e deve permanecer enquanto o bot estiver usando esse documento.

## Menu

| Item | Comportamento |
| --- | --- |
| Run | Solicita leitura/validação das opções, maximiza/ativa o Notepad próprio e habilita Running após confirmar o foco. Cria outro documento se o anterior foi fechado/substituído. |
| Stop | Pausa manualmente, mantém o documento aberto e só retoma com Run. |
| Configurações | Pausa manualmente e abre o arquivo unificado no Notepad. Salve e selecione Run. |
| Logs | Abre um console PowerShell com as últimas 50 linhas do log do bot e acompanhamento contínuo (`Get-Content -Wait`). |
| Open logs folder | Abre a pasta `logs` do perfil no Explorador de Arquivos. |
| About | Abre o repositório do projeto no navegador. |
| Exit | Encerra o bot, remove o ícone e descarta seu documento sem salvar. |

Run aparece quando pausado; Stop, quando habilitado. Duplo clique solicita a mesma
alternância, com validação antes de Running. Fechar o console de Logs não encerra
o bot. Falhas ao abrir editor, logs ou navegador são registradas no log do bot.

## Pausa e retomada

Verde indica Running habilitado, inclusive durante esperas; não significa que
haja digitação naquele instante. Mouse/teclado externos e perda de foco/aba
cancelam o ciclo e deixam o ícone cinza. Entrada marcada do próprio bot não conta
como retorno do usuário.

Após `IDLE_TIME_THRESHOLD` segundos de inatividade, o bot relê a configuração,
considera o novo limite, maximiza/ativa seu Notepad e confirma o foco antes de
ficar verde. Atividade durante a transição, Stop manual, encerramento solicitado,
configuração inválida ou recusa de foco impedem a retomada. Documento fechado ou
substituído exige Run; não é recriado automaticamente por inatividade.

Os ciclos usam um intervalo aleatório adicional. Com os padrões atuais, são
60 segundos de inatividade e mais 30 a 239 segundos por ciclo. A mensagem inicial
é separada desses ciclos e pode começar imediatamente após a abertura/Run.

## Configuração

O arquivo editado pelo menu é:

```text
%USERPROFILE%\.kmao-bot\config\application.conf
```

Ele contém 31 parâmetros do bot/logger, com comentário em português na linha
anterior de cada variável. Os valores padrão vêm de
[config/application.conf.example](config/application.conf.example).

1. Abra Configurações; o bot entra em pausa manual para não interromper a edição.
2. Edite e salve com Ctrl+S.
3. Selecione Run. Toda a configuração é relida e validada antes de ficar verde.

A releitura também ocorre na inicialização e na retomada por inatividade. Durante
um ciclo, os valores em memória permanecem coerentes. Um arquivo inválido não
substitui parcialmente esse conjunto e não traz o Notepad à frente para iniciar
uma interação. O bot continua cinza e registra o motivo em `bot-*.log`; corrija
o arquivo e use Run. Erros repetidos iguais não são registrados a cada polling.

O arquivo aceita `NOME=inteiro` sem aspas, comentários `#` e linhas vazias. Campos
omitidos usam o padrão; nomes desconhecidos/duplicados e valores fora dos limites
são rejeitados. Nos pares aleatórios, mínimo deve ser menor que máximo, e máximo
é exclusivo. Por exemplo, `MIN_CLICKS=1` e `MAX_CLICKS=4` resultam em 1, 2 ou 3.

Os parâmetros atuais e padrões são:

| Parâmetro | Padrão | Unidade e regra |
| --- | --- | --- |
| `MIN_INTERVAL` | 30 | Tempo mínimo entre ciclos de interação, em segundos (1 a 86400). |
| `MAX_INTERVAL` | 240 | Limite superior exclusivo entre ciclos, em segundos; deve ser maior que MIN_INTERVAL. |
| `RECT_WIDTH` | 400 | Largura máxima da área central de cliques no editor do bot, em pixels (1 a 32768). |
| `RECT_HEIGHT` | 200 | Altura máxima da área central de cliques no editor do bot, em pixels (1 a 32768). |
| `MIN_CLICKS` | 1 | Quantidade mínima de cliques por ciclo (1 a 100). |
| `MAX_CLICKS` | 4 | Limite superior exclusivo de cliques; deve ser maior que MIN_CLICKS e no máximo 100. |
| `TYPING_CHANCE` | 70 | Chance de digitar uma frase após os cliques, em porcentagem (0 a 100). |
| `IDLE_TIME_THRESHOLD` | 60 | Tempo sem atividade do usuário antes da retomada automática, em segundos (1 a 86400). |
| `MIN_CHAR_DELAY` | 40 | Pausa mínima entre caracteres das frases, em milissegundos (0 a 60000). |
| `MAX_CHAR_DELAY` | 200 | Limite superior exclusivo entre caracteres, em ms; maior que MIN_CHAR_DELAY, até 60000. |
| `HESITATION_CHANCE` | 8 | Chance de acrescentar uma pausa de hesitação entre caracteres, em porcentagem (0 a 100). |
| `MIN_HESITATION` | 300 | Pausa mínima adicional de hesitação, em milissegundos (0 a 60000). |
| `MAX_HESITATION` | 800 | Limite superior exclusivo da hesitação, em ms; maior que MIN_HESITATION, até 60000. |
| `SPACE_MIN_DELAY` | 30 | Pausa mínima ao digitar um espaço, em milissegundos (0 a 60000). |
| `SPACE_MAX_DELAY` | 120 | Limite superior exclusivo da pausa em espaços, em ms; maior que SPACE_MIN_DELAY, até 60000. |
| `PUNCT_MIN_DELAY` | 50 | Pausa mínima adicional após pontuação, em milissegundos (0 a 60000). |
| `PUNCT_MAX_DELAY` | 150 | Limite superior exclusivo após pontuação, em ms; maior que PUNCT_MIN_DELAY, até 60000. |
| `CURSOR_MIN_DELAY` | 80 | Pausa mínima entre mover o cursor e clicar, em milissegundos (0 a 60000). |
| `CURSOR_MAX_DELAY` | 200 | Limite superior exclusivo antes do clique, em ms; maior que CURSOR_MIN_DELAY, até 60000. |
| `MULTI_CLICK_MIN_DELAY` | 200 | Pausa mínima entre cliques do mesmo ciclo, em milissegundos (0 a 60000). |
| `MULTI_CLICK_MAX_DELAY` | 500 | Limite superior exclusivo entre cliques, em ms; maior que MULTI_CLICK_MIN_DELAY, até 60000. |
| `PRE_TYPING_MIN_DELAY` | 500 | Espera mínima antes de começar uma frase, em milissegundos (0 a 60000). |
| `PRE_TYPING_MAX_DELAY` | 1500 | Limite superior exclusivo antes da frase, em ms; maior que PRE_TYPING_MIN_DELAY, até 60000. |
| `PRE_ENTER_MIN_DELAY` | 200 | Pausa mínima antes da quebra de linha, em milissegundos (0 a 60000). |
| `PRE_ENTER_MAX_DELAY` | 600 | Limite superior exclusivo antes da quebra de linha, em ms; maior que PRE_ENTER_MIN_DELAY, até 60000. |
| `FINAL_MIN_DELAY` | 200 | Pausa mínima ao terminar um ciclo, em milissegundos (0 a 60000). |
| `FINAL_MAX_DELAY` | 800 | Limite superior exclusivo ao terminar o ciclo, em ms; maior que FINAL_MIN_DELAY, até 60000. |
| `STARTUP_MIN_CHAR_DELAY` | 45 | Pausa mínima entre letras da mensagem inicial, em milissegundos (0 a 60000). |
| `STARTUP_MAX_CHAR_DELAY` | 110 | Limite superior exclusivo da mensagem inicial, em ms; maior que STARTUP_MIN_CHAR_DELAY, até 60000. |
| `MOUSE_SAMPLING_INTERVAL` | 200 | Intervalo mínimo entre amostras de movimento do mouse no logger, em ms (1 a 60000). |
| `RECORDING_DURATION_MINUTES` | 480 | Duração máxima de gravação do logger, em minutos (0 a 525600); 0 grava até encerrar. |

Tempos internos de polling, prontidão, encerramento e escrita do logger são
limites da implementação/protocolo; não são nomes adicionais aceitos no arquivo.
O logger aplica suas duas opções somente ao iniciar uma nova gravação.

### Importação e recuperação

Se `application.conf` ainda não existir, o primeiro componente que iniciar cria o
arquivo completo com os valores explícitos de `config/bot.conf` e
`config/kmao.conf` já existentes no perfil. Os originais são preservados; valores
não definidos usam os padrões. Um legado inválido impede essa criação e produz
um erro de inicialização, sem modificar o original.

Um arquivo unificado existente não é substituído. Depois da importação, edite
somente ele. Na recuperação para uma versão anterior à 0.3.5, a versão antiga
usa seus arquivos legados; alterações do unificado não são copiadas de volta.
Dados antigos que ainda estão no checkout precisam ser copiados para o perfil
antes dessa primeira importação, conforme o [README](README.md).

As frases continuam em `%USERPROFILE%\.kmao-bot\phrases.txt`, uma por linha UTF-8.
Elas são lidas ao iniciar o bot, não a cada Run; reinicie após alterar esse arquivo.
A janela de configuração é um documento do usuário, não o alvo descartável do bot.

## Documento próprio e segurança do alvo

Uma janela recém-aberta, vazia e com título sem nome reconhecido é usada
diretamente. Se houver notas anteriores/restauradas, o bot usa os controles de
automação para criar seu documento separado. Outras janelas/abas são preservadas;
podem continuar visíveis, e a preferência de restauração de sessões não é alterada.
Idiomas/controles não reconhecidos seguem a criação isolada ou geram diagnóstico.

A escrita Unicode é enviada diretamente ao controle do documento próprio, sem
teclas globais nem Enter para outros programas. Os cliques também são endereçados
a esse editor; o movimento do cursor é marcado como entrada do bot. Antes das
ações e durante as esperas, são verificados atividade, sessão, foco e área do editor.
Os cliques são limitados ao retângulo central configurado e ao editor visível.

Ao fechar o documento, ele permanece fechado até Run. Ao salvar manualmente,
abrir outro arquivo na aba ou remover a identificação, o bot procura reconhecer
a perda de propriedade, pausa e preserva o documento. Não use a janela descartável
para anotações pessoais nem dependa dessa verificação como mecanismo de salvamento.

Exit e a parada cooperativa limpam o texto próprio e fecham somente sua aba/janela.
Não matam processos Notepad. O X do Notepad pode salvar a sessão antes de o bot
perceber; término forçado, falha de automação e energia interrompida podem impedir
a limpeza. Prefira Exit para o descarte normal.

## Nome no Windows e execução de desenvolvimento

O host próprio tem descrição/produto KMAO Bot e a identidade dos atalhos existentes.
A mudança chega pelo ZIP, sem recriar atalhos. O Windows pode manter uma entrada
antiga de Windows PowerShell no cache da bandeja. O KMAO não apaga esse cache nem
altera preferências de outros aplicativos. Veja a
[documentação da área de notificação](https://learn.microsoft.com/en-us/windows/win32/shell/notification-area).

`dev.ps1` direto ou export simples sem host ainda rodam dentro do PowerShell e
podem ser identificados assim pelo Windows. Use o build completo e o lançador
instalado para verificar a identidade própria. O console de Logs continua separado.

## Testes e limites

```bash
./scripts/kmao.sh test
./scripts/kmao.sh desktop-test
```

A suíte inclui configuração/migração, rejeição de valores inválidos, reentrada em
Running, bandeja, host e coordenação com atualizador. O comando interativo abre e
descarta documentos próprios. O teste nativo usa perfil e eventos privados; o
legado de processo completo exige que outra instância do bot esteja encerrada.

O bot requer desktop interativo desbloqueado, Windows PowerShell 5.1 e automação
do Notepad disponível. Diálogos iniciais, políticas do Windows, versões/idiomas e
restauração de abas precisam de validação na máquina alvo. Não é possível garantir
foco ou limpeza após falha do processo/sistema. O [roadmap](ROADMAP.md) registra
as verificações pendentes.
