# autoclicker.ps1
# Move o cursor para uma posição aleatória DENTRO de um retângulo central
# a cada intervalo aleatório (30s..4min), faz clique esquerdo e digita uma frase aleatória.

Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing

$src = @"
using System;
using System.Runtime.InteropServices;
public class Win32 {
    [DllImport("user32.dll")] public static extern bool SetCursorPos(int X, int Y);
    [DllImport("user32.dll")] public static extern void mouse_event(uint dwFlags, uint dx, uint dy, uint dwData, UIntPtr dwExtraInfo);
}
"@
Add-Type $src

$MOUSEEVENTF_LEFTDOWN = 0x0002
$MOUSEEVENTF_LEFTUP   = 0x0004

# Frases (edite se quiser)
$phrases = @(
    "Ola! Testando automacao central.",
    "Mensagem automatica: OK.",
    "Clique central realizado.",
    "Teste: movimento em retangulo central.",
    "Bot acionado - script em execucao."
)

# Obter resolução da tela primária
$screenBounds = [System.Windows.Forms.Screen]::PrimaryScreen.Bounds
$screenWidth = $screenBounds.Width
$screenHeight = $screenBounds.Height

# --- CONFIGURACAO DO RETANGULO CENTRAL ---
# Largura e altura do retangulo (em pixels)
$rectWidth  = 400   # ajuste aqui (ex.: 400)
$rectHeight = 200   # ajuste aqui (ex.: 200)

# calcula o canto superior-esquerdo do retangulo central
$rectLeft = [int](([double]$screenWidth - [double]$rectWidth) / 2)
$rectTop  = [int](([double]$screenHeight - [double]$rectHeight) / 2)

Write-Host "Autoclicker iniciado."
Write-Host "Resolução detectada: ${screenWidth}x${screenHeight}"
Write-Host "Retangulo central: largura=${rectWidth}, altura=${rectHeight}"
Write-Host "Coordenadas do retangulo: left=$rectLeft, top=$rectTop"
Write-Host "Pressione Ctrl+C nesta janela para interromper."

while ($true) {
    # intervalo aleatorio entre 30 e 240 segundos
    $seconds = Get-Random -Minimum 1 -Maximum 240
    Write-Host "$(Get-Date -Format 'HH:mm:ss') - Dormindo por $seconds segundos..."
    Start-Sleep -Seconds $seconds

    # Escolhe uma posicao aleatoria dentro do retangulo central
    $x = Get-Random -Minimum $rectLeft -Maximum ($rectLeft + $rectWidth)
    $y = Get-Random -Minimum $rectTop  -Maximum ($rectTop  + $rectHeight)

    # Move o cursor e realiza clique
    [Win32]::SetCursorPos([int]$x, [int]$y)
    Start-Sleep -Milliseconds 120

    [Win32]::mouse_event($MOUSEEVENTF_LEFTDOWN, [uint32]$x, [uint32]$y, 0, [UIntPtr]::Zero)
    Start-Sleep -Milliseconds 60
    [Win32]::mouse_event($MOUSEEVENTF_LEFTUP, [uint32]$x, [uint32]$y, 0, [UIntPtr]::Zero)
    Start-Sleep -Milliseconds 120

    Write-Host "$(Get-Date -Format 'HH:mm:ss') - Clique em ($x,$y) realizado dentro do retangulo."

    # Digita uma frase aleatoria (a janela alvo precisa ter foco)
    $phrase = $phrases | Get-Random
    [System.Windows.Forms.SendKeys]::SendWait($phrase)
    [System.Windows.Forms.SendKeys]::SendWait("{ENTER}")

    Write-Host ("Digitou: """ + $phrase + """")
    Start-Sleep -Milliseconds 300
}
