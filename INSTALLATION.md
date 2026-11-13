# Instalação, atualização e publicação

A última versão publicada é `0.3.1`; a `0.3.2` está em preparação para assinatura
Authenticode. A distribuição compatível com Smart App Control depende da emissão
do certificado e de teste em Windows protegido. Veja [CODE_SIGNING.md](CODE_SIGNING.md).
O instalador e o atualizador estão implementados;
nenhuma Release ou chave de produção é criada automaticamente ao clonar o projeto.

## Como a instalação funciona

O instalador Inno Setup roda por usuário, sem elevação, e usa por padrão:

```text
%LOCALAPPDATA%\Programs\KMAO Bot\
├── Start-Kmao.ps1                # Despachante estável dos atalhos
├── update-public-key.xml         # Identidade confiável de publicação
├── current.json                  # Versão ativa
├── previous.json                 # Versão anterior, quando disponível
└── versions\
    └── 0.3.1\                   # Código completo e independente por versão
```

O menu Iniciar recebe os atalhos **KMAO Bot**, **KMAO Bot - Gravar atividade**,
**KMAO Bot - Restaurar versao anterior** e **Desinstalar KMAO Bot**, na pasta
KMAO Bot. Os atalhos do aplicativo têm identidades próprias para o Windows.

O instalador original da versão 0.2.0 criou atalhos com nomes genéricos, como
**Iniciar bot** e **Gravar atividade**. Nessa instalação, pesquise esses nomes ou
abra `shell:programs\KMAO Bot` pelo `Win+R`. A correção dos nomes é aplicada
pelo instalador; ao reinstalar com o pacote corrigido, os atalhos antigos são
removidos. Uma atualização apenas pelo ZIP não recria os atalhos do instalador.
 Configurações, frases e gravações continuam em
`%USERPROFILE%\.kmao-bot`, inclusive para quem já usava a distribuição portátil.
A desinstalação remove o código e as versões baixadas, preservando a pasta de dados.

Reinstalações não devem ocorrer com componentes ou atualizador em execução. O
instalador verifica seus mutexes e pede que sejam fechados. Ele não força o
encerramento de processos PowerShell. Cada usuário pode executar uma instância do
bot e uma do logger por sessão de desktop.

## Bandeja e Notepad próprio

Desde a 0.3.0, o bot abre um Notepad próprio e roda pela bandeja, com Run/Stop, Logs, About e
Exit. O [guia da interface](TRAY_BOT.md) detalha a pausa, o descarte sem salvar e a
preservação de outros documentos. Esses recursos estão no código versionado e não exigem alterações nos atalhos.

**Correção da consulta de atualizações:** as versões até 0.3.0 não interpretam
corretamente a lista da API no Windows PowerShell 5.1. Feche o bot e o logger e
execute `kmao-setup-0.3.1.exe` manualmente uma vez. Os dados em
`%USERPROFILE%\.kmao-bot` são preservados. Depois disso, os atalhos da instalação
consultam novas prereleases ao iniciar e registram o resultado nos logs `launcher-*.log`.

## Desenvolvimento no WSL

O repositório pode permanecer no filesystem Linux (`/home/...`). Use o terminal
Bash ou Zsh do WSL, a partir da raiz do projeto:

```bash
./scripts/kmao.sh doctor    # Verifica PowerShell e Inno Setup do Windows
./scripts/kmao.sh test      # Testes de núcleo, sessão, bandeja e build no Windows
./scripts/kmao.sh desktop-test # Interativo: Notepad próprio e encerramento do bot
./scripts/kmao.sh keygen    # Uma vez: chaves no perfil do usuário Windows
./scripts/kmao.sh build --authenticode-signer /mnt/c/caminho/Provider.ps1 # Distribuição
```

O comando usa a interoperabilidade do WSL (`powershell.exe`) e converte os caminhos
com `wslpath`. O código é acessado pelo caminho UNC `\\wsl.localhost\...`; não é
necessário mover o repositório para o Windows ou copiar os scripts manualmente.
Os arquivos de distribuição ficam em `dist/release/` no próprio repositório WSL.

Para gerar o `.exe`, instale o **Inno Setup 6 no Windows**. O comando procura o
compilador no PATH e nos diretórios de instalação usuais. Se ele estiver em outro
local, passe o caminho usando a notação WSL, com aspas quando houver espaços:

