# Próximas melhorias: instalação e atualização

Status: implementação inicial concluída no código. O projeto inclui instalador
Inno Setup, lançador, atualizador com confirmação, assinatura de pacotes, troca
atômica de versão, recuperação e workflows de validação/build manual. O pacote
portátil continua disponível. Consulte [INSTALLATION.md](INSTALLATION.md).

Validação local: testes portáveis e testes no Windows PowerShell 5.1 acessando o
repositório pelo WSL, incluindo código, criptografia, empacotamento, continuidade
sem conexão/recusa, recuperação e eventos/mutexes entre processos. A compilação do
`.exe` também foi validada no Windows via WSL. Os hooks em desktop e a validação
manual completa de instalação, atualização e desinstalação seguem como critérios
de aceitação para os testes com convidados. A identidade RSA de produção e
as releases iniciais já existem. A 0.3.2 prepara Authenticode, mas a emissão do
certificado e a validação com Smart App Control ativo ainda estão pendentes.
Veja [CODE_SIGNING.md](CODE_SIGNING.md).
A mudança de esquema de configuração é rejeitada; a migração permanece futura.

## Público e distribuição

- Uso pessoal inicialmente, com algumas pessoas convidadas para testar.
- Downloads públicos em GitHub Releases, sem divulgação ampla nesta fase.
- Um link público pode ser descoberto ou compartilhado; isso não oferece controle
  de acesso nem confidencialidade.
- Um único canal de versões de teste no início, com versão explícita, notas de
  alteração e pacote correspondente a cada publicação.
- A publicação da primeira versão será uma etapa posterior, quando o responsável
  pelo projeto decidir compartilhá-la.

## Instalação

- Usar Inno Setup para gerar um instalador `.exe`, mantendo os scripts atuais.
- Instalar por usuário, sem solicitar privilégios de administrador, em
  `%LOCALAPPDATA%\Programs\KMAO Bot`.
- Distribuir todas as dependências do aplicativo, incluindo `lib/`, modelos de
  configuração e modelo de frases.
- Criar atalhos no menu Iniciar para o bot e o logger, usando um lançador comum.
- Registrar a versão instalada e permitir a desinstalação pelo Windows.
- Manter configurações, frases, gravações e logs em `%USERPROFILE%\.kmao-bot`.
- Preservar esses dados em reinstalações, atualizações e na desinstalação padrão.
- Prever a transição da execução portátil para a instalada, reutilizando a pasta
  de dados existente.
- Não criar serviço nem tarefa agendada para verificação em segundo plano.

## Atualização ao iniciar

1. Ao abrir o bot ou o logger, o lançador consulta a versão disponível no canal
   de testes e compara com a instalada.
2. Se houver uma versão mais recente, exibe as versões, as notas de alteração e
   pede confirmação para atualizar. Uma versão recusada pode ser oferecida
   novamente na próxima inicialização.
3. Se o usuário recusar, não houver atualização ou a consulta falhar por falta de
   conexão, inicia o componente solicitado na versão instalada.
4. Se o usuário aceitar, baixa o pacote para uma área temporária e valida sua
   integridade e autenticidade antes de executar ou substituir qualquer arquivo.
5. Coordena o encerramento limpo dos componentes do KMAO em execução, incluindo
   gravação dos eventos restantes do logger e remoção dos hooks. Se não for
   possível encerrá-los com segurança, adia a instalação.
6. Um processo separado aplica a atualização e reabre o componente solicitado.
   Não substitui arquivos enquanto o bot ou o logger ainda os utiliza.

Toda atualização exige confirmação. O lançador deve continuar distinguindo
claramente falhas de atualização das falhas do próprio bot ou logger, com logs
que ajudem a diagnosticar ambas.

## Integridade, recuperação e configuração

- Validar os pacotes por assinatura, com chave pública confiável distribuída no
  atualizador; um hash isolado não autentica o publicador.
- Manter a chave privada de publicação fora do repositório e dos pacotes,
  armazenando-a de forma segura para assinar as versões.
- Avaliar certificado de assinatura de código para instalador e scripts como
  decisão adicional de distribuição; nenhum certificado foi adquirido ou definido.
- Rejeitar pacotes incompletos, adulterados, incompatíveis ou de origem inesperada.
- Impedir atualizações simultâneas por duas instâncias do lançador.
- Preservar a versão anterior até concluir a instalação e permitir sua restauração
  caso a atualização falhe.
- Não sobrescrever configurações ou frases personalizadas. Se novas versões
  alterarem o formato da configuração, definir migração e cópia de segurança.
- Não incluir dados pessoais, gravações, logs ou chaves privadas nas Releases.

## Sequência de implementação

1. **Instalador e lançador:** versionamento, empacotamento completo, atalhos,
   instalação por usuário, desinstalação e preservação de dados.
2. **Publicação:** geração reproduzível em Windows, testes, assinatura e preparação
   das Releases. Publicar somente quando for decidido compartilhar a versão.
3. **Atualizador com confirmação:** consulta ao iniciar, download validado,
   coordenação do encerramento, aplicação, recuperação e reinício.

## Validação necessária

- Instalação e desinstalação em uma conta sem privilégios de administrador.
- Atalhos e inicialização do bot e do logger fora da pasta de instalação.
- Atualização aceita e recusada, versão já atualizada e execução sem internet.
- Download interrompido, assinatura inválida, pacote incompatível e instalação
  incompleta, mantendo uma versão utilizável do aplicativo.
- Duas inicializações simultâneas e tentativa de atualização durante uma gravação.
- Encerramento dos hooks, gravação final do CSV e reinício do componente solicitado.
- Preservação de frases, configurações e gravações, incluindo eventuais migrações.
- Recuperação da versão anterior após falha.

Referências: [Inno Setup](https://jrsoftware.org/isinfo.php),
[instalação sem administrador](https://jrsoftware.org/ishelp/topic_setup_privilegesrequired.htm),
[GitHub Releases](https://docs.github.com/en/repositories/releasing-projects-on-github/about-releases)
e [assinatura de scripts PowerShell](https://learn.microsoft.com/powershell/module/microsoft.powershell.core/about/about_signing).


## Implementado na 0.3.0: Notepad próprio e bandeja

- Janela isolada e maximizada do Notepad com mensagem inicial e texto restrito ao editor.
- Ícones de robô verde/cinza, Run/Stop, Logs ao vivo, About e Exit.
- Descarte sem salvar do documento criado pelo bot e preservação de outras abas/janelas.
- Pausa e preservação do documento quando seu conteúdo deixa de ser identificado como pertencente ao bot.
- Integração com o encerramento cooperativo e a prontidão exigidos pelo atualizador.
- Testes Windows dos ícones, controles, logs e do processo completo usando perfil temporário.

Uso e limites: [TRAY_BOT.md](TRAY_BOT.md). O fluxo real de atualização entre Releases
publicadas continua sendo validado com as instalações de teste.
