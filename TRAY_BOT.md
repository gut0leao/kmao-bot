# Bot pela bandeja e Notepad próprio — 0.3.0

## Uso

Inicie **KMAO Bot** pelo menu Iniciar. O programa cria uma janela própria do
Notepad do Windows, maximizada, e coloca a mensagem inicial:

```text
KMAO BOT running...
```

O bot começa em modo **Run**. O ícone na área de notificação é uma carinha de robô
verde; em **Stop**, fica cinza. No Windows 11, o ícone pode estar dentro da área de
ícones ocultos, acessível pela seta da bandeja.

Clique com o botão direito no ícone:

Desde a versão 0.3.3, o cabeçalho desse menu mostra a versão em execução, por exemplo
`KMAO 0.3.3`. Ele permite confirmar a versão após uma atualização.

| Opção | Comportamento |
| --- | --- |
| Run | Aparece quando parado. Retoma o bot e ativa/maximiza seu Notepad; cria outro se a janela anterior foi fechada. |
| Stop | Aparece quando habilitado. Cancela o ciclo atual e mantém o Notepad aberto para retomar depois. |
| Logs | Abre um console PowerShell com as últimas 50 linhas do log da execução e `Get-Content -Wait`, equivalente a `tail -f`. |
| Open logs folder | Abre `%USERPROFILE%\.kmao-bot\logs` no Explorador de Arquivos para consultar os logs do bot, lançador e atualizador. |
| About | Abre o projeto `https://github.com/gut0leao/kmao-bot` no navegador. |
| Exit | Encerra o bot, descarta seu documento sem salvar e remove o ícone da bandeja. |

Um duplo clique no ícone alterna entre Run e Stop. Fechar a janela de Logs não
encerra o bot. Os logs pertencem à execução atual e não incluem as frases digitadas.

O modo Run habilita a automação, mas ainda respeita o limite de inatividade e os
intervalos de `config/bot.conf`. Por padrão, aguarda 60 segundos de inatividade e
mais um intervalo aleatório de 30 a 239 segundos antes de interagir. A cor verde
indica Run habilitado; ela não significa que o bot esteja digitando naquele instante.

## Escopo da interação

- O alvo é sempre o documento do Notepad criado pelo bot. A seleção do alvo não
  acompanha outras janelas em primeiro plano.
- A escrita é enviada diretamente ao controle de edição desse documento, como
  texto Unicode, incluindo caracteres especiais e emojis. Não usa teclas globais
  para digitar nem envia Enter para outros programas.
- Os cliques ficam no retângulo central da área de edição, limitado ao tamanho
  atual do editor. Antes de mover/clicar, o bot confirma o foco, a inatividade e
  que o ponto pertence ao editor e não está coberto por outro controle/janela. O
  clique é enviado ao próprio editor, sem pressionar botões globalmente em outros
  aplicativos. O movimento do cursor usa entrada identificada como sendo do bot.
- Se você usar mouse/teclado, trocar para outra janela ou selecionar outra aba do
  Notepad, o ciclo é interrompido. O bot não recupera o foco por conta própria.
- Run é uma ação explícita que pode trazer o Notepad do bot de volta ao foco.
- Se fechar o Notepad, o bot fica em Stop. Use Run para criar um novo documento.
- Se substituir o documento ou remover a mensagem inicial, o bot pausa e preserva
  o conteúdo. Use Run para abrir outra janela própria. O bot verifica somente o
  prefixo fixo de identificação, sem registrar o conteúdo do documento.

Mantenha a mensagem inicial no documento enquanto quiser que ele seja usado pelo
bot. Esse documento é descartável: não o use para anotações que deseja preservar.
Se salvar manualmente o documento ou abrir outro arquivo na mesma aba, ele deixa
de ser descartável: o bot pausa e o preserva. Use Run para criar outro documento.

## Notepad do Windows 11 e encerramento

