# autoclicker.ps1
# Moves cursor to a random position INSIDE a central rectangle
# at random intervals (30s..4min), performs left click and types a random phrase.

# ===== CONFIGURATION VARIABLES =====
# Timing intervals (in seconds)
$MIN_INTERVAL = 30          # Minimum time between cycles
$MAX_INTERVAL = 240         # Maximum time between cycles (4 minutes)

# Click area configuration (in pixels)
$RECT_WIDTH = 400           # Width of the central clicking rectangle
$RECT_HEIGHT = 200          # Height of the central clicking rectangle

# Click behavior
$MIN_CLICKS = 1             # Minimum number of clicks per cycle
$MAX_CLICKS = 4             # Maximum number of clicks per cycle (exclusive)

# Typing behavior
$TYPING_CHANCE = 70         # Percentage chance to type a phrase (0-100)

# Idle detection configuration
$IDLE_TIME_THRESHOLD = 60   # Minimum idle time in seconds before bot activates

# Typing speed configuration (in milliseconds)
$MIN_CHAR_DELAY = 40        # Minimum delay between characters
$MAX_CHAR_DELAY = 200       # Maximum delay between characters
$HESITATION_CHANCE = 8      # Percentage chance for thinking pause
$MIN_HESITATION = 300       # Minimum hesitation pause
$MAX_HESITATION = 800       # Maximum hesitation pause
$SPACE_MIN_DELAY = 30       # Minimum delay for spaces
$SPACE_MAX_DELAY = 120      # Maximum delay for spaces
$PUNCT_MIN_DELAY = 50       # Minimum extra delay for punctuation
$PUNCT_MAX_DELAY = 150      # Maximum extra delay for punctuation

# Mouse timing configuration (in milliseconds)
$CURSOR_MIN_DELAY = 80      # Minimum delay after moving cursor
$CURSOR_MAX_DELAY = 200     # Maximum delay after moving cursor
$CLICK_MIN_DELAY = 50       # Minimum delay between mouse down/up
$CLICK_MAX_DELAY = 100      # Maximum delay between mouse down/up
$MULTI_CLICK_MIN_DELAY = 200 # Minimum delay between multiple clicks
$MULTI_CLICK_MAX_DELAY = 500 # Maximum delay between multiple clicks

# Pre-typing delays (in milliseconds)
$PRE_TYPING_MIN_DELAY = 500  # Minimum delay before starting to type
$PRE_TYPING_MAX_DELAY = 1500 # Maximum delay before starting to type
$PRE_ENTER_MIN_DELAY = 200   # Minimum delay before pressing Enter
$PRE_ENTER_MAX_DELAY = 600   # Maximum delay before pressing Enter
$FINAL_MIN_DELAY = 200       # Minimum final pause after cycle
$FINAL_MAX_DELAY = 800       # Maximum final pause after cycle
# Phrases configuration
$PHRASES_FILE = "phrases.txt"       # File containing phrases to type (one per line)

# =====================================

Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing

$src = @"
using System;
using System.Runtime.InteropServices;
public class Win32 {
    [DllImport("user32.dll")] public static extern bool SetCursorPos(int X, int Y);
    [DllImport("user32.dll")] public static extern void mouse_event(uint dwFlags, uint dx, uint dy, uint dwData, UIntPtr dwExtraInfo);
    [DllImport("user32.dll")] public static extern bool GetLastInputInfo(ref LASTINPUTINFO plii);
    
    public struct LASTINPUTINFO {
        public uint cbSize;
        public uint dwTime;
    }
    
    [DllImport("kernel32.dll")] public static extern uint GetTickCount();
}
"@
Add-Type $src

$MOUSEEVENTF_LEFTDOWN = 0x0002
$MOUSEEVENTF_LEFTUP   = 0x0004

# Load phrases from external file
function Load-Phrases {
    param([string]$filePath)
    
    if (Test-Path $filePath) {
        $phrases = Get-Content $filePath | Where-Object { $_.Trim() -ne "" }
        Write-Host "Loaded $($phrases.Count) phrases from $filePath"
        return $phrases
    } else {
        Write-Host "Warning: Phrases file '$filePath' not found. Using default phrase."
        return @("Default phrase - phrases.txt file not found")
    }
}

# Function to get idle time in seconds
function Get-IdleTime {
    $lastInputInfo = New-Object Win32+LASTINPUTINFO
    $lastInputInfo.cbSize = [System.Runtime.InteropServices.Marshal]::SizeOf($lastInputInfo)
    
    if ([Win32]::GetLastInputInfo([ref]$lastInputInfo)) {
        $currentTickCount = [Win32]::GetTickCount()
        $idleTimeMs = $currentTickCount - $lastInputInfo.dwTime
        return [math]::Floor($idleTimeMs / 1000)
    } else {
        Write-Host "Warning: Could not get idle time. Assuming system is not idle."
        return 0
    }
}

# Function for humanized typing
function Type-HumanLike {
    param([string]$text)
    
    foreach ($char in $text.ToCharArray()) {
        # Variable typing speed
        $delay = Get-Random -Minimum $MIN_CHAR_DELAY -Maximum $MAX_CHAR_DELAY
        
        # Occasional longer pause (simulates thinking/hesitation)
        if ((Get-Random -Minimum 1 -Maximum 100) -le $HESITATION_CHANCE) {
            $delay += Get-Random -Minimum $MIN_HESITATION -Maximum $MAX_HESITATION
        }
        
        # For spaces, use slightly shorter pause
        if ($char -eq ' ') {
            $delay = Get-Random -Minimum $SPACE_MIN_DELAY -Maximum $SPACE_MAX_DELAY
        }
        
        # For punctuation, add small extra pause
        if ($char -match '[.,;:!?()\-"]') {
            $delay += Get-Random -Minimum $PUNCT_MIN_DELAY -Maximum $PUNCT_MAX_DELAY
        }
        
        # Escape special SendKeys characters
        $charToSend = $char.ToString()
        switch ($char) {
            '+' { $charToSend = '{+}' }
            '^' { $charToSend = '{^}' }
            '%' { $charToSend = '{%}' }
            '~' { $charToSend = '{~}' }
            '(' { $charToSend = '{(}' }
            ')' { $charToSend = '{)}' }
            '[' { $charToSend = '{[}' }
            ']' { $charToSend = '{]}' }
            '{' { $charToSend = '{{}' }
            '}' { $charToSend = '{}}' }
        }
        
        [System.Windows.Forms.SendKeys]::SendWait($charToSend)
        Start-Sleep -Milliseconds $delay
    }
}

