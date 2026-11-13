# Alterações

## 0.3.4

- Executa o bot no processo próprio `Kmao.Bot.exe`, com descrição e produto `KMAO Bot`, em vez de hospedar a bandeja no `powershell.exe`.
- Define a identidade `Kmao.Bot` no processo, mantendo a mesma identidade dos atalhos existentes.
- Preserva a consulta de atualização no lançador, os eventos de prontidão/encerramento, a bandeja e a automação no Notepad.
- Mantém o PowerShell 5.1 dentro do processo do aplicativo; a correção funciona por atualização automática, sem recriar atalhos.

O Windows pode manter a entrada antiga `Windows PowerShell` em cache na configuração da bandeja. A nova execução usa `KMAO Bot`. Os pacotes de teste continuam sem Authenticode; a assinatura RSA das atualizações permanece a mesma.

## 0.3.3

- Reutiliza a janela recém-aberta do Notepad quando vazia e sem título, evitando uma segunda janela desnecessária sem alterar sessões anteriores.
- Digita `KMAO BOT is running...` caractere por caractere; a mensagem pausa com atividade do usuário e continua ao retomar.
- Fica cinza ao detectar atividade e retoma automaticamente após o limite de inatividade, maximizando/ativando seu Notepad antes de ficar verde.
- Mantém Stop manual até Run; falha de foco e documento fechado/substituído permanecem pausados.

- Exibe a versão instalada no cabeçalho do menu da bandeja.
- Adiciona `Open logs folder` para abrir a pasta de logs no Explorador de Arquivos.

### Teste de atualização da 0.3.2

Feche o bot e abra novamente pelo atalho instalado. Aceite a atualização para 0.3.3 e confira `KMAO 0.3.3` no menu da bandeja e a opção `Open logs folder`. Configurações, frases e gravações são preservadas. O pacote de teste continua sem Authenticode; a assinatura RSA das atualizações permanece a mesma.

## 0.3.2

A infraestrutura Authenticode foi preparada; a emissão/configuração do certificado e o teste com Smart App Control ativo permanecem pendentes. Os pacotes de teste foram gerados sem Authenticode por opção explícita.

- Adiciona `./scripts/kmao.sh publish`, baseado em `VERSION`, com publicação de prerelease, modo rascunho e simulação local.
- Exige provedor Authenticode no build de distribuição; permite build de desenvolvimento sem assinatura apenas por opção explícita.
- Prepara assinatura de scripts, runtime C# pré-compilado, dispatcher, instalador, desinstalador e cópias temporárias do Inno Setup.
- Calcula ZIP e hashes depois da assinatura e verifica finalidade Code Signing, cadeia reconhecida pelo Windows e timestamp.
- Adiciona adaptador para certificado em token/HSM exposto no repositório do Windows, sem exportação de chave ou captura de PIN.
- Documenta os requisitos do certificado, as limitações de A3/gov.br e a emissão pendente; pausa o workflow de release até configurar o provedor.

## 0.3.1

- Corrige a leitura da lista de releases no Windows PowerShell 5.1, que impedia a oferta de atualizações sem registrar erro.
- Registra a consulta, a disponibilidade ou ausência de nova versão e a recusa da atualização nos logs do lançador.
- Adiciona regressão com arrays não enumerados, como os retornados pela API real, incluindo listas vazias e com uma única release.

### Instalações anteriores

Instale `kmao-setup-0.3.1.exe` manualmente uma vez, após fechar o bot e o logger. As versões até 0.3.0 contêm o defeito na consulta e não conseguem obter esta correção automaticamente. Configurações, frases e gravações são preservadas. As próximas versões poderão ser oferecidas ao iniciar pelos atalhos da instalação.

## 0.3.0

- Abre um Notepad próprio, maximizado, com a mensagem `KMAO BOT running...`.
- Restringe cliques e texto ao documento criado pelo bot; interrompe o ciclo ao detectar atividade do usuário ou mudança de foco/aba.
- Adiciona execução pela bandeja com carinha de robô verde em Run e cinza em Stop.
- Inclui Run, Stop, Logs, About e Exit no menu da bandeja; duplo clique alterna Run/Stop.
- Abre acompanhamento dos logs em tempo real em uma janela PowerShell.
- Descarta o documento do bot sem salvar ao sair ou atualizar, preservando outras abas e janelas do Notepad.
- Preserva o documento e pausa se ele for substituído ou se a mensagem inicial for removida.
- Mantém configurações e frases existentes, com suporte a texto Unicode e emojis.
- Valida a inicialização da interface e o encerramento cooperativo dentro dos limites do atualizador.

### Atualização da 0.2.1

Os recursos desta versão funcionam pela atualização automática do código, sem recriar os atalhos. Abra o bot pelo atalho da instalação e aceite a atualização. O ícone pode aparecer na área de ícones ocultos da bandeja. Verde significa Run habilitado; a automação ainda aguarda inatividade e só atua no Notepad próprio em primeiro plano. Use Exit para descartar esse documento e encerrar.

## 0.2.1

- Corrige os atalhos do menu Iniciar para incluir o nome KMAO Bot e permitir sua localização pela pesquisa do Windows.
- Define identidades próprias para os atalhos do bot, do logger e da restauração.
- Remove os atalhos com nomes genéricos ao reinstalar com o instalador corrigido.
- Adiciona comandos de diagnóstico, testes, assinatura e build diretamente pelo WSL.
- Corrige caminhos UNC, geração de chaves RSA e serialização do manifesto no Windows PowerShell 5.1.
- Evita colisões de nomes dos logs em inicializações rápidas no Windows.
- Valida os testes de sessão e a compilação do instalador pelo WSL.

### Instalações da versão 0.2.0

Para corrigir os atalhos de uma instalação existente, execute `kmao-setup-0.2.1.exe` após fechar o bot e o logger. Configurações e gravações são preservadas. A atualização somente pelo ZIP não recria os atalhos do instalador.

## 0.2.0

- Instalador por usuário e atalhos para bot e logger.
- Consulta de novas versões ao iniciar, com confirmação antes da atualização.
- Pacotes assinados, instalação por versões e recuperação da versão anterior.
- Encerramento cooperativo para preservar os eventos do logger durante atualizações.
