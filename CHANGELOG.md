# Alterações

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