# Load phrases from file
$phrases = Load-Phrases -filePath $PHRASES_FILE

# Get primary screen resolution
$screenBounds = [System.Windows.Forms.Screen]::PrimaryScreen.Bounds
$screenWidth = $screenBounds.Width
$screenHeight = $screenBounds.Height

# --- CENTRAL RECTANGLE CONFIGURATION ---
# Rectangle width and height (in pixels)
$rectWidth  = $RECT_WIDTH
$rectHeight = $RECT_HEIGHT

# Calculate top-left corner of central rectangle
$rectLeft = [int](([double]$screenWidth - [double]$rectWidth) / 2)
$rectTop  = [int](([double]$screenHeight - [double]$rectHeight) / 2)

Write-Host "Initialized."
Write-Host "Current resolution: ${screenWidth}x${screenHeight}"
Write-Host "Center square: width=${rectWidth}, height=${rectHeight}"
Write-Host "Rect coordinaties: left=$rectLeft, top=$rectTop"
Write-Host "Idle threshold: ${IDLE_TIME_THRESHOLD} seconds"
Write-Host "Press Ctrl+C to interrupt."

while ($true) {
    # Check if system has been idle long enough
    $idleTime = Get-IdleTime
    
    if ($idleTime -lt $IDLE_TIME_THRESHOLD) {
        Write-Host "$(Get-Date -Format 'HH:mm:ss') - System active (idle: ${idleTime}s, need: ${IDLE_TIME_THRESHOLD}s). Waiting..."
        Start-Sleep -Seconds 5  # Check again in 5 seconds
        continue
    }
    
    Write-Host "$(Get-Date -Format 'HH:mm:ss') - System idle for ${idleTime}s. Starting activity..."
    
    # More humanized random interval
    $seconds = Get-Random -Minimum $MIN_INTERVAL -Maximum $MAX_INTERVAL
    Write-Host "$(Get-Date -Format 'HH:mm:ss') - Sleeping for $seconds seconds..."
    Start-Sleep -Seconds $seconds

    # Sometimes do multiple clicks to simulate human behavior
    $numClicks = Get-Random -Minimum $MIN_CLICKS -Maximum $MAX_CLICKS
    Write-Host "$(Get-Date -Format 'HH:mm:ss') - Performing $numClicks click(s)..."
    
    for ($i = 1; $i -le $numClicks; $i++) {
        # Choose a random position within the central rectangle
        $x = Get-Random -Minimum $rectLeft -Maximum ($rectLeft + $rectWidth)
        $y = Get-Random -Minimum $rectTop  -Maximum ($rectTop  + $rectHeight)

        # Move cursor with slight humanized delay
        [Win32]::SetCursorPos([int]$x, [int]$y)
        Start-Sleep -Milliseconds (Get-Random -Minimum $CURSOR_MIN_DELAY -Maximum $CURSOR_MAX_DELAY)

        # Perform click with humanized timing
        [Win32]::mouse_event($MOUSEEVENTF_LEFTDOWN, [uint32]$x, [uint32]$y, 0, [UIntPtr]::Zero)
        Start-Sleep -Milliseconds (Get-Random -Minimum $CLICK_MIN_DELAY -Maximum $CLICK_MAX_DELAY)
        [Win32]::mouse_event($MOUSEEVENTF_LEFTUP, [uint32]$x, [uint32]$y, 0, [UIntPtr]::Zero)
        
        Write-Host "  Click $i at ($x,$y) performed."
        
        # Small delay between multiple clicks
        if ($i -lt $numClicks) {
            Start-Sleep -Milliseconds (Get-Random -Minimum $MULTI_CLICK_MIN_DELAY -Maximum $MULTI_CLICK_MAX_DELAY)
        }
    }

    # Random chance to type a phrase
    if ((Get-Random -Minimum 1 -Maximum 100) -le $TYPING_CHANCE) {
        # Random delay before typing (simulates reading/thinking)
        Start-Sleep -Milliseconds (Get-Random -Minimum $PRE_TYPING_MIN_DELAY -Maximum $PRE_TYPING_MAX_DELAY)
        
        # Type a random phrase in humanized way
        $phrase = $phrases | Get-Random
        Write-Host ("Typing: """ + $phrase + """")
        
        # Use humanized typing function
        Type-HumanLike -text $phrase
        
        # Pause before Enter (simulates text review)
        Start-Sleep -Milliseconds (Get-Random -Minimum $PRE_ENTER_MIN_DELAY -Maximum $PRE_ENTER_MAX_DELAY)
        [System.Windows.Forms.SendKeys]::SendWait("{ENTER}")

        Write-Host ("Typing concluded: """ + $phrase + """")
    } else {
        Write-Host "Skipping typing this time (humanized behavior)."
    }
    
    # Final pause with some variation
    Start-Sleep -Milliseconds (Get-Random -Minimum $FINAL_MIN_DELAY -Maximum $FINAL_MAX_DELAY)
}