```bash
./scripts/kmao.sh build --authenticode-signer /mnt/c/caminho/Provider.ps1 \
  --iscc '/mnt/c/Program Files (x86)/Inno Setup 6/ISCC.exe'
```

O build verifica o compilador antes de criar a saída ou ler as chaves. Para desenvolvimento sem Authenticode, use `--allow-unsigned` explicitamente;
esse modo não resolve o bloqueio pelo SAC. Para gerar
somente o ZIP assinado e seus metadados, use `./scripts/kmao.sh build --skip-installer`.
Para apenas empacotar os scripts, sem chaves nem Inno Setup:

```bash
./scripts/kmao.sh export --output ./dist/portable-teste
```

Por padrão, `keygen` grava em `%USERPROFILE%\.kmao-signing` **do Windows**, usando a
mesma identidade das instruções PowerShell abaixo. Ele não cria uma segunda chave
no home Linux. Para gerar chaves em outro local, use um diretório de um disco do
Windows, onde a proteção por ACL está disponível:

```bash
./scripts/kmao.sh keygen \
  --private-key '/mnt/c/caminho-seguro/private.xml' \
  --public-key '/mnt/c/caminho-seguro/public.xml'
./scripts/kmao.sh build \
  --private-key '/mnt/c/caminho-seguro/private.xml' \
  --public-key '/mnt/c/caminho-seguro/public.xml' \
  --authenticode-signer /mnt/c/caminho/Provider.ps1 \
  --output ./dist/release-teste
```

As opções de caminho aceitam caminhos Linux absolutos ou relativos ao diretório
atual. Não passe `C:\...` diretamente às opções do wrapper; use `/mnt/c/...`.
Arquivos de chave e pastas de saída existentes não são substituídos.
`./scripts/kmao.sh --help` lista as opções.

Se `powershell.exe` não for encontrado ou o WSL impedir a execução de `.exe`,
verifique a interoperabilidade e o PATH do Windows no WSL. O `pwsh` instalado no
Linux continua útil para testes portáveis, mas não substitui os testes de sessão
nem o Inno Setup do Windows. O workflow do GitHub Actions permanece outra opção
para gerar o instalador num runner Windows.

