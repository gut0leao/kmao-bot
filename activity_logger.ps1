# Activity Logger - Script Principal PowerShell
# Baseado na especificacao ACTIVITY_LOGGER_SPEC.md

# Carregar assemblies necessários
Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing

# Adicionar tipos necessarios para Windows API
Add-Type -TypeDefinition @"
    using System;
    using System.Diagnostics;
    using System.Runtime.InteropServices;
    
    public delegate IntPtr LowLevelProc(int nCode, IntPtr wParam, IntPtr lParam);
    
    public static class User32 {
        [DllImport("user32.dll", CharSet = CharSet.Auto, SetLastError = true)]
        public static extern IntPtr SetWindowsHookEx(int idHook, LowLevelProc lpfn, IntPtr hMod, uint dwThreadId);
        
        [DllImport("user32.dll", CharSet = CharSet.Auto, SetLastError = true)]
        [return: MarshalAs(UnmanagedType.Bool)]
        public static extern bool UnhookWindowsHookEx(IntPtr hhk);
        
        [DllImport("user32.dll", CharSet = CharSet.Auto, SetLastError = true)]
        public static extern IntPtr CallNextHookEx(IntPtr hhk, int nCode, IntPtr wParam, IntPtr lParam);
        
        [DllImport("kernel32.dll", CharSet = CharSet.Auto, SetLastError = true)]
        public static extern IntPtr GetModuleHandle(string lpModuleName);
        
        [DllImport("user32.dll")]
        public static extern bool GetCursorPos(out POINT lpPoint);
    }
    
    [StructLayout(LayoutKind.Sequential)]
    public struct POINT {
        public int x;
        public int y;
    }
    
    [StructLayout(LayoutKind.Sequential)]
    public struct MSLLHOOKSTRUCT {
        public POINT pt;
        public uint mouseData;
        public uint flags;
        public uint time;
        public IntPtr dwExtraInfo;
    }
    
    [StructLayout(LayoutKind.Sequential)]
    public struct KBDLLHOOKSTRUCT {
        public uint vkCode;
        public uint scanCode;
        public uint flags;
        public uint time;
        public IntPtr dwExtraInfo;
    }
"@

# Constantes
$WH_MOUSE_LL = 14
$WH_KEYBOARD_LL = 13
$WM_LBUTTONDOWN = 0x0201
$WM_RBUTTONDOWN = 0x0204
$WM_MBUTTONDOWN = 0x0207
$WM_MOUSEWHEEL = 0x020A
$WM_MOUSEHWHEEL = 0x020E
$WM_MOUSEMOVE = 0x0200
$WM_KEYDOWN = 0x0100
$WM_KEYUP = 0x0101

# Variáveis globais
$script:logFile = ""
$script:startTime = Get-Date
$script:lastMousePos = @{x = -1; y = -1}
$script:lastMouseSample = 0
$script:mouseSamplingInterval = 200
$script:recordingDurationMinutes = 480
$script:buffer = @()
$script:bufferSize = 100

# Função para ler configuração
function Read-Config {
    $configPath = "config\kmao.conf"
    $defaultValues = @{
        "MOUSE_SAMPLING_INTERVAL" = 200
        "RECORDING_DURATION_MINUTES" = 480
    }
    
    if (Test-Path $configPath) {
        Write-Host "Lendo configuracao de: $configPath"
        Get-Content $configPath | ForEach-Object {
            if ($_ -match "^([^#]+)=(.+)$") {
                $key = $matches[1].Trim()
                $value = $matches[2].Trim()
                $defaultValues[$key] = [int]$value
            }
        }
    } else {
        Write-Host "Arquivo de configuracao nao encontrado. Usando valores padrao."
    }
    
    $script:mouseSamplingInterval = $defaultValues["MOUSE_SAMPLING_INTERVAL"]
    $script:recordingDurationMinutes = $defaultValues["RECORDING_DURATION_MINUTES"]
    
    Write-Host "Mouse Sampling Interval: $($script:mouseSamplingInterval)ms"
    Write-Host "Recording Duration: $($script:recordingDurationMinutes) minutos"
}

# Função para criar nome do arquivo
function Get-LogFileName {
    $timestamp = Get-Date -Format "yyyy-MM-dd-HH-mm-fff"
    return "data\$timestamp-recording.csv"
}

# Função para escrever header do CSV
function Write-CsvHeader {
    "t,e,x,y,k" | Out-File -FilePath $script:logFile -Encoding UTF8
}

# Função para escrever evento no buffer
function Write-Event {
    param($eventType, $x = "", $y = "", $key = "")
    
    $timestamp = [int64](Get-Date -UFormat %s)
    $event = "$timestamp,$eventType,$x,$y,$key"
    
    $script:buffer += $event
    
    if ($script:buffer.Count -ge $script:bufferSize) {
        Flush-Buffer
    }
}

# Função para descarregar buffer
function Flush-Buffer {
    if ($script:buffer.Count -gt 0) {
        $script:buffer | Out-File -FilePath $script:logFile -Append -Encoding UTF8
        $script:buffer = @()
    }
}

