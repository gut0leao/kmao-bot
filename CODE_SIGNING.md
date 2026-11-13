# Assinatura do publicador Windows

A distribuição para computadores com Controle Inteligente de Aplicativos (Smart
App Control/SAC) está pendente de um certificado de assinatura de código emitido
por um provedor confiável e da validação de uma instalação com SAC ativo.
Não há certificado de produção configurado. Esta preparação do build, sozinha,
não torna os instaladores 0.3.1 e anteriores confiáveis para o Windows.

## Duas assinaturas diferentes

- A chave RSA em `%USERPROFILE%\.kmao-signing` autentica o manifesto e os hashes
  das atualizações dentro do KMAO. Ela continua necessária e não deve ser trocada.
- Authenticode identifica o publicador perante o Windows. Precisa de certificado
  com finalidade **Code Signing** (EKU `1.3.6.1.5.5.7.3.3`) e cadeia confiável.
  Certificados autoassinados ou a importação manual de uma raiz não demonstram
  compatibilidade com SAC e não fazem parte desta solução.

Um A3 identifica a forma de proteção da chave; isso não implica Code Signing.
Certificados de autenticação, e-mail, e-CPF/e-CNPJ ou assinatura de documentos não
são automaticamente apropriados. A assinatura de documentos pelo gov.br não
substitui a assinatura Authenticode de executáveis.

## Obter o certificado

Opções a avaliar antes de contratar:

- Programa gratuito para projetos abertos, como SignPath Foundation: aprovação
  sujeita às regras do programa. Não é automático nem garantido.
- Certificado de assinatura de código para pessoa física, de autoridade que
  atenda residentes no Brasil. Confirme finalidade, cadeia aceita pelo Windows,
  suporte a `.ps1`/`.dll`/`.exe`, timestamp e integração com token/HSM ou nuvem.
- Azure Artifact Signing: a documentação consultada limita pessoas físicas aos
  EUA e Canadá; não é uma opção confirmada para pessoa física no Brasil.

A emissão, a validação de identidade e eventuais pagamentos devem ser feitos pelo
responsável pelo projeto. Não envie PFX, chaves, PIN, senha ou documentos ao chat.

Fontes consultadas em 12/11/2026:

