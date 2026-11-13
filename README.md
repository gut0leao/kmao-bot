# KMAO Bot (Keep-me Always On Bot)

O KMAO reúne um bot de interação com um Notepad próprio e um gravador de eventos
de mouse e teclado para Windows. A versão do código está em [VERSION](VERSION);
esta documentação descreve a **0.3.5**.

O bot roda pela bandeja, digita apenas em seu documento e pausa quando o usuário
volta a usar o computador. O Activity Logger funciona como componente separado.
A instalação por usuário oferece atualização com confirmação e recuperação da
versão anterior.

| Guia | Conteúdo |
| --- | --- |
| [Bandeja e configuração](TRAY_BOT.md) | Run/Stop, Configurações, Notepad, retomada e limites |
| [Instalação e publicação](INSTALLATION.md) | Windows, desenvolvimento no WSL, build, GitHub e atualização |
| [Assinatura Windows](CODE_SIGNING.md) | RSA do atualizador, Authenticode e certificado pendente |
| [Activity Logger](ACTIVITY_LOGGER_SPEC.md) | Configuração, hooks, CSV e encerramento |
| [Estado e próximos passos](ROADMAP.md) | Funcionalidades entregues, evidências e pendências |
| [Histórico](CHANGELOG.md) | Alterações por versão |

## Uso no Windows

Instale o pacote completo `kmao-setup-0.3.5.exe` e abra **KMAO Bot** pelo menu
Iniciar. O instalador usa `%LOCALAPPDATA%\Programs\KMAO Bot`, sem exigir
privilégios de administrador. Feche bot, logger e atualizador antes de reinstalar.

O bot usa `Kmao.Bot.exe`, que hospeda Windows PowerShell 5.1 e a bandeja dentro do
processo identificado como KMAO Bot. Não é preciso instalar um runtime PowerShell
separado. O logger continua sendo executado em Windows PowerShell.

São necessários Windows PowerShell 5.1, .NET Framework 4.6 ou posterior, Notepad
instalado e desktop interativo desbloqueado. Windows 11 é o alvo principal; a
compatibilidade com todas as versões e idiomas do Notepad não está garantida.
A execução nativa dos componentes não está disponível no Linux ou macOS.

Os pacotes de teste atuais usam assinatura RSA para atualizações, mas continuam
sem Authenticode. O Windows pode bloquear um instalador ou componente desconhecido.
O [guia de assinatura](CODE_SIGNING.md) explica a emissão ainda pendente. Instalar
uma versão sem bloqueio não demonstra que todas as seguintes serão aceitas.

Instalações até 0.3.0 precisam receber manualmente um instalador da 0.3.1 ou
posterior para corrigir a consulta ao GitHub. A partir dessa correção, abra pelos
atalhos instalados para receber ofertas de atualização.

## Bandeja e Notepad

- A abertura cria um documento próprio maximizado e digita
  `KMAO BOT is running...` caractere por caractere. Sessões anteriores são
  preservadas; uma janela nova já vazia e sem título reconhecido é reutilizada.
- Verde indica Running habilitado. Atividade externa ou perda de foco pausa o
  ciclo e deixa o ícone cinza. Após a inatividade configurada, o bot relê as
  opções, maximiza/ativa seu Notepad e só retoma se confirmar o foco.
- Stop é pausa manual e só é desfeito por Run. Fechar ou substituir o documento
  também exige Run para criar outro. Configurações pausa manualmente para editar.
- A escrita e os cliques são enviados ao editor próprio; o cursor usa entrada
  marcada como sendo do bot. As verificações de atividade e foco continuam entre
  as ações e durante as esperas.
- Logs acompanha o log atual em um console; Open logs folder abre a pasta de
  diagnósticos; About abre o GitHub; Exit encerra e descarta o documento do bot.

Com os padrões atuais, os ciclos aguardam 60 segundos de inatividade e mais um
intervalo aleatório de 30 a 239 segundos. Executam de 1 a 3 cliques na área central
de até 400 × 200 pixels do editor, com 70% de chance de acrescentar uma frase.
A mensagem inicial é uma etapa separada e pode começar antes dessa espera.

Use Exit para o descarte normal. Não use o documento descartável para anotações
pessoais. Fechamento forçado, queda de energia ou o X do próprio Notepad podem
impedir que o KMAO limpe o texto antes da restauração de sessão do Notepad.

## Configuração do usuário

Abra **Configurações** no menu da bandeja. O arquivo é:

```text
%USERPROFILE%\.kmao-bot\config\application.conf
```

Ele reúne **31 parâmetros** de bot e logger. Cada variável tem um comentário em
português na linha acima, com unidade e limites. A referência de valores padrão
é [config/application.conf.example](config/application.conf.example).

Salve e selecione Run para aplicar. O bot relê e valida todo o arquivo antes de
cada entrada em Running: inicialização, Run manual e retomada por inatividade.
Configuração inválida mantém o bot cinza, preserva o último conjunto válido em
memória e registra o erro. O logger lê o mesmo arquivo ao iniciar uma gravação;
edições não reconfiguram uma gravação já em andamento.

Na primeira criação, valores explícitos de `config/bot.conf` e `config/kmao.conf`
do perfil são importados; os originais permanecem intactos. Depois disso, somente
`application.conf` é usado pelas versões atuais. Não sobrescreva nem apague seus
arquivos para atualizar. Em uma recuperação para uma versão anterior à 0.3.5,
essa versão volta a usar os arquivos legados, sem receber as edições do unificado.

