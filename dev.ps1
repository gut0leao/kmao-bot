# autoclicker.ps1
# Moves cursor to a random position INSIDE a central rectangle
# at random intervals (30s..4min), performs left click and types a random phrase.

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

# Function for humanized typing
function Type-HumanLike {
    param([string]$text)
    
    foreach ($char in $text.ToCharArray()) {
        # Variable typing speed (40-200ms per character)
        $delay = Get-Random -Minimum 40 -Maximum 200
        
        # Occasional longer pause (simulates thinking/hesitation)
        if ((Get-Random -Minimum 1 -Maximum 100) -le 8) {  # 8% chance
            $delay += Get-Random -Minimum 300 -Maximum 800
        }
        
        # For spaces, use slightly shorter pause
        if ($char -eq ' ') {
            $delay = Get-Random -Minimum 30 -Maximum 120
        }
        
        # For punctuation, add small extra pause
        if ($char -match '[.,;:!?()\-"]') {
            $delay += Get-Random -Minimum 50 -Maximum 150
        }
        
        [System.Windows.Forms.SendKeys]::SendWait($char.ToString())
        Start-Sleep -Milliseconds $delay
    }
}

# Phrases (edit if you want)
$phrases = @(
    "Here, we're all one family. (But in the first crisis, they fire you without mercy.)",
    "Wear the company shirt. (Even though the company will never wear yours.)",
    "Think outside the box. (As long as you keep obeying what comes from the box.)",
    "Work with purpose. (Preferably the shareholder's purpose.)",
    "Where there's a will, there's a way. (Those who can't find a way get the blame.)",
    "Change starts with you. (So no one has to change the system.)",
    "Be the protagonist of your story. (But follow the company script.)",
    "Here we value continuous learning. (As long as you learn alone, after hours, at no cost.)",
    "We're transparent in everything. (Except salaries, decisions, and promotion criteria.)",
    "Success depends only on your effort. (Completely ignoring class, privileges, and context.)",
    "The energy you emanate is the reality you create. (So if the project failed, it's your vibration's fault.)",
    "Gratitude is the first step to success. (Start by being grateful for working 12 hours with a smile.)",
    "Nothing happens by chance. (Except budget cuts and your dismissal.)",
    "Be like water: adapt. (Because resisting is lack of emotional intelligence.)",
    "You don't work, you manifest. (But the electric bill comes manifested in your name.)",
    "Transform challenges into opportunities. (Especially those that shouldn't exist.)",
    "The world is a mirror: what you see is what you are. (So if the environment is toxic, you're the problem.)",
    "Let go of control and trust the process. (The selection process, in this case, to replace you.)",
    "Purpose is the new salary. (And meal vouchers became spiritual energy.)",
    "Shine wherever you are. (Even without raises, recognition, or decent conditions.)",
    "Automation came to free people for more strategic tasks. (Translation: half the team leaves, the other half gets more spreadsheets.)",
    "We're investing in operational efficiency. (Meaning: fewer people, more targets, same 2009 infrastructure.)",
    "Innovation is in our DNA. (But you need to fill three forms to install Git.)",
    "We use data to make decisions. (Decisions that were already made, but now with a pretty chart.)",
    "Automating is evolving. (Especially when the intern programs and the director presents.)",
    "Being agile is a mindset issue. (Mindset, because the budget stays the same.)",
    "We're going through a transformation journey. (And the transforming part is cost cutting.)",
    "Technology is a means, not an end. (But the end always comes before the means work.)",
    "Less bureaucracy, more results. (That's why we now have five committees to approve a deploy.)",
    "We're building the future of work. (With temporary contracts and Teams login at 10 PM.)"
)

# Get primary screen resolution
$screenBounds = [System.Windows.Forms.Screen]::PrimaryScreen.Bounds
$screenWidth = $screenBounds.Width
$screenHeight = $screenBounds.Height

# --- CENTRAL RECTANGLE CONFIGURATION ---
# Rectangle width and height (in pixels)
$rectWidth  = 400   # adjust here (e.g.: 400)
$rectHeight = 200   # adjust here (e.g.: 200)

# Calculate top-left corner of central rectangle
$rectLeft = [int](([double]$screenWidth - [double]$rectWidth) / 2)
$rectTop  = [int](([double]$screenHeight - [double]$rectHeight) / 2)

Write-Host "Initialized."
Write-Host "Current resolution: ${screenWidth}x${screenHeight}"
Write-Host "Center square: width=${rectWidth}, height=${rectHeight}"
Write-Host "Rect coordinaties: left=$rectLeft, top=$rectTop"
Write-Host "Press Ctrl+C to interrupt."

while ($true) {
    # More humanized random interval between 30 seconds and 4 minutes
    $seconds = Get-Random -Minimum 30 -Maximum 240
    Write-Host "$(Get-Date -Format 'HH:mm:ss') - Sleeping for $seconds seconds..."
    Start-Sleep -Seconds $seconds

    # Sometimes do multiple clicks (1-3) to simulate human behavior
    $numClicks = Get-Random -Minimum 1 -Maximum 4
    Write-Host "$(Get-Date -Format 'HH:mm:ss') - Performing $numClicks click(s)..."
    
    for ($i = 1; $i -le $numClicks; $i++) {
        # Choose a random position within the central rectangle
        $x = Get-Random -Minimum $rectLeft -Maximum ($rectLeft + $rectWidth)
        $y = Get-Random -Minimum $rectTop  -Maximum ($rectTop  + $rectHeight)

        # Move cursor with slight humanized delay
        [Win32]::SetCursorPos([int]$x, [int]$y)
        Start-Sleep -Milliseconds (Get-Random -Minimum 80 -Maximum 200)

        # Perform click with humanized timing
        [Win32]::mouse_event($MOUSEEVENTF_LEFTDOWN, [uint32]$x, [uint32]$y, 0, [UIntPtr]::Zero)
        Start-Sleep -Milliseconds (Get-Random -Minimum 50 -Maximum 100)
        [Win32]::mouse_event($MOUSEEVENTF_LEFTUP, [uint32]$x, [uint32]$y, 0, [UIntPtr]::Zero)
        
        Write-Host "  Click $i at ($x,$y) performed."
        
        # Small delay between multiple clicks
        if ($i -lt $numClicks) {
            Start-Sleep -Milliseconds (Get-Random -Minimum 200 -Maximum 500)
        }
    }

    # Random chance to type a phrase (70% chance)
    if ((Get-Random -Minimum 1 -Maximum 100) -le 70) {
        # Random delay before typing (simulates reading/thinking)
        Start-Sleep -Milliseconds (Get-Random -Minimum 500 -Maximum 1500)
        
        # Type a random phrase in humanized way
        $phrase = $phrases | Get-Random
        Write-Host ("Typing: """ + $phrase + """")
        
        # Use humanized typing function
        Type-HumanLike -text $phrase
        
        # Pause before Enter (simulates text review)
        Start-Sleep -Milliseconds (Get-Random -Minimum 200 -Maximum 600)
        [System.Windows.Forms.SendKeys]::SendWait("{ENTER}")

        Write-Host ("Typing concluded: """ + $phrase + """")
    } else {
        Write-Host "Skipping typing this time (humanized behavior)."
    }
    
    # Final pause with some variation
    Start-Sleep -Milliseconds (Get-Random -Minimum 200 -Maximum 800)
}
