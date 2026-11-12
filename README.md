# KMAO Bot (Keep-me Always On Bot)

O KMAO Bot reúne dois scripts PowerShell para Windows: um bot que simula atividade de mouse e teclado e um gravador de eventos para análise de uso do computador.

O projeto usa scripts PowerShell e uma biblioteca C# para as APIs do Windows. Há empacotamento portátil, instalador por usuário e atualização com confirmação ao iniciar. Não há interface principal nem integração com a bandeja do sistema.

Consulte o [guia de instalação e publicação](INSTALLATION.md) para gerar o instalador, configurar a assinatura e preparar as Releases. Nenhuma versão é publicada automaticamente.

## Requisitos

- Windows com Windows PowerShell 5.1 e .NET Framework 4.6 ou posterior; Windows 11 é a plataforma alvo.
- Assemblies .NET `System.Windows.Forms` e `System.Drawing` e APIs nativas `user32.dll` e `kernel32.dll`.
- Permissão para executar scripts PowerShell. Os lançadores `.bat` usam `-ExecutionPolicy Bypass` para o processo iniciado.

O instalador exige Windows PowerShell 5.1 disponível e instalação por usuário. A biblioteca C# é compilada em memória por `Add-Type`; não é necessário instalar um compilador separado. Os scripts de aplicação não funcionam nativamente em Linux ou macOS.

## Copiar para outro computador ou diretório

Os scripts dependem das pastas `lib/`, `config/` e do modelo `phrases.txt` distribuídos junto deles. Copiar somente `dev.ps1` e `dev.bat` deixa o pacote incompleto. A pasta do aplicativo no perfil guarda os dados do usuário; o código e os modelos continuam necessários na pasta de execução.

Na raiz do repositório, gere o pacote portátil:

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\Export-Kmao.ps1
```

O comando cria `dist/kmao-portable/` e `dist/kmao-portable.zip`. Extraia **todo o conteúdo** do ZIP para o diretório de uso, preservando as subpastas. Por exemplo:

```text
C:\BACKUP_GUTO\dev\
├── dev.bat
├── dev.ps1
├── Start-Kmao.ps1
├── Launch-Kmao.ps1
├── Apply-KmaoUpdate.ps1
├── VERSION
├── activity_logger.ps1
├── init_recording.bat
├── phrases.txt
├── lib\
│   ├── Kmao.Common.ps1
│   ├── Kmao.Windows.cs
│   └── Kmao.Update.ps1
└── config\
    ├── bot.conf.example
    └── kmao.conf.example
```

O pacote também inclui documentação, licença e testes. Depois, execute `dev.bat` ou `init_recording.bat` no diretório de destino. O modo portátil não consulta atualizações; os atalhos criados pelo instalador usam o ciclo gerenciado. Não é necessário copiar `.git`, configurações pessoais, gravações ou logs.

Para gerar outro pacote, informe uma pasta nova com `-Destination 'C:\caminho\pacote-novo'`. O exportador não substitui uma pasta ou ZIP existente.

## Pasta do aplicativo

Configurações, frases, gravações e logs ficam no perfil do usuário, independentemente da pasta de execução:

```text
%USERPROFILE%\.kmao-bot\
├── config\
│   ├── bot.conf                 # Configuração do bot
│   └── kmao.conf                # Configuração do logger
├── phrases.txt                  # Uma frase por linha
├── data\                        # Gravações CSV
└── logs\                        # Logs operacionais por execução
```

A pasta do perfil é obtida pela API `.NET Environment.GetFolderPath(UserProfile)`. Na primeira execução de cada componente, seus arquivos são copiados dos exemplos do repositório. Arquivos existentes na pasta do aplicativo são preservados.

Configurações antigas em `config/kmao.conf` e gravações antigas em `data/` do repositório não são migradas automaticamente. Para reaproveitar uma configuração anterior, copie-a para a nova pasta antes de executar. Personalizações antigas feitas diretamente em `dev.ps1` devem ser transferidas para `bot.conf`. Depois da cópia inicial, edite os arquivos do perfil; alterações nos exemplos do repositório não substituem suas configurações.

## Bot de automação

Inicie por `dev.bat` ou execute o script PowerShell. Use o caminho do repositório, que pode ser diferente do exemplo:

```powershell
& 'C:\caminho\kmao-bot\dev.bat'
```

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File 'C:\caminho\kmao-bot\dev.ps1'
```

### Comportamento

