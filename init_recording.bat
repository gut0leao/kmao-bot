@echo off
REM Activity Logger - Inicializador de Gravacao
REM Baseado na especificacao ACTIVITY_LOGGER_SPEC.md

echo ========================================
echo KMAO Activity Logger - Inicializando...
echo ========================================

REM Criar estrutura de diretorios se nao existir
if not exist "config" mkdir config
if not exist "data" mkdir data

REM Verificar se existe arquivo de configuracao
if not exist "config\kmao.conf" (
    echo Arquivo de configuracao nao encontrado.
    if exist "config\kmao.conf.example" (
        echo Copiando configuracao do template...
        copy "config\kmao.conf.example" "config\kmao.conf" >nul
    ) else (
        echo Criando arquivo de configuracao padrao...
        call :create_default_config
    )
)

REM Executar o script PowerShell de gravacao
echo Iniciando gravacao de atividades...
powershell.exe -ExecutionPolicy Bypass -File "activity_logger.ps1"

if %errorlevel% neq 0 (
    echo.
    echo ERRO: Falha na execucao do script PowerShell
    echo Verifique se o arquivo activity_logger.ps1 existe
    pause
    exit /b 1
)

echo.
echo Gravacao finalizada com sucesso!
pause
exit /b 0

:create_default_config
echo # Configuracao do KMAO Activity Logger > "config\kmao.conf"
echo. >> "config\kmao.conf"
echo # Intervalo de sampling para movimento do mouse (ms) >> "config\kmao.conf"
echo MOUSE_SAMPLING_INTERVAL=200 >> "config\kmao.conf"
echo. >> "config\kmao.conf"
echo # Duracao maxima da gravacao em minutos >> "config\kmao.conf"
echo # 480 = 8 horas de trabalho >> "config\kmao.conf"
echo # 0 = gravacao ilimitada (ate interrupcao manual) >> "config\kmao.conf"
echo RECORDING_DURATION_MINUTES=480 >> "config\kmao.conf"
echo. >> "config\kmao.conf"
echo # Configuracoes futuras podem ser adicionadas aqui >> "config\kmao.conf"
echo # BUFFER_SIZE=1000 >> "config\kmao.conf"
echo # LOG_LEVEL=INFO >> "config\kmao.conf"
goto :eof