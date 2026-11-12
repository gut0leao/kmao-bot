# Alterações

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