- [Microsoft: certificados e assinatura para SAC](https://learn.microsoft.com/en-us/windows/apps/develop/smart-app-control/code-signing-for-smart-app-control).
- [Microsoft: disponibilidade do Artifact Signing](https://learn.microsoft.com/en-us/azure/artifact-signing/quickstart).
- [SignPath Foundation: condições](https://signpath.org/terms.html).
- [Microsoft: App Control e PowerShell](https://learn.microsoft.com/en-us/powershell/scripting/security/app-control/how-app-control-works).
- [Inno Setup: SignedUninstaller](https://jrsoftware.org/ishelp/topic_setup_signeduninstaller.htm).

## Contrato do provedor de assinatura

O build recebe `--authenticode-signer /mnt/c/.../Provider.ps1`. O script roda no
Windows PowerShell 5.1 e deve aceitar exatamente um arquivo em `-Path`, assiná-lo
**no mesmo caminho**, adicionar timestamp confiável e retornar código zero.
O processo herda o ambiente do build; segredos não devem ser argumentos.
O build verifica a assinatura, a finalidade Code Signing e a presença de timestamp
após cada arquivo. Falhas interrompem a geração: não há fallback sem assinatura.
Uma assinatura válida na máquina de build ainda exige teste de SAC em outra máquina,
com cadeias públicas e sem certificados de teste instalados.

A integração permite um adaptador local/token ou um adaptador de serviço remoto.
O adaptador de um serviço remoto precisa implementar a autenticação e aguardar a
assinatura do arquivo. Não há integração SignPath/Azure pronta nem conta criada.

### Certificado exposto no repositório do Windows

Para um certificado adequado já emitido, há um adaptador em
`scripts/Sign-KmaoFile.ps1`, baseado em `Set-AuthenticodeSignature`. Ele procura o
certificado em `Cert:\CurrentUser\My`, pelo thumbprint público. O middleware do
provedor pode pedir o PIN do token; o KMAO não lê nem armazena esse PIN.

No WSL, configure somente dados públicos, usando os valores do provedor:

```bash
export KMAO_AUTHENTICODE_THUMBPRINT='THUMBPRINT_DE_40_HEXADECIMAIS'
export KMAO_AUTHENTICODE_TIMESTAMP_URL='URL_DO_TIMESTAMP_DO_PROVEDOR'
# Variáveis precisam ser propagadas ao Windows pela interoperabilidade WSL.
export WSLENV="${WSLENV:+$WSLENV:}KMAO_AUTHENTICODE_THUMBPRINT:KMAO_AUTHENTICODE_TIMESTAMP_URL"
./scripts/kmao.sh build \
  --authenticode-signer ./scripts/Sign-KmaoFile.ps1 \
  --output ./dist/release-com-authenticode
```

O timestamp deve ser compatível com `Set-AuthenticodeSignature`; provedores que
exigem outra ferramenta devem usar seu próprio adaptador. Não é necessário
exportar a chave privada nem gerar outra chave RSA do atualizador.

## Ordem do build

1. Copia os arquivos para `payload`, sem alterar o código de trabalho.
2. No Windows PowerShell 5.1, compila os três arquivos C# em
   `lib/Kmao.Runtime.dll`, com as referências de .NET Framework e UI Automation.
3. Assina todos os `.ps1`, `.dll` e `.exe` do payload. Os scripts recebem UTF-8
   com BOM antes da assinatura, para Windows PowerShell 5.1.
4. Gera o ZIP, os hashes e o manifesto RSA a partir dos **bytes já assinados**.
5. Copia o dispatcher `Start-Kmao.ps1` já assinado para a raiz da instalação.
6. Compila com o SignTool integrado do Inno Setup e `SignedUninstaller=yes`.
   O callback verifica Setup, Uninstall e as cópias temporárias que o Inno assina;
   o resultado do instalador e o cache do desinstalador são verificados novamente.

Assinar apenas o `.exe` final não cobre o desinstalador nem as cópias temporárias
do Inno Setup. Não altere arquivos assinados após gerar o manifesto.

Com a DLL presente, o aplicativo a carrega diretamente. O checkout e o export
portátil simples ainda podem compilar os fontes C# ao iniciar para desenvolvimento;
isso não constitui uma distribuição validada para SAC.

## Desenvolvimento e CI

Build sem Authenticode agora exige consentimento explícito para desenvolvimento:

```bash
./scripts/kmao.sh build --allow-unsigned --output ./dist/dev-sem-authenticode
```

Essa opção não corrige o bloqueio do Windows. Os testes usam chaves RSA temporárias
e esse modo; não simulam que um certificado autoassinado seja publicamente aceito.
O workflow de release falha antes de ler os segredos de produção até que o provedor
seja escolhido e sua autenticação configurada no runner. Configure a variável de
repositório `KMAO_AUTHENTICODE_SIGNER` com o caminho do adaptador `.ps1` presente
no runner e acrescente a etapa de autenticação do serviço escolhido; um token
local não fica automaticamente disponível em runners hospedados do GitHub. O workflow de validação
continua funcionando. Nenhuma publicação ocorre nesta preparação.

## Aceitação antes de publicar

- Emitir o certificado ou obter aprovação no programa escolhido.
- Executar um build com o provedor real; conferir assinaturas e timestamp de
  scripts, DLL, dispatcher estável, instalador e desinstalador.
- Testar instalação, Run/Stop/Logs/Exit, logger, atualização e desinstalação em
  Windows com SAC ativo. Não modificar a política nem as raízes de confiança.
- Se houver bloqueio, usar os eventos CodeIntegrity/AppLocker para identificar
  o componente específico. Assinatura não garante aceitação por toda política
  corporativa ou ausência de detecção por antivírus.
- Publicar em uma **nova versão**; não substituir os anexos já publicados.
