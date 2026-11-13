# Instalação, build e publicação — 0.3.5

[VERSION](VERSION) define a versão do código; [CHANGELOG.md](CHANGELOG.md) reúne
as notas. O projeto possui instalador e atualizador. Authenticode ainda depende
de certificado/provedor: os pacotes atuais de teste são gerados explicitamente
sem essa assinatura, mantendo a assinatura RSA do manifesto.

## Instalar no Windows

Baixe o instalador da release escolhida no
[GitHub do projeto](https://github.com/gut0leao/kmao-bot/releases), feche bot,
logger e atualizador e execute `kmao-setup-0.3.5.exe` para essa versão.
O instalador Inno Setup é por usuário, sem exigir administrador.

```text
%LOCALAPPDATA%\Programs\KMAO Bot\
├── Start-Kmao.ps1
├── update-public-key.xml
├── current.json
├── previous.json                 # Quando há versão anterior
└── versions\
    └── 0.3.5\
        ├── Kmao.Bot.exe
        ├── Kmao.Bot.exe.config
        ├── dev.ps1 / activity_logger.ps1
        ├── Launch-Kmao.ps1 / Apply-KmaoUpdate.ps1
        ├── lib\
        └── config\
```

O menu Iniciar recebe KMAO Bot, KMAO Bot - Gravar atividade, KMAO Bot - Restaurar
versao anterior e Desinstalar KMAO Bot. As configurações e dados permanecem em
`%USERPROFILE%\.kmao-bot`, inclusive após a desinstalação padrão.

O lançador consulta atualizações antes de iniciar o componente. No bot, ele inicia
`Kmao.Bot.exe` e acompanha sua saída. O executável hospeda Windows PowerShell 5.1,
interface e automação no próprio processo. O logger continua em PowerShell.
Atalhos existentes funcionam com esse fluxo; o ZIP não recria atalhos do instalador.

A versão 0.2.0 criou atalhos genéricos. Reinstalar com um instalador posterior
corrige esses nomes. Versões até 0.3.0 também precisam de uma instalação manual
posterior para corrigir a leitura da API do GitHub; o próprio atualizador antigo
não consegue obter essa correção. Use um instalador publicado da 0.3.1 ou posterior.

O Windows pode bloquear arquivos sem assinatura/reputação reconhecida. Isso é
independente da validação RSA do KMAO. Veja [CODE_SIGNING.md](CODE_SIGNING.md).

## Configuração e dados

Configurações no menu da bandeja abre
`%USERPROFILE%\.kmao-bot\config\application.conf`. A primeira criação reúne os
valores explícitos dos antigos `bot.conf` e `kmao.conf` no perfil e mantém ambos
intactos. O template é [config/application.conf.example](config/application.conf.example).

O bot valida e relê o arquivo a cada entrada em Running. Abrir Configurações pausa
manualmente; salve e escolha Run. O logger aplica as opções na próxima gravação.
A [referência de configuração](TRAY_BOT.md#configuração) explica os 31 parâmetros,
a importação, valores inválidos e o uso de arquivos legados em recuperação.

Frases ficam em `phrases.txt`, CSVs em `data/` e diagnósticos em `logs/`, todos
sob a pasta do perfil. Não copie dados pessoais para o diretório do código.

## Desenvolvimento no WSL

O checkout pode permanecer em `/home/...`; não é preciso copiar o repositório
para um disco Windows. Execute Bash ou Zsh com interoperabilidade Windows ativa:

```bash
./scripts/kmao.sh doctor
./scripts/kmao.sh test
./scripts/kmao.sh desktop-test
```

`doctor` verifica Windows PowerShell e Inno Setup. `test` executa a suíte no
Windows via `powershell.exe`, incluindo build UNC com chaves temporárias.
`desktop-test` é interativo: abre/descarta documentos próprios e valida processos
com perfis temporários. Feche outra sessão do bot para o teste legado de singleton.

Para os testes Python do wrapper/publicador no Linux:

```bash
python3 tests/test_wsl_bridge.py
python3 tests/test_publish_release.py
```

O wrapper passa caminhos convertidos por `wslpath`, sem avaliá-los como código.
Use caminhos Linux, por exemplo `/mnt/c/Program Files (x86)/Inno Setup 6/ISCC.exe`.
Não passe `C:\...` às opções Bash. O `pwsh` Linux é útil para testes portáveis,
mas não compila o host nativo nem substitui os testes Windows.

## Preparar a chave RSA uma vez

O padrão do WSL aponta para o perfil **Windows**:

```bash
./scripts/kmao.sh keygen
```

Os arquivos são `%USERPROFILE%\.kmao-signing\private.xml` e `public.xml`. Se já
existem, não gere outra identidade. O comando recusa sobrescrever chaves e aplica
proteção ACL à chave privada em disco Windows. Faça backup seguro e mantenha a
chave privada fora do Git, dos pacotes e dos logs.

Para caminhos próprios, use `--private-key` e `--public-key` em `keygen`/`build`.
Não gere chaves privadas no filesystem WSL; use o local padrão ou `/mnt/c/...`.

A chave pública é instalada pelo `.exe` e preservada nas reinstalações. Rotação
de identidade exige uma migração deliberada; o protocolo 1 não a automatiza.

## Gerar o pacote Windows

Instale Inno Setup 6 no Windows. A versão vem de VERSION. Faça commit do estado
que será distribuído antes de gerar os pacotes.

Para os testes atuais, sem Authenticode:

```bash
./scripts/kmao.sh build --allow-unsigned --output ./dist/release-0.3.5
```

O manifesto continua assinado com RSA. Sem `--allow-unsigned`, o build exige um
provedor Authenticode. As duas opções são mutuamente exclusivas. Quando houver
um provedor configurado:

```bash
./scripts/kmao.sh build \
  --authenticode-signer /mnt/c/caminho/Provider.ps1 \
  --output ./dist/release-com-authenticode
```

O compilador Inno é procurado no PATH e nas pastas usuais do Windows. Para
informá-lo explicitamente, acrescente:

```bash
--iscc '/mnt/c/Program Files (x86)/Inno Setup 6/ISCC.exe'
```

A saída padrão, sem `--output`, é `dist/release`. Uma pasta existente não é
substituída; use uma nova saída para repetir um build. `--skip-installer` omite
somente o instalador: os demais requisitos de assinatura continuam valendo.
Um build de teste no PowerShell Linux exige `-AllowUnsigned -SkipInstaller` e gera
um ZIP de fontes, sem host/DLL compilados; não equivale ao pacote Windows completo.

| Arquivo da saída Windows | Uso |
| --- | --- |
| `kmao-setup-0.3.5.exe` | Instalação/reinstalação manual |
| `kmao-0.3.5.zip` | Atualização do código versionado |
| `kmao-manifest.json` | Versão, canal, notas e hashes assinados |
| `kmao-manifest.sig` | Assinatura RSA do manifesto |
| `kmao-release-notes.md` | Descrição da release atual |
| `payload/`, `installer-source/` | Intermediários; não anexar à release |
| `signed-uninstaller/` | Cache intermediário, quando Authenticode é usado |

O build Windows compila `Kmao.Bot.exe` com os tipos de interface/automação
incorporados e `lib/Kmao.Runtime.dll` para o logger/entradas PowerShell. As
assinaturas Authenticode, quando configuradas, são aplicadas antes de gerar o ZIP,
os hashes e o manifesto. Cada execução produz seu conjunto próprio de assinaturas.

## Publicação no GitHub

Depois de commit, build e push:

```bash
git push origin main
./scripts/kmao.sh publish --dry-run
./scripts/kmao.sh publish
```

`publish` lê VERSION e cria `v0.3.5` para esse código, com título KMAO 0.3.5 —
testes, marca prerelease e notas da saída do build. Anexa somente instalador,
ZIP, manifesto e assinatura. Não faz build, commit nem push.

Procura primeiro `dist/release-0.3.5`; se essa pasta não existir, usa `dist/release`.
Para uma pasta diferente, ou para criar apenas um rascunho:

```bash
./scripts/kmao.sh publish --output ./dist/meu-pacote
./scripts/kmao.sh publish --draft
```

Requer Python 3, Git e GitHub CLI autenticado (`gh auth login`) no WSL. Não usa
PowerShell para publicar. Verifica os arquivos, versão/canal e hash do ZIP, exige
árvore limpa e confirma que HEAD existe no GitHub. `--dry-run` valida localmente e
imprime o comando, sem acessar o GitHub. A assinatura é validada na etapa de build.

Se alterar código ou documentação incluída no pacote depois do build, gere um
novo conjunto em outra pasta antes de publicar. Se a versão já foi publicada,
use um novo número em VERSION; não substitua seus anexos. Downloads públicos
podem ser descobertos ou compartilhados mesmo sem divulgação.

## GitHub Actions

[Validate](.github/workflows/check.yml) roda em pushes/PRs, com testes portáveis e
Windows PowerShell 5.1; não usa as chaves de publicação. Testes que exigem um
desktop são limitados/pulados conforme o ambiente e não substituem testes manuais.

[Build release (manual)](.github/workflows/release.yml) usa `workflow_dispatch`.
Antes de usá-lo, configure autenticação do provedor de assinatura no runner, a
variável `KMAO_AUTHENTICODE_SIGNER` apontando ao adaptador `.ps1`, e os secrets
`KMAO_RELEASE_KEY_BASE64` e `KMAO_RELEASE_PUBLIC_KEY_BASE64` com a identidade RSA
existente. Sem provedor, o workflow falha antes de ler os segredos de produção.

Depois dessa configuração, o workflow testa, compila e envia os quatro arquivos
e as notas como artifact. `create_draft=true` cria rascunho de prerelease na tag
obtida de VERSION; a publicação continua manual. Chaves temporárias são excluídas
no final. Detalhes do provedor estão em [CODE_SIGNING.md](CODE_SIGNING.md).

## Atualização e recuperação

Os atalhos consultam as 100 releases recentes e selecionam a maior prerelease
publicada com tag `vX.Y.Z` superior à instalada. O canal é `testing`; sufixos de
versão, drafts e releases estáveis não entram nessa seleção. Recusa ou falha de
consulta inicia a versão instalada e registra o resultado em `launcher-*.log`.
Não há serviço ou tarefa agendada de verificação.

Após a confirmação, um processo separado autentica o manifesto com a chave
pública instalada, verifica o ZIP e cada arquivo e prepara a nova versão ao lado
da atual. A extração rejeita caminhos inseguros, arquivos/listas incompatíveis e
erros de sintaxe PowerShell. O encerramento de bot/logger tem até 20 segundos
para liberar a sessão; o logger tenta gravar os eventos finais. Nenhum processo
alheio é encerrado à força.

A ativação troca o estado atomicamente, guarda a versão anterior e espera até
30 segundos pela prontidão do componente solicitado. O bot sinaliza interface e
infraestrutura disponíveis; isso não exige estar verde nem concluir a mensagem
inicial. Configuração editada inválida pode manter a interface pronta, mas pausada.
O logger sinaliza após configuração, hooks e abertura do CSV. O outro componente
permanece encerrado após a atualização.

Falha de inicialização restaura a versão anterior. Um diário `pending.json`
permite recuperar a anterior na abertura após interrupção do atualizador. Para
restaurar manualmente, use KMAO Bot - Restaurar versao anterior, ou no PowerShell:

```powershell
& "$env:LOCALAPPDATA\Programs\KMAO Bot\Start-Kmao.ps1" -Rollback
```

A restauração pede confirmação. Versões antigas não são limpas automaticamente;
a desinstalação remove o código, mantendo dados do perfil. O esquema do protocolo
continua 1; a importação aditiva de configuração da 0.3.5 preserva os legados para
versões antigas. Pacotes de outro esquema são rejeitados.

## Diagnóstico

- Sem oferta: conferir instalação pelo atalho, versão em `current.json`, marca
  prerelease/tag/assets no GitHub e logs `launcher-*.log`.
- Bot cinza: conferir atividade recente, Stop manual, configuração inválida,
  documento substituído/fechado ou recusa de foco. Use Configurações e Logs.
- Pacote incompleto: extrair/copiar o conjunto inteiro; nunca somente `dev.ps1`.
- Nome antigo na bandeja: usar o build com host nativo e considerar o cache do
  Windows; execução direta de scripts ainda pertence ao PowerShell.
- Bloqueio de segurança: identificar o arquivo nos eventos do Windows; assinatura
  RSA não substitui Authenticode. Não anunciar o modo de teste como validado para SAC.

Logs de host, bot, logger, lançador e atualizador ficam em `logs/` no perfil.
Downloads usam `updates/`; uma interrupção forçada pode deixar arquivos temporários.
Veja [ROADMAP.md](ROADMAP.md) para a validação em outras contas e políticas.
