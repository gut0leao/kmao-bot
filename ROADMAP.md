# Estado do projeto e próximos passos

Referência: código **0.3.5**, definido em [VERSION](VERSION). O produto está em
fase de testes pessoais e com convidados, com downloads públicos no GitHub e
sem divulgação ampla. Os guias operacionais estão no [README](README.md).

## Implementado

| Área | Estado atual |
| --- | --- |
| Instalação | Inno Setup por usuário, atalhos identificáveis e desinstalação que preserva dados |
| Atualização | Consulta ao iniciar, confirmação, manifesto RSA, hashes por arquivo e versão instalada separadamente |
| Recuperação | Estado atômico, versão anterior e diário para atualização interrompida |
| Sessões | Uma instância de bot e uma de logger por sessão de desktop; encerramento cooperativo |
| Bandeja | Run, Stop, Configurações, Logs, Open logs folder, About e Exit |
| Notepad | Documento próprio, mensagem gradual, foco confirmado e descarte no encerramento normal |
| Atividade | Pausa cinza por atividade; retomada após inatividade; Stop manual preservado |
| Identidade | `Kmao.Bot.exe` com descrição KMAO Bot e PowerShell 5.1 hospedado no processo |
| Configuração | 31 parâmetros comentados em `application.conf`, importação dos legados e validação a cada entrada em Running |
| Logger | Hooks com message pump, fila limitada, CSV e esvaziamento final |
| WSL | Diagnóstico, testes, export, build e publicação pelo `kmao.sh` |
| Publicação | `publish` usa VERSION e quatro assets, com rascunho e simulação local |
| Authenticode | Infraestrutura de build/adaptador pronta; certificado/provedor ainda não configurado |

As configurações legadas são importadas de forma aditiva na 0.3.5. Isso não altera
o esquema 1 do protocolo de atualização. Migrações entre esquemas incompatíveis
continuam pendentes; esses pacotes são rejeitados pelo atualizador.

## Validação realizada

- Testes portáveis e no Windows PowerShell 5.1 via WSL para sintaxe, estrutura
  nativa de entrada, configuração/migração e cancelamento com monitor simulado.
- Assinaturas RSA, integridade/extração, seleção do canal, indisponibilidade de
  rede, recusa, recuperação e coordenação com eventos/mutexes reais.
- Host nativo: identidade, execução STA, saída, códigos de retorno e `finally`.
- Bandeja: cores, Run/Stop, configuração antes de Running e acompanhamento de logs.
- Notepad e processo completo em testes interativos, com perfis temporários e
  documentos próprios; prontidão em até 30 s e encerramento em até 20 s.
- Compilação do instalador Windows diretamente do checkout WSL.
- Instalação e atualização automática confirmadas pelo responsável em sua máquina.

Essas evidências não substituem uma matriz de compatibilidade nem confirmam
aceitação universal pelo Smart App Control. Os pacotes atuais de teste continuam
sem Authenticode, embora as atualizações sejam autenticadas por RSA.

## Prioridades pendentes

1. **Assinatura do publicador:** obter certificado Code Signing ou aprovação em
   programa de assinatura, configurar o provedor e validar o conjunto em Windows
   protegido. Veja [CODE_SIGNING.md](CODE_SIGNING.md).
2. **Aceitação com convidados:** instalar/desinstalar em outras contas sem admin,
   verificar atalhos, identidade na bandeja, atualização aceita/recusada e execução
   sem internet. Não substituir assets já publicados para repetir um teste.
3. **Uso prolongado:** verificar logger por duração, Ctrl+C, atualização durante
   gravação, falhas de disco/permissão e preservação dos eventos finais.
4. **Compatibilidade do Notepad:** testar restauração de sessões, abas, idiomas,
   documentos salvos/substituídos, indisponibilidade da automação e recusa de foco.
5. **Operação contínua:** avaliar rotação/retenção de logs e gravações, limpeza de
   versões antigas/downloads interrompidos e recuperação de hooks removidos.

## Critérios para compartilhar uma versão

- Código e documentação coerentes com VERSION e CHANGELOG.
- Testes adequados à mudança concluídos e limitações registradas.
- Pacotes completos, manifesto e assinatura produzidos juntos, com a identidade
  RSA existente e sem dados pessoais/chaves privadas.
- Confirmação de preservação de configurações, frases, gravações e notas pessoais
  em atualização, encerramento normal e recuperação.
- Publicação feita explicitamente pelo responsável como prerelease; toda
  atualização pelo aplicativo continua exigindo confirmação.

Não há serviço ou tarefa agendada de atualização, telemetria de uso, retenção
automática de dados, análise de produtividade pronta ou garantia de recuperação
após término forçado. Essas capacidades não devem ser anunciadas como entregues.
