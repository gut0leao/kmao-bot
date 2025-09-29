# KMAO Bot (Keep-me Always On Bot)

O **KMAO Bot** é um programa para **Windows 11** que mantém o computador ativo simulando movimentos sutis de mouse e, opcionalmente, pressionando teclas de forma periódica.  
Ele foi inspirado em scripts anteriores feitos em PowerShell, agora evoluindo para uma aplicação nativa para Windows.

**✨ Novidade**: O projeto agora inclui um **Activity Logger** completo para monitoramento e análise de atividade de teclado e mouse.

---

## 🎯 Objetivo

### Bot Principal (KMAO)
Evitar bloqueio de tela, suspensão ou ativação do protetor de tela no Windows, mantendo o computador sempre ativo enquanto o KMAO Bot estiver em execução.

### Activity Logger
Registrar e analisar padrões de uso do computador, capturando eventos de mouse e teclado para análise de produtividade e comportamento de uso.

---

## ⚙️ Funcionalidades

### 🤖 KMAO Bot (Keep-me Always On)

- Movimenta o **cursor do mouse** dentro de uma pequena área retangular no **centro da tela**.  
- Intervalo de tempo configurável entre os movimentos (ex.: a cada 30s, 1min, 5min).  
- Simulação opcional de **pressões leves de tecla** (ex.: `Shift` ou `Ctrl`).  
- **Botão Iniciar/Parar** para controlar a execução.  
- Fecha de forma limpa, interrompendo automaticamente a simulação.  
- (Opcional) Rodar em **background** com opção de minimizar para a bandeja do sistema.

### 📊 Activity Logger

- **Monitoramento em tempo real** de eventos de mouse e teclado
- **Registro de movimentos do mouse** com coordenadas e timestamps precisos
- **Captura de teclas pressionadas** para análise de padrões de digitação
- **Exportação para CSV** com dados estruturados para análise posterior
- **Configuração flexível** de intervalos de amostragem e duração de gravação
- **Execução via scripts** PowerShell e Batch para facilidade de uso
- **Hooks de baixo nível** do Windows para captura eficiente de eventos  

---

## 🛠️ Requisitos Técnicos

### KMAO Bot
- Compatível com **Windows 11**.  
- Implementação preferencial em **C# (WinForms ou WPF)**, mas pode ser em outra linguagem adequada para gerar executáveis no Windows.  
- Gerar um **executável instalável (.exe)**.  
- Código deve ser bem estruturado e comentado.

### Activity Logger
- **Windows 10/11** com PowerShell 5.1 ou superior
- **Assemblies .NET**: `System.Windows.Forms` e `System.Drawing`
- **APIs Windows**: User32.dll e Kernel32.dll para hooks de sistema
- **Permissões**: Política de execução PowerShell configurada (`RemoteSigned` ou `Bypass`)  

---

## 🚀 Como Usar

### 🎮 Activity Logger

O Activity Logger está **funcionando e testado**! Para usar:

#### Execução Rápida
```batch
# Via arquivo batch (mais simples)
.\init_recording.bat

# Via PowerShell direto
powershell.exe -ExecutionPolicy Bypass -File ".\activity_logger.ps1"
```

#### Execução via VS Code
1. **F5** → Selecione "Run KMAO Logger (PowerShell)"
2. **Debug PowerShell** → Use "Debug PowerShell Script" para debugging com breakpoints
3. **Tasks** → `Ctrl+Shift+P` → "Tasks: Run Task" → "KMAO Activity Logger"

#### Configuração
- **Arquivo de configuração**: `config/kmao.conf` (criado automaticamente)
- **Intervalo de amostragem**: Padrão 200ms para movimento do mouse
- **Duração máxima**: Padrão 8 horas (480 minutos), configurável
- **Saída**: Arquivos CSV em `data/` com timestamp

#### Estrutura de Dados CSV
```csv
Timestamp,EventType,Data,WindowTitle,ProcessName
2025-09-29 11:51:23.456,MouseMove,"X:150 Y:200",Visual Studio Code,Code
2025-09-29 11:51:24.123,KeyPress,A,Visual Studio Code,Code
```

---

## 🚀 Extras desejáveis

### KMAO Bot
- Ícone do programa com as letras **KMAO** estilizadas.  
- Logs simples (console ou arquivo `.txt`) para depuração.

### Activity Logger ✅ IMPLEMENTADO
- ✅ **Configuração via arquivo** (`config/kmao.conf`)
- ✅ **Exportação CSV** estruturada
- ✅ **Execução via VS Code** (F5, Debug, Tasks)
- ✅ **Hooks de sistema** para captura eficiente
- ✅ **Detecção automática de dependências**  

---

## 📦 Próximos Passos

### KMAO Bot (Em desenvolvimento)
1. Implementar a versão inicial em C# com interface simples.  
2. Adicionar opção de configurar intervalo entre os movimentos.  
3. Implementar minimização para a bandeja.  
4. Criar instalador para distribuição.

### Activity Logger ✅ COMPLETO
- ✅ **Sistema de captura** implementado e funcionando
- ✅ **Scripts de execução** (PowerShell + Batch)
- ✅ **Configuração VS Code** (Launch, Tasks, Debug)
- ✅ **Exportação de dados** em formato CSV
- 🔄 **Melhorias futuras**: Interface gráfica, análise de dados, relatórios

## 📁 Estrutura do Projeto

```
kmao-bot/
├── 📄 README.md                    # Este arquivo
├── 📄 ACTIVITY_LOGGER_SPEC.md     # Especificação técnica
├── 📄 LICENSE                     # Licença do projeto
├── 🔧 init_recording.bat          # Launcher principal
├── 🔧 dev.bat / dev.ps1           # Scripts de desenvolvimento
├── 📜 activity_logger.ps1         # Script principal de logging
├── 📁 config/
│   └── 📄 kmao.conf.example       # Configuração exemplo
├── 📁 data/                       # Arquivos CSV de saída
└── 📁 .vscode/                    # Configuração VS Code
    ├── 📄 launch.json             # Configurações F5/Debug
    └── 📄 tasks.json              # Tasks do projeto
```  

---

## � Privacidade e Segurança

### Activity Logger
- **⚠️ IMPORTANTE**: Este é um keylogger para fins legítimos de análise pessoal
- **Uso responsável**: Utilize apenas em seus próprios dispositivos
- **Dados locais**: Todos os dados ficam armazenados localmente no seu computador
- **Sem transmissão**: Nenhum dado é enviado para serviços externos
- **Transparência**: Código fonte aberto para auditoria de segurança

---

## �📜 Licença

Este projeto poderá ser publicado sob uma licença open source (a definir, ex.: MIT ou GPL).

---

**Desenvolvido com ❤️ para automação e análise de produtividade**
