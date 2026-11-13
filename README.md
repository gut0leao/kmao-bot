# KMAO Bot (Keep-me Always On Bot)

O KMAO Bot reúne dois scripts PowerShell para Windows: um bot que simula atividade de mouse e teclado e um gravador de eventos para análise de uso do computador.

O projeto usa scripts PowerShell e bibliotecas C# para as APIs do Windows. O bot
roda pela bandeja, cria seu próprio Notepad maximizado e interage somente com esse
documento. Há empacotamento portátil, instalador por usuário e atualização com
confirmação ao iniciar. O [guia da bandeja e do Notepad](TRAY_BOT.md) descreve os
controles Run, Stop, Logs, About e Exit. Desde a 0.3.4, o build inclui o processo
próprio `Kmao.Bot.exe`, identificado como KMAO Bot pelo Windows.

**Distribuição Windows:** a próxima versão está em preparação para assinatura
Authenticode. Os instaladores publicados podem ser bloqueados pelo Smart App Control.
Veja [assinatura e pendências de emissão](CODE_SIGNING.md).

**Atualização da 0.2.1/0.3.0:** instale o instalador 0.3.1 manualmente uma vez para
corrigir a consulta de novas versões. Configurações, frases e gravações são preservadas.

Consulte o [guia de instalação e publicação](INSTALLATION.md) para gerar o instalador, configurar a assinatura e preparar as Releases. Nenhuma versão é publicada automaticamente.

## Requisitos

- Windows com Windows PowerShell 5.1 e .NET Framework 4.6 ou posterior; Windows 11 é a plataforma alvo.
- Assemblies .NET `System.Windows.Forms` e `System.Drawing` e APIs nativas `user32.dll` e `kernel32.dll`.
- Permissão para executar scripts PowerShell. Os lançadores `.bat` usam `-ExecutionPolicy Bypass` para o processo iniciado.

O instalador exige Windows PowerShell 5.1 disponível e instalação por usuário. A biblioteca C# é compilada em memória por `Add-Type`; não é necessário instalar um compilador separado. Os scripts de aplicação não funcionam nativamente em Linux ou macOS.

## Desenvolver no WSL

Mantenha o repositório no Linux e execute os comandos abaixo pelo terminal WSL.
Eles chamam o PowerShell do Windows e convertem os caminhos automaticamente:

```bash
./scripts/kmao.sh doctor
./scripts/kmao.sh test
./scripts/kmao.sh keygen  # Somente na primeira preparação da assinatura
./scripts/kmao.sh build --allow-unsigned --output ./dist/dev-teste # Desenvolvimento apenas
```

