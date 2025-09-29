# Activity Logger - Especificação Técnica

## Visão Geral
Sistema de logging de eventos de teclado e mouse para análise de produtividade pessoal, usando apenas ferramentas nativas do Windows 11.

## Objetivos
- Registrar eventos de teclado e mouse durante o dia de trabalho
- Usar formato compacto e eficiente para grandes volumes de dados
- Não requerer instalação de dependências externas

## Tecnologia Base
- **PowerShell** com Windows API calls
- **APIs utilizadas:**
  - `user32.dll` - Hooks de teclado e mouse
  - `SetWindowsHookEx` - Hooks globais
  - `GetMessage` - Processamento de mensagens

## Formato de Saída

### Estrutura do Arquivo CSV
```csv
t,e,x,y,k
1727621415,mc,1920,540,
1727621416,mm,1925,545,
1727621417,kd,,,A
1727621418,ku,,,A
```

### Campos
- **t** = Timestamp Unix (segundos desde 1970-01-01)
- **e** = Tipo de evento (códigos abaixo)
- **x** = Coordenada X do mouse (vazio para eventos de teclado)
- **y** = Coordenada Y do mouse (vazio para eventos de teclado)
- **k** = Tecla pressionada (vazio para eventos de mouse)

### Códigos de Eventos

#### Mouse
- **mc** = Mouse Click (qualquer botão)
- **mm** = Mouse Move
- **sc** = Scroll

#### Teclado
- **kd** = Key Down
- **ku** = Key Up

## Estratégia de Sampling

### Mouse
- **Cliques**: Registrar todos os eventos
- **Scroll**: Registrar todos os eventos
- **Movimento**: 
  - Registrar apenas quando há mudança de posição
  - Sampling configurável via `MOUSE_SAMPLING_INTERVAL` (padrão: 200ms)
  - **NÃO registrar se não houve mudança de posição**

### Teclado
- **Registrar todos os eventos** (key down e key up)
- Volume baixo, não requer sampling

## Organização de Arquivos

### Estrutura de Diretórios
```
config/
├── kmao.conf                          # Arquivo de configuração ativo
└── kmao.conf.example                  # Template de configuração

data/
├── 2025-09-29-08-30-123-recording.csv
├── 2025-09-29-14-15-456-recording.csv
└── 2025-09-30-09-00-789-recording.csv
```

### Nomenclatura de Arquivos
**Formato:** `yyyy-mm-dd-hh-mm-sss-recording.csv`

Onde:
- **yyyy-mm-dd** = Data de início da gravação
- **hh-mm** = Hora e minuto de início (24h)
- **sss** = Milissegundos de início
- **recording.csv** = Sufixo fixo

**Exemplo:** `2025-09-29-08-30-123-recording.csv`
- Gravação iniciada em 29/09/2025 às 08:30:123

## Arquivo de Configuração

### Localização
- **Arquivo ativo:** `config/kmao.conf`
- **Template:** `config/kmao.conf.example`

### Comportamento
- O programa **deve ler** o arquivo de configuração antes de iniciar a execução
- Se `config/kmao.conf` não existir, usar valores padrão
- O template `kmao.conf.example` serve como referência de configuração

### Variáveis Disponíveis

#### Sampling de Mouse
```bash
# Intervalo mínimo entre registros de movimento do mouse (em milissegundos)
MOUSE_SAMPLING_INTERVAL=200
```

#### Duração da Gravação
```bash
# Tempo máximo de gravação em minutos (0 = ilimitado)
RECORDING_DURATION_MINUTES=480
```

### Formato do Arquivo
- Formato simples `VARIAVEL=VALOR`
- Linhas iniciadas com `#` são comentários
- Valores numéricos sem aspas
- Strings podem usar aspas opcionalmente

### Exemplo de Arquivo de Configuração
```bash
# Configuração do KMAO Activity Logger

# Intervalo de sampling para movimento do mouse (ms)
MOUSE_SAMPLING_INTERVAL=200

# Duração máxima da gravação em minutos
# 480 = 8 horas de trabalho
# 0 = gravação ilimitada (até interrupção manual)
RECORDING_DURATION_MINUTES=480

# Configurações futuras podem ser adicionadas aqui
# BUFFER_SIZE=1000
# LOG_LEVEL=INFO
```

## Estimativas de Performance

### Volume de Dados
- **~25-30 bytes** por evento
- **~50 eventos/minuto** (com sampling otimizado)
- **~3.6MB por dia** (8 horas de trabalho)
- **~1MB quando comprimido** (.gz)

### Otimizações
- Buffer de escrita para melhor performance
- Rotação automática de arquivos por sessão
- Compressão opcional de arquivos antigos

## Dados Capturados

### Eventos de Mouse
- Coordenadas X,Y de cliques
- Coordenadas X,Y de movimento (apenas quando há mudança)
- Eventos de scroll
- Timestamp preciso de cada evento

### Eventos de Teclado
- Tecla pressionada/liberada
- Timestamp preciso
- Códigos de tecla padrão

## Considerações de Implementação

### Performance
- Implementar sampling inteligente para movimento do mouse
- Usar buffers para escrita em lotes
- Evitar logging desnecessário (posição inalterada)

### Privacidade
- Não registrar janelas ativas
- Não registrar conteúdo de teclado sensível (opcional)
- Dados ficam localmente no repositório

### Robustez
- Tratamento de erros de I/O
- Recuperação automática de hooks
- Logging de erros em arquivo separado
- **Finalização automática** baseada em `RECORDING_DURATION_MINUTES`
- Finalização limpa ao atingir tempo limite

## Análise Posterior

### Tipos de Análise Possíveis
- **Atividade por período**: Eventos por hora/dia
- **Padrões de movimento**: Áreas mais clicadas
- **Velocidade de digitação**: Análise temporal de teclas
- **Períodos de inatividade**: Gaps nos timestamps
- **Estatísticas de produtividade**: Volume de atividade

### Ferramentas de Análise
- Excel/LibreOffice (CSV nativo)
- Python/Pandas para análises complexas
- PowerBI para visualizações
- Ferramentas de linha de comando (awk, grep)

## Próximos Passos

1. Criar estrutura de diretórios (`config/`, `data/`)
2. Implementar arquivo de configuração `kmao.conf.example`
3. Implementar script PowerShell base
4. Implementar leitor de configuração
5. Testar hooks de teclado e mouse
6. Implementar sistema de sampling configurável
7. Criar sistema de logging em CSV
8. Testes de performance e volume
9. Scripts de análise complementares

---

**Data de Criação:** 2025-09-29  
**Versão:** 1.0  
**Autor:** Sistema de Logging de Atividade