- Aguarda pelo menos 60 segundos de inatividade e depois um intervalo aleatório de 30 a 239 segundos.
- Move o cursor dentro de um retângulo de 400 × 200 pixels no centro da tela principal e executa de 1 a 3 cliques por ciclo.
- Tem 70% de chance de digitar uma frase aleatória, com pausas entre caracteres, e pressionar `Enter` ao final.
- Monitora mouse e teclado em uma thread própria. Os eventos enviados pelo bot são marcados para não serem confundidos com atividade externa.
- Cancela o ciclo ao detectar atividade externa, inclusive durante a espera e a digitação. As esperas verificam o cancelamento a cada até 25 ms; cada nova ação também verifica o estado antes de enviar entrada.
- Verifica a janela em foco. Após um clique do bot, a referência é atualizada para a janela ativada; mudanças posteriores cancelam o restante do ciclo.
- Envia pressionar/soltar juntos em cada clique ou tecla para evitar deixar botões presos ao cancelar.

A detecção depende da entrega de eventos pelo Windows; ela não garante ausência absoluta de uma ação que já esteja sendo enviada no instante da retomada do usuário. Uma frase parcialmente digitada permanece no aplicativo de destino, mas o restante e o `Enter` são cancelados quando a retomada é detectada.

### Configuração

Edite `%USERPROFILE%\.kmao-bot\config\bot.conf`. Todas as opções estão em [config/bot.conf.example](config/bot.conf.example), incluindo intervalos, área de cliques, quantidade de cliques, chance de digitação e pausas.

Os limites máximos dos intervalos aleatórios são exclusivos. Cada mínimo deve ser menor que seu máximo. Chances aceitam 0 a 100; intervalos e limite de inatividade aceitam 1 a 86400 segundos, pausas aceitam 0 a 60000 ms e limites de cliques aceitam 1 a 100. A área configurada deve caber na tela principal.

Edite `%USERPROFILE%\.kmao-bot\phrases.txt` para definir uma frase por linha. Linhas vazias são ignoradas; um arquivo sem frases é tratado como erro. As frases são lidas como UTF-8 e enviadas como caracteres Unicode, sem interpretar caracteres especiais como comandos `SendKeys`.

O bot ainda clica e digita na janela atingida pelos cliques; não há uma lista de aplicativos permitidos. Use `Ctrl+C` para interromper.

## Activity Logger

Inicie por `init_recording.bat` ou diretamente:

```powershell
& 'C:\caminho\kmao-bot\init_recording.bat'
```

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File 'C:\caminho\kmao-bot\activity_logger.ps1'
```

Ambas as opções inicializam a pasta do aplicativo e a configuração. Use `Ctrl+C` para interromper ou configure uma duração máxima.

### Configuração

Edite `%USERPROFILE%\.kmao-bot\config\kmao.conf`:

```ini
# Intervalo mínimo entre registros de movimento (1..60000 ms)
MOUSE_SAMPLING_INTERVAL=200

# Duração máxima (0..525600 minutos); 0 = até interrupção manual
RECORDING_DURATION_MINUTES=480
```

### Captura e gravação

Os hooks são instalados em uma thread C# com loop de mensagens do Windows. Seus callbacks colocam eventos em uma fila; a escrita em disco ocorre no script PowerShell. A remoção dos hooks está em `finally`, inclusive para falha parcial de instalação.

A fila é limitada a 100000 eventos. Se ela lotar, a execução sinaliza erro e encerra a captura. Os eventos são consumidos em lotes de até 1000, e o arquivo é descarregado a cada 100 registros escritos ou 10 segundos. O encerramento tenta parar a captura, gravar os eventos restantes e fechar o arquivo, com tratamento independente das falhas de limpeza.

Os CSVs são criados em `data/` da pasta do aplicativo. O nome inclui data, hora, segundos, milissegundos, PID e um identificador de sessão para evitar colisões. O formato é:

```csv
t,e,x,y,k
1727621415,mc,1920,540,
1727621416,mm,1925,545,
1727621417,kd,,,A
1727621418,ku,,,A
```

| Campo | Conteúdo |
| --- | --- |
| `t` | Timestamp Unix em segundos |
| `e` | `mc`: clique; `mm`: movimento; `sc`: scroll; `kd`: tecla pressionada; `ku`: tecla liberada |
| `x`, `y` | Coordenadas do mouse; vazias para teclado |
| `k` | Nome da tecla virtual; vazio para mouse |

São registrados cliques dos botões esquerdo, direito, central e auxiliares, scroll vertical/horizontal e eventos de teclado comuns e de sistema (`WM_SYSKEYDOWN`/`WM_SYSKEYUP`). Movimentos são registrados apenas quando há mudança de posição e o intervalo mínimo é atingido.

O logger também captura entradas sintetizadas por software, inclusive pelo bot quando ambos estão em execução. Não registra títulos de janelas ou nomes de processos. Os registros de clique não distinguem os botões, e os de scroll não incluem direção ou intensidade.

## Configuração, erros e logs

- Os arquivos `.conf` aceitam `NOME=inteiro`, sem aspas, linhas vazias e comentários iniciados por `#`.
- Chaves desconhecidas, duplicadas, valores inválidos, fora dos limites ou pares mínimo/máximo inconsistentes impedem a inicialização.
- Falhas de configuração, APIs do Windows e escrita são apresentadas no terminal e registradas em `logs/`, com timestamp, nível e detalhes da exceção quando disponíveis.
- Os logs operacionais não contêm frases digitadas nem os eventos capturados; esses eventos ficam somente nos CSVs.
- Falhas tratadas produzem código de saída 1, preservado pelos lançadores `.bat`. O encerramento usa `finally` para liberar recursos; fechamento forçado do processo pode impedir essa limpeza e perder dados ainda em buffer.
- Logs e gravações não possuem rotação nem exclusão automática; acompanhe o espaço usado na pasta do aplicativo.