O Inno Setup 6 precisa estar instalado no Windows para gerar o `.exe`. Os arquivos
ficam em `dist/release/` no repositório WSL; as chaves padrão ficam no perfil do
usuário Windows, fora do repositório. Veja o [fluxo WSL completo](INSTALLATION.md#desenvolvimento-no-wsl).

Após gerar os pacotes, fazer commit e push, publique a versão definida em `VERSION`:

```bash
./scripts/kmao.sh publish            # Publica como prerelease
./scripts/kmao.sh publish --dry-run  # Confere sem acessar o GitHub
```

O comando encontra os pacotes em `dist/release-VERSION` ou `dist/release`. Veja as
[opções de publicação](INSTALLATION.md#publicar-pelo-wsl-com-um-comando).

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
    ├── application.conf.example
    ├── bot.conf.example           # Legado
    └── kmao.conf.example          # Legado
```

O pacote também inclui documentação, licença e testes. Depois, execute `dev.bat` ou `init_recording.bat` no diretório de destino. O modo portátil não consulta atualizações; os atalhos criados pelo instalador usam o ciclo gerenciado. Não é necessário copiar `.git`, configurações pessoais, gravações ou logs.

Para gerar outro pacote, informe uma pasta nova com `-Destination 'C:\caminho\pacote-novo'`. O exportador não substitui uma pasta ou ZIP existente.

## Pasta do aplicativo

Configurações, frases, gravações e logs ficam no perfil do usuário, independentemente da pasta de execução:

```text
%USERPROFILE%\.kmao-bot\
├── config\
│   ├── application.conf         # Configuração unificada: bot e logger
│   ├── bot.conf                 # Legado preservado, quando existente
│   └── kmao.conf                # Legado preservado, quando existente
├── phrases.txt                  # Uma frase por linha
├── data\                        # Gravações CSV
└── logs\                        # Logs operacionais por execução
```

A pasta do perfil é obtida pela API `.NET Environment.GetFolderPath(UserProfile)`. Na primeira execução de cada componente, seus arquivos são copiados dos exemplos do repositório. Arquivos existentes na pasta do aplicativo são preservados.

Configurações antigas em `config/kmao.conf` e gravações antigas em `data/` do repositório não são migradas automaticamente. Para reaproveitar uma configuração anterior, copie-a para a nova pasta antes de executar. Desde a 0.3.5, os valores de `bot.conf` e `kmao.conf` já existentes no perfil são importados para `config/application.conf`, mantendo os originais. Personalizações antigas feitas diretamente em `dev.ps1` devem ser transferidas para `application.conf`. Depois da cópia inicial, edite os arquivos do perfil; alterações nos exemplos do repositório não substituem suas configurações.

## Bot de automação

Na versão 0.3.0, a interface fica na bandeja e o alvo é um Notepad próprio. Veja
[TRAY_BOT.md](TRAY_BOT.md) para uso e encerramento.

Inicie por `dev.bat` ou execute o script PowerShell. Use o caminho do repositório, que pode ser diferente do exemplo:

```powershell
& 'C:\caminho\kmao-bot\dev.bat'
```

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File 'C:\caminho\kmao-bot\dev.ps1'
```

### Comportamento

- Cria um Notepad próprio maximizado, digitando `KMAO BOT is running...` caractere por caractere, e inicia em Run.
- Exibe um robô verde em Run e cinza em Stop; botão direito oferece Run/Stop, Logs,
  About e Exit. O ícone pode estar na área oculta da bandeja do Windows.
- Aguarda pelo menos 60 segundos de inatividade e um intervalo aleatório de 30 a
  239 segundos. Verde indica que Run está habilitado, inclusive durante as esperas.
- Executa de 1 a 3 cliques no retângulo central de até 400 × 200 pixels, limitado
  à área do editor, com 70% de chance de acrescentar uma frase e uma nova linha.
- Escreve texto Unicode diretamente no editor do Notepad próprio. Não digita nem
  envia Enter a outros aplicativos. O alvo não acompanha mudanças de janela.
- Cancela o ciclo e fica cinza ao detectar atividade externa ou mudança de foco/aba.
- Após o limite de inatividade, maximiza/ativa o próprio Notepad e só retoma (verde)
  depois de confirmar o foco. Stop manual só é desfeito por Run.
- Logs abre um console com acompanhamento ao vivo. About abre o projeto no GitHub.
- Exit e a parada pelo atualizador descartam apenas o documento do bot sem salvar.
  Outras abas e janelas do Notepad são preservadas.

### Configuração

Use **Configurações** na bandeja para editar `%USERPROFILE%\.kmao-bot\config\application.conf`. O arquivo contém todos os parâmetros do bot e do logger, com comentários em português acima de cada opção. Veja [config/application.conf.example](config/application.conf.example). Ao abrir o editor, o bot pausa manualmente. Salve e selecione Run para aplicar. Toda entrada em Running relê e valida o arquivo, inclusive após inatividade; valores inválidos mantêm o ícone cinza e são registrados no log.

Os limites máximos dos intervalos aleatórios são exclusivos. Cada mínimo deve ser menor que seu máximo. Chances aceitam 0 a 100; intervalos e limite de inatividade aceitam 1 a 86400 segundos, pausas aceitam 0 a 60000 ms e limites de cliques aceitam 1 a 100. A área configurada é limitada ao tamanho atual do editor do Notepad.

Edite `%USERPROFILE%\.kmao-bot\phrases.txt` para definir uma frase por linha. Linhas vazias são ignoradas; um arquivo sem frases é tratado como erro. As frases são lidas como UTF-8 e enviadas como texto Unicode ao editor, sem interpretar caracteres especiais como comandos de teclado.

Use Stop para pausar e Exit para encerrar pelo ícone da bandeja. A janela própria é descartável; não a use para anotações que deseja manter. Se substituir o documento ou remover a mensagem inicial, o bot pausa e preserva o conteúdo.

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

Edite as opções do logger no mesmo `%USERPROFILE%\.kmao-bot\config\application.conf` (aplicadas na próxima gravação):

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

O logger também captura entradas sintetizadas por software. Os movimentos do bot podem ser registrados, mas os cliques e textos enviados diretamente ao editor do Notepad não produzem eventos globais de mouse/teclado. Não registra títulos de janelas ou nomes de processos. Os registros de clique não distinguem os botões, e os de scroll não incluem direção ou intensidade.

## Configuração, erros e logs

- Os arquivos `.conf` aceitam `NOME=inteiro`, sem aspas, linhas vazias e comentários iniciados por `#`.
- Chaves desconhecidas, duplicadas, valores inválidos, fora dos limites ou pares mínimo/máximo inconsistentes mantêm o bot pausado; no logger, impedem o início da gravação.
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

Os testes de núcleo, atualização e coordenação de sessões passaram no Windows PowerShell 5.1 chamado pelo WSL. A captura por hooks em desktop e a instalação completa ainda precisam de validação manual. Também devem ser verificados manualmente a gravação por duração, a interrupção com `Ctrl+C`, falhas de permissão/escrita, a retomada real de atividade durante a digitação e a troca de janela. O Windows pode remover silenciosamente hooks que excedam seu tempo limite; não há recuperação automática implementada.

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
convidados. A compilação do instalador e os testes de sessão e atualização passaram no Windows
via WSL; a validação manual completa de instalação e atualização continua necessária. O [roadmap](ROADMAP.md) registra o estado e os
critérios de aceitação.

## Estrutura do repositório

```text
kmao-bot/
├── README.md
├── ROADMAP.md                   # Decisões e validação pendente
├── INSTALLATION.md              # Instalação, assinatura e publicação
├── TRAY_BOT.md                  # Bandeja, Notepad próprio e testes interativos
├── Show-KmaoLogs.ps1            # Acompanhamento do log ao vivo
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
│   ├── application.conf.example
│   ├── bot.conf.example          # Legado
│   └── kmao.conf.example         # Legado
├── lib/
│   ├── Kmao.Common.ps1          # Caminhos, configuração e logs
│   ├── Kmao.Windows.cs          # Hooks, fila e envio de entrada
│   ├── Kmao.Update.ps1           # Autenticidade, extração e troca de versão
│   ├── Kmao.Desktop.cs           # Bandeja e ícones
│   └── Kmao.Notepad.cs           # Janela e documento próprios
└── tests/
    ├── Test-Core.ps1
    ├── Test-Windows.ps1
    ├── Test-Updates.ps1
    ├── Test-Lifecycle.ps1
    └── Test-Desktop*.ps1
```

## Privacidade

O Activity Logger registra eventos de teclado, incluindo nomes das teclas pressionadas e liberadas, e pode permitir a reconstrução de informações sensíveis. Utilize somente em dispositivos próprios ou com autorização das pessoas envolvidas.

Eventos, frases, configurações e gravações não são enviados para serviços externos. A instalação gerenciada faz consultas HTTPS ao GitHub para verificar e baixar atualizações. Os arquivos de uso ficam na pasta do aplicativo no perfil do usuário.

## Licença

O repositório inclui a licença [GNU General Public License v3.0](LICENSE).