Referência: [interoperabilidade entre WSL e Windows](https://learn.microsoft.com/en-us/windows/wsl/filesystems#run-windows-tools-from-linux).

## Preparar a identidade de publicação (uma vez)

No PowerShell, a partir da raiz do repositório:

```powershell
.\scripts\New-KmaoSigningKey.ps1 `
  -PrivateKeyPath "$env:USERPROFILE\.kmao-signing\private.xml" `
  -PublicKeyPath "$env:USERPROFILE\.kmao-signing\public.xml"
```

O comando cria uma chave RSA de 3072 bits e restringe o acesso ao arquivo privado.
Ele recusa gravar a chave privada dentro do repositório ou substituir uma chave
existente. Faça uma cópia de segurança segura da chave privada. Ela é necessária
para assinar todas as atualizações reconhecidas pelas instalações existentes.
Nunca a inclua em commits, Releases, ZIPs ou mensagens.

A assinatura dos pacotes é independente de Authenticode. Não há certificado
de assinatura de código configurado. O build de distribuição agora exige um
provedor; o modo de desenvolvimento `--allow-unsigned` pode ser bloqueado pelo
Windows e não deve ser distribuído como compatível com Smart App Control. A chave pública é incorporada ao
instalador inicial e preservada nas reinstalações. A rotação da identidade não faz
parte do protocolo 1; trocar de chave exige uma migração deliberada das instalações.

## Gerar o instalador localmente

É necessário Windows PowerShell 5.1 e [Inno Setup 6](https://jrsoftware.org/isinfo.php).
Execute os testes antes de gerar uma versão para convidados:

```powershell
.\tests\Test-Core.ps1
.\tests\Test-Updates.ps1
.\tests\Test-Lifecycle.ps1

.\scripts\Build-KmaoRelease.ps1 `
  -PrivateKeyPath "$env:USERPROFILE\.kmao-signing\private.xml" `
  -PublicKeyPath "$env:USERPROFILE\.kmao-signing\public.xml" `
  -AuthenticodeSigner "C:\caminho\Provider.ps1" `
  -IsccPath "${env:ProgramFiles(x86)}\Inno Setup 6\ISCC.exe"
```

O resultado fica em `dist/release/`:

- `kmao-setup-0.3.2.exe`: instalação inicial ou reinstalação manual, após configurar o provedor.
- `kmao-0.3.2.zip`: código da versão usado pelo atualizador.
- `kmao-manifest.json` e `kmao-manifest.sig`: metadados e assinatura RSA/SHA-256.
- `kmao-release-notes.md`: notas somente da versão atual, para usar na descrição da Release.
- `payload/` e `installer-source/`: pastas intermediárias, não destinadas à Release.

O build recusa um diretório de saída existente. Para outra geração, use
`-OutputDirectory` com uma pasta nova. `-SkipInstaller` permite testar assinatura e
pacote em Linux/PowerShell 7, sem gerar o `.exe`. Os bytes do ZIP podem variar entre
builds; cada assinatura corresponde ao pacote exato produzido naquela execução.

## Gerar pelo GitHub Actions

O workflow **Build release (manual)** é acionado somente em `workflow_dispatch`.
Configure previamente os secrets do repositório, usando GitHub CLI autenticado:

```powershell
[Convert]::ToBase64String([IO.File]::ReadAllBytes("$env:USERPROFILE\.kmao-signing\private.xml")) | gh secret set KMAO_RELEASE_KEY_BASE64
[Convert]::ToBase64String([IO.File]::ReadAllBytes("$env:USERPROFILE\.kmao-signing\public.xml")) | gh secret set KMAO_RELEASE_PUBLIC_KEY_BASE64
```

O workflow testa no Windows PowerShell, gera o instalador com Inno Setup e entrega
os quatro anexos de distribuição e o arquivo de notas como artifact. As chaves temporárias ficam no diretório do
runner e são excluídas no final; não são enviadas como artifacts.

O workflow de release está temporariamente bloqueado antes da leitura de segredos
até configurar o provedor Authenticode no runner. As instruções seguintes descrevem
o fluxo após essa configuração.

Por padrão, não cria Release. Se `create_draft` estiver habilitado, cria apenas um
**rascunho não publicado**, marcado como prerelease, na tag `v0.3.1`. A publicação
para os convidados depende de uma ação posterior no GitHub. Os workflows de
validação em pushes/PRs não recebem nem precisam da chave de publicação.

## Publicar pelo WSL com um comando

Depois de gerar os pacotes, fazer o commit e enviar ao GitHub:

```bash
git push origin main
./scripts/kmao.sh publish
```

`publish` lê `VERSION`, usa a tag `vX.Y.Z`, o título `KMAO X.Y.Z — testes` e as
notas `kmao-release-notes.md`. Publica diretamente como **prerelease** com os quatro
anexos: instalador, ZIP, manifesto e assinatura. Não executa build, commit nem push.

Procura os pacotes em `dist/release-X.Y.Z`; se essa pasta não existir, usa
`dist/release`, que é a saída padrão do build. Para outro diretório:

```bash
./scripts/kmao.sh publish --output ./dist/meu-pacote
```

Para conferir o comando sem acessar o GitHub ou criar apenas um rascunho:

```bash
./scripts/kmao.sh publish --dry-run
./scripts/kmao.sh publish --draft
```

Requer Python 3, Git e GitHub CLI (`gh auth login`) no WSL. Não precisa executar
PowerShell para publicar. O comando verifica arquivos obrigatórios, versão/canal do
manifesto e hash do ZIP; exige uma árvore Git limpa e confirma o commit no GitHub
antes de criar a release. A assinatura é validada pelo build, conforme
[CODE_SIGNING.md](CODE_SIGNING.md). Não substitui releases nem anexos existentes.

## Publicar uma nova versão para testes

1. Atualize `VERSION` com três números, por exemplo `0.3.2`, e escreva as notas em
   `CHANGELOG.md`. O canal inicial usa versões numéricas e a marca prerelease do
   GitHub; sufixos como `-beta.1` não são suportados neste protocolo.
2. Gere os quatro arquivos na mesma execução, usando a mesma chave de assinatura.
3. Anexe instalador, ZIP, manifesto e assinatura à Release `v0.3.2` do repositório
   `gut0leao/kmao-bot` e marque-a como **prerelease**.
4. Revise o rascunho e publique quando decidir compartilhar o teste.

O atualizador lista as 100 Releases mais recentes e considera somente prereleases
publicadas com tag `vX.Y.Z`. Escolhe a maior versão numérica superior à instalada.
Ele não usa `/releases/latest`, que não é adequado ao canal de testes. Uma versão
com pacote ou assinatura inválidos não é instalada; a versão atual continua
utilizável. O endereço do repositório e o canal estão fixos no protocolo inicial.

Downloads públicos podem ser descobertos e compartilhados mesmo sem divulgação.
Não inclua configurações pessoais, gravações, logs ou chaves privadas nos anexos.

## Fluxo de atualização

Os atalhos instalados passam pelo lançador e consultam o GitHub a cada início. Se
houver atualização, mostram versão instalada, versão oferecida e notas, pedindo
confirmação. Recusar ou estar sem internet inicia a versão atual. A mesma oferta
pode aparecer na próxima inicialização. Nenhum serviço ou tarefa agendada é criado.

Após aceitar:

1. Um processo separado obtém o bloqueio de atualização e revalida a assinatura do
   manifesto com a chave pública instalada. O download exige HTTPS e o endereço
   esperado dos assets do repositório.
2. O ZIP precisa corresponder ao hash assinado. A extração verifica hashes de cada
   arquivo, lista completa, caminhos seguros, limites de tamanho, versão, esquema
   de configuração e sintaxe PowerShell.
3. A nova versão é preparada ao lado da atual. O atualizador sinaliza o encerramento
   do bot e logger e aguarda até 20 segundos pela limpeza. Novas sessões são
   bloqueadas nesse intervalo. Nenhum processo de usuário é morto à força.
4. Um arquivo de estado troca a versão ativa atomicamente e guarda a anterior.
   A versão nova tem até 30 segundos para sinalizar que inicializou configuração,
   hooks e, no logger, o arquivo de gravação. Somente o componente solicitado é
   reaberto; o outro permanece encerrado.
5. Se a inicialização falhar, o atualizador tenta encerrar a tentativa, restaura a
   versão anterior e a reabre. Se o processo do atualizador for interrompido, um
   diário `pending.json` permite recuperar a versão anterior na próxima abertura.

Se um componente não concluir o encerramento, a atualização é adiada e os detalhes
ficam em `%USERPROFILE%\.kmao-bot\logs`. O mesmo diretório guarda os logs do
lançador e do atualizador. Downloads temporários usam `updates/` e são removidos
quando o fluxo termina normalmente; uma interrupção forçada pode deixar sobras.

Para restaurar manualmente, use o atalho **Restaurar versao anterior** ou:

```powershell
& "$env:LOCALAPPDATA\Programs\KMAO Bot\Start-Kmao.ps1" -Rollback
```

A restauração também pede confirmação. As versões antigas ficam em `versions/`
até a desinstalação; não há limpeza automática nem exclusão dos dados pessoais.

## Compatibilidade e limites

- O esquema de configuração atual é 1. Atualizações de outro esquema são
  rejeitadas, preservando os arquivos do usuário; ainda não há migração de esquema.
- O despachante estável e a chave pública são instalados pelo `.exe`. O bot,
  logger, lançador e atualizador são versionados e podem ser atualizados pelo ZIP.
- O pacote portátil continua funcionando sem instalar e sem consultar atualizações.
  Use o instalador para entrar no ciclo gerenciado.
- A assinatura verifica a origem dos pacotes; não protege contra alteração local
  por alguém que já tenha acesso de escrita à conta do usuário.
- A confirmação de prontidão valida a inicialização, não garante ausência de erros
  posteriores durante o uso. O atalho de restauração permanece disponível.
- Testes automáticos de sessão usam eventos/mutexes reais no Windows sem gerar
  entrada de mouse/teclado. Hooks e interação exigem `Test-Windows.ps1` em desktop
  interativo. Instalação, desinstalação e atualização entre duas Releases também
  devem ser validadas numa conta Windows de teste antes de convidar pessoas.