Os valores são inteiros sem aspas. Linhas vazias e comentários `#` são aceitos;
chaves desconhecidas/duplicadas e pares mínimo/máximo inconsistentes são rejeitados.
Os limites máximos aleatórios são exclusivos. Regras e grupos de parâmetros estão
no [guia da bandeja](TRAY_BOT.md#configuração).

As frases ficam em `%USERPROFILE%\.kmao-bot\phrases.txt`, em UTF-8, uma por linha.
Linhas vazias são ignoradas; arquivo sem frases impede a inicialização. As frases
são lidas ao iniciar o bot, sem interpretar caracteres como comandos de teclado.

## Dados e logs

```text
%USERPROFILE%\.kmao-bot\
├── config\application.conf       # Configuração atual
├── config\bot.conf               # Legado, quando existente
├── config\kmao.conf              # Legado, quando existente
├── phrases.txt
├── data\                        # Gravações CSV
├── logs\                        # Bot, logger, launcher, updater e host
└── updates\                     # Área temporária do atualizador
```

O perfil é obtido pela API do Windows; não depende da pasta de execução nem do
home Linux do WSL. Logs operacionais não incluem as frases nem os eventos
capturados. Os CSVs do logger contêm os eventos e podem revelar informações
sensíveis. Use somente em dispositivos próprios ou com autorização das pessoas
envolvidas. Não há rotação, compressão ou exclusão automática de logs/CSV.

## Activity Logger

Abra **KMAO Bot - Gravar atividade** no menu Iniciar. Para desenvolvimento ou modo
portátil, use `init_recording.bat` ou `activity_logger.ps1` no pacote completo.
Interrompa com Ctrl+C ou configure `RECORDING_DURATION_MINUTES`.

Os hooks rodam em uma thread C# com processamento de mensagens. O script consome
a fila e escreve o CSV, incluindo o esvaziamento final antes de liberar a sessão.
O formato, os limites e as falhas são descritos na
[especificação atual do logger](ACTIVITY_LOGGER_SPEC.md).

## Desenvolvimento no WSL

Mantenha o repositório no Linux e use Bash ou Zsh. Os comandos chamam o PowerShell
do Windows e convertem caminhos via `wslpath`:

```bash
./scripts/kmao.sh doctor
./scripts/kmao.sh test
./scripts/kmao.sh desktop-test  # Interativo; abre e descarta documentos próprios
```

O build do `.exe` requer Inno Setup 6 no Windows. Prepare a identidade RSA somente
uma vez e mantenha a mesma chave para as atualizações seguintes:

```bash
./scripts/kmao.sh keygen       # Não repetir se as chaves já existem
./scripts/kmao.sh build --allow-unsigned --output ./dist/release-0.3.5
```

`--allow-unsigned` dispensa apenas Authenticode; o manifesto continua assinado com
RSA. Para um build com publicador reconhecido, configure `--authenticode-signer`
conforme [CODE_SIGNING.md](CODE_SIGNING.md). Pastas de saída não são sobrescritas.

Faça commit antes de gerar o pacote que será publicado. Depois do build e push:

```bash
./scripts/kmao.sh publish --dry-run
./scripts/kmao.sh publish
```

O comando lê `VERSION`, encontra os pacotes em `dist/release-VERSION` ou
`dist/release` e publica como prerelease. Não faz build, commit nem push.
`--draft` cria um rascunho. Requer Python 3, Git e GitHub CLI autenticado no WSL.
O [guia de publicação](INSTALLATION.md#publicação-no-github) detalha a sequência.

## Pacote portátil e arquitetura

```bash
./scripts/kmao.sh export --output ./dist/portable-teste
```

Extraia todo o pacote e execute `dev.bat` ou `init_recording.bat`. Copiar somente
um script deixa dependências ausentes. O export simples contém os fontes e pode
compilar C# ao iniciar; não gera o executável próprio. O build Windows gera também
`Kmao.Bot.exe`, seu `.config` e `lib/Kmao.Runtime.dll`. Sem instalação gerenciada,
o modo portátil não consulta atualizações.

| Arquivo/pasta | Responsabilidade |
| --- | --- |
| `Start-Kmao.ps1` | Despachante estável da instalação |
| `Launch-Kmao.ps1`, `Apply-KmaoUpdate.ps1` | Consulta, confirmação e atualização |
| `host/Kmao.Bot.cs` | Processo próprio com PowerShell e automação incorporados |
| `dev.ps1`, `activity_logger.ps1` | Fluxos de bot e logger |
| `lib/Kmao.Configuration.ps1` | Configuração unificada, migração e validação |
| `lib/Kmao.Common.ps1` | Diretórios, logs e coordenação de sessões |
| `lib/Kmao.Windows.cs` | Hooks, fila e entrada marcada |
| `lib/Kmao.Desktop.cs`, `lib/Kmao.Notepad.cs` | Bandeja e documento próprio |
| `config/` | Template atual e templates legados |
| `scripts/`, `installer/` | Comandos WSL, assinatura, build e instalador |
| `tests/`, `.github/workflows/` | Verificações locais e CI |

## Validação e limites

Foram executados testes portáveis e no Windows via WSL: configuração/migração,
cripto/extração, sessões e recuperação, bandeja/logs, host nativo e compilação do
instalador. Testes interativos com perfis temporários validaram Notepad próprio,
texto gradual, prontidão e encerramento. O responsável pelo projeto confirmou
instalação e atualização automática em sua máquina.

Ainda são necessários testes em outras contas/máquinas, desinstalação completa,
cenários prolongados do logger e compatibilidade com políticas de proteção.
A captura real e a troca de foco também exigem validação manual; os hooks não têm
recuperação automática se o Windows os remover. Veja [ROADMAP.md](ROADMAP.md).

O aplicativo consulta/baixa atualizações do GitHub por HTTPS e abre o navegador
quando solicitado. Eventos, frases e configurações não são enviados pelo KMAO.
A licença é [GNU GPLv3](LICENSE).