# Hook do Mouse
$mouseHookProc = {
    param($nCode, $wParam, $lParam)
    
    if ($nCode -ge 0) {
        $hookStruct = [System.Runtime.InteropServices.Marshal]::PtrToStructure($lParam, [type][MSLLHOOKSTRUCT])
        $currentTime = [int64](Get-Date).Ticks / 10000  # milissegundos
        
        switch ($wParam) {
            $WM_LBUTTONDOWN { Write-Event "mc" $hookStruct.pt.x $hookStruct.pt.y }
            $WM_RBUTTONDOWN { Write-Event "mc" $hookStruct.pt.x $hookStruct.pt.y }
            $WM_MBUTTONDOWN { Write-Event "mc" $hookStruct.pt.x $hookStruct.pt.y }
            $WM_MOUSEWHEEL { Write-Event "sc" $hookStruct.pt.x $hookStruct.pt.y }
            $WM_MOUSEHWHEEL { Write-Event "sc" $hookStruct.pt.x $hookStruct.pt.y }
            $WM_MOUSEMOVE {
                # Sampling inteligente - só registra se posição mudou e tempo suficiente passou
                if (($hookStruct.pt.x -ne $script:lastMousePos.x -or $hookStruct.pt.y -ne $script:lastMousePos.y) -and
                    ($currentTime - $script:lastMouseSample) -ge $script:mouseSamplingInterval) {
                    
                    Write-Event "mm" $hookStruct.pt.x $hookStruct.pt.y
                    $script:lastMousePos = @{x = $hookStruct.pt.x; y = $hookStruct.pt.y}
                    $script:lastMouseSample = $currentTime
                }
            }
        }
    }
    
    return [User32]::CallNextHookEx([IntPtr]::Zero, $nCode, $wParam, $lParam)
}

# Hook do Teclado
$keyboardHookProc = {
    param($nCode, $wParam, $lParam)
    
    if ($nCode -ge 0) {
        $hookStruct = [System.Runtime.InteropServices.Marshal]::PtrToStructure($lParam, [type][KBDLLHOOKSTRUCT])
        $key = [System.Windows.Forms.Keys]$hookStruct.vkCode
        
        switch ($wParam) {
            $WM_KEYDOWN { Write-Event "kd" "" "" $key.ToString() }
            $WM_KEYUP { Write-Event "ku" "" "" $key.ToString() }
        }
    }
    
    return [User32]::CallNextHookEx([IntPtr]::Zero, $nCode, $wParam, $lParam)
}

# Função principal
function Start-ActivityLogger {
    Write-Host "========================================="
    Write-Host "KMAO Activity Logger - Iniciando..."
    Write-Host "========================================="
    
    # Ler configuração
    Read-Config
    
    # Criar diretório data se não existir
    if (!(Test-Path "data")) {
        New-Item -ItemType Directory -Path "data" | Out-Null
    }
    
    # Configurar arquivo de log
    $script:logFile = Get-LogFileName
    Write-Host "Arquivo de log: $($script:logFile)"
    Write-CsvHeader
    
    # Configurar hooks
    $mouseHook = [User32]::SetWindowsHookEx($WH_MOUSE_LL, $mouseHookProc, [User32]::GetModuleHandle("user32"), 0)
    $keyboardHook = [User32]::SetWindowsHookEx($WH_KEYBOARD_LL, $keyboardHookProc, [User32]::GetModuleHandle("user32"), 0)
    
    if ($mouseHook -eq [IntPtr]::Zero -or $keyboardHook -eq [IntPtr]::Zero) {
        Write-Error "Falha ao instalar hooks. Execute como Administrador."
        return
    }
    
    Write-Host "Hooks instalados com sucesso!"
    Write-Host "Gravacao iniciada. Pressione Ctrl+C para parar."
    
    # Loop principal com verificação de tempo
    try {
        $endTime = if ($script:recordingDurationMinutes -gt 0) { 
            $script:startTime.AddMinutes($script:recordingDurationMinutes) 
        } else { 
            [DateTime]::MaxValue 
        }
        
        while ((Get-Date) -lt $endTime) {
            Start-Sleep -Milliseconds 100
            
            # Flush buffer periodicamente
            if ($script:buffer.Count -gt 0) {
                $timeSinceLastFlush = (Get-Date) - $script:startTime
                if ($timeSinceLastFlush.TotalSeconds % 10 -lt 0.1) {
                    Flush-Buffer
                }
            }
        }
        
        if ($script:recordingDurationMinutes -gt 0) {
            Write-Host "Tempo limite atingido. Finalizando gravacao..."
        }
    }
    catch {
        Write-Host "Gravacao interrompida pelo usuario."
    }
    finally {
        # Cleanup
        Write-Host "Removendo hooks..."
        [User32]::UnhookWindowsHookEx($mouseHook) | Out-Null
        [User32]::UnhookWindowsHookEx($keyboardHook) | Out-Null
        
        # Flush final do buffer
        Flush-Buffer
        
        Write-Host "Gravacao finalizada!"
        Write-Host "Arquivo salvo: $($script:logFile)"
        
        # Estatísticas básicas
        if (Test-Path $script:logFile) {
            $lines = (Get-Content $script:logFile).Count - 1  # -1 para descontar header
            Write-Host "Total de eventos registrados: $lines"
        }
    }
}

# Executar o logger
Start-ActivityLogger