O Notepad moderno pode restaurar sessões anteriores e agrupar arquivos em abas.
O KMAO usa os controles de automação do Notepad para criar uma nova janela isolada,
sem reutilizar uma anotação restaurada. As outras janelas e abas são preservadas.
A abertura do aplicativo pelo Windows pode restaurar essas outras sessões; o bot
não altera essa preferência global do Notepad nem fecha as sessões restauradas.

Ao sair, o bot limpa o texto do seu documento, remove a marca de alteração e fecha
somente a própria aba/janela. Se houver outras abas na janela, preserva-as. Ele não
mata processos Notepad, não salva automaticamente arquivos e não altera o conteúdo
de outras anotações. Se não puder confirmar a propriedade do documento, preserva-o
em vez de apagá-lo. Uma falha de automação é registrada nos logs.

Use Exit para finalizar normalmente. Se fechar primeiro a janela do Notepad pelo
X, o próprio Notepad pode salvar sua sessão antes de o bot perceber o fechamento;
para garantir o descarte do texto pelo KMAO, prefira Exit no ícone da bandeja.
Fechamento forçado pelo Gerenciador de Tarefas,
queda de energia ou término abrupto do processo podem impedir a limpeza. O menu Exit
e o encerramento cooperativo do atualizador passam pela rotina de descarte.

A interface requer **Windows PowerShell 5.1**, Notepad instalado e um desktop Windows
interativo e desbloqueado. Notepad clássico e o moderno são tratados separadamente;
a automação de menus do Notepad moderno precisa estar disponível. Diálogos de
primeira execução, permissões ou versões com controles incompatíveis podem impedir
a abertura. Nesse caso, o programa registra o erro e preserva os documentos existentes.

A janela de console do bot é ocultada quando pertence exclusivamente ao lançamento
independente do aplicativo. Consoles compartilhados/interativos são preservados.

## Configuração e compatibilidade

As configurações e frases existentes continuam em `%USERPROFILE%\.kmao-bot`.
O esquema permanece 1; não é necessário apagar ou recriar `bot.conf`.

As mesmas opções de intervalos, quantidade de cliques e chance de digitação continuam
válidas. A área de cliques agora é limitada ao editor, em vez da tela principal.
O Activity Logger continua independente. Ele pode registrar os movimentos do
cursor feitos pelo bot; os cliques e textos enviados diretamente ao editor não
geram eventos globais de mouse/teclado no logger.

Os ícones verde/cinza são desenhados pelo próprio código com GDI+, sem dependência
de imagens externas. Os callbacks da bandeja rodam em uma thread STA C# e alteram
apenas o estado do controlador; não executam scriptblocks PowerShell nessa thread.

## Desenvolvimento e testes pelo WSL

```bash
./scripts/kmao.sh test
./scripts/kmao.sh desktop-test
```

O primeiro comando inclui compilação dos componentes, ícones, ciclo da bandeja,
acompanhamento de logs e testes portáveis/sessão/build. O segundo é explicitamente
interativo: abre e descarta um documento de teste e valida o processo completo do
bot com perfil temporário e ciclos de interação desabilitados. Feche outra instância
do KMAO antes desse teste. Outros documentos do Notepad não são usados como alvo.

No teste de processo completo, o bot precisa sinalizar prontidão dentro de 30 segundos
e encerrar dentro de 20 segundos após o pedido de parada do atualizador. Isso valida
a integração com o protocolo de atualização das versões anteriores.

## Atualização automática

A 0.3.1 corrige a consulta à API do GitHub no Windows PowerShell 5.1, mantendo
o protocolo e a identidade de assinatura. Usuários das versões até 0.3.0 precisam
instalar `kmao-setup-0.3.1.exe` manualmente uma vez: o defeito está no atualizador
já instalado. As próximas versões poderão ser oferecidas ao abrir os atalhos,
com confirmação antes da instalação.

Esses recursos estão no código versionado e não exigem recriar os atalhos para
funcionar. A publicação deve incluir o ZIP, o instalador e o par manifesto/assinatura
produzidos juntos. A versão anterior permanece disponível para recuperação.