## Validação e trabalho pendente

Os testes portáveis verificam sintaxe PowerShell, compilação C#, tamanho da estrutura nativa de entrada, caminhos, preservação de configuração, validação numérica, logs e cancelamento de ciclos com um monitor simulado. Também exercitam o ciclo do logger, incluindo falhas de inicialização, captura e limpeza, gravação final e fechamento do CSV:

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\tests\Test-Core.ps1
```

Há também um teste de integração para desktop Windows. Ele move o cursor em um pixel, sem clicar ou digitar; deixe mouse e teclado sem uso durante a execução:

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\tests\Test-Windows.ps1
```

A validação nativa no Windows continua pendente neste ambiente de desenvolvimento Linux. Também devem ser verificados manualmente a gravação por duração, a interrupção com `Ctrl+C`, falhas de permissão/escrita, a retomada real de atividade durante a digitação e a troca de janela. O Windows pode remover silenciosamente hooks que excedam seu tempo limite; não há recuperação automática implementada.

A [especificação original do Activity Logger](ACTIVITY_LOGGER_SPEC.md) é histórica e inclui caminhos e propostas anteriores. Este README descreve o funcionamento atual. Não há configurações de execução ou depuração do VS Code versionadas.

## Instalação e atualização

O instalador usa `%LOCALAPPDATA%\Programs\KMAO Bot` e preserva os dados em
`%USERPROFILE%\.kmao-bot`. Os atalhos consultam as prereleases do GitHub ao iniciar,
pedem confirmação antes de atualizar e continuam usando a versão instalada se a
consulta falhar ou o usuário recusar. Pacotes são autenticados por assinatura RSA,
verificados arquivo por arquivo e preparados em diretórios por versão.

A troca aguarda o encerramento cooperativo dos componentes e mantém a versão
anterior para recuperação. O [guia de instalação](INSTALLATION.md) descreve a
configuração das chaves, geração do `.exe`, workflow manual e publicação para
convidados. A validação do instalador e do fluxo nativo no Windows ainda está
pendente neste ambiente Linux. O [roadmap](ROADMAP.md) registra o estado e os
critérios de aceitação.

## Estrutura do repositório

```text
kmao-bot/
├── README.md
├── ROADMAP.md                   # Decisões e validação pendente
├── INSTALLATION.md              # Instalação, assinatura e publicação
├── VERSION / CHANGELOG.md
├── Start-Kmao.ps1 / Launch-Kmao.ps1 / Apply-KmaoUpdate.ps1
├── scripts/                     # Chaves e build de release
├── installer/                   # Projeto Inno Setup
├── .github/workflows/           # Validação e build manual
├── ACTIVITY_LOGGER_SPEC.md
├── LICENSE
├── Export-Kmao.ps1              # Geração do pacote portátil
├── dev.bat / dev.ps1
├── init_recording.bat / activity_logger.ps1
├── phrases.txt                  # Modelo inicial de frases
├── config/
│   ├── bot.conf.example
│   └── kmao.conf.example
├── lib/
│   ├── Kmao.Common.ps1          # Caminhos, configuração e logs
│   ├── Kmao.Windows.cs          # Hooks, fila e envio de entrada
│   └── Kmao.Update.ps1           # Autenticidade, extração e troca de versão
└── tests/
    ├── Test-Core.ps1
    ├── Test-Windows.ps1
    ├── Test-Updates.ps1
    └── Test-Lifecycle.ps1
```

## Privacidade

O Activity Logger registra eventos de teclado, incluindo nomes das teclas pressionadas e liberadas, e pode permitir a reconstrução de informações sensíveis. Utilize somente em dispositivos próprios ou com autorização das pessoas envolvidas.

Eventos, frases, configurações e gravações não são enviados para serviços externos. A instalação gerenciada faz consultas HTTPS ao GitHub para verificar e baixar atualizações. Os arquivos de uso ficam na pasta do aplicativo no perfil do usuário.

## Licença

O repositório inclui a licença [GNU General Public License v3.0](LICENSE).
