# Fonctions utilitaires pour piloter VirtualBox
. (Join-Path $PSScriptRoot "config.ps1")

function VBox {
    & $VBox @args
    if ($LASTEXITCODE -ne 0) { throw "VBoxManage $($args -join ' ') a echoue ($LASTEXITCODE)" }
}

function Test-Vm([string]$Name) {
    (& $VBox list vms) -match "^`"$([regex]::Escape($Name))`" "
}

function Test-VmRunning([string]$Name) {
    (& $VBox list runningvms) -match "^`"$([regex]::Escape($Name))`" "
}

# Tape du texte dans la console d'une VM (clavier US cote invite)
function Send-Text([string]$Vm, [string]$Text) {
    VBox controlvm $Vm keyboardputstring $Text
}

# Touches speciales : Enter, Tab, Space, Up, Down, Left, Right, Esc, Backspace
$ScanCodes = @{
    Enter = "1c 9c"; Tab = "0f 8f"; Space = "39 b9"; Esc = "01 81"; Backspace = "0e 8e"
    Up = "e0 48 e0 c8"; Down = "e0 50 e0 d0"; Left = "e0 4b e0 cb"; Right = "e0 4d e0 cd"
}
function Send-Key([string]$Vm, [string]$Key, [int]$Repeat = 1) {
    for ($i = 0; $i -lt $Repeat; $i++) {
        VBox controlvm $Vm keyboardputscancode @($ScanCodes[$Key] -split ' ')
        Start-Sleep -Milliseconds 150
    }
}

# Tape une ligne puis Enter
function Send-Line([string]$Vm, [string]$Text) {
    if ($Text) { Send-Text $Vm $Text }
    Send-Key $Vm Enter
}

# Capture l'ecran de la console et renvoie le chemin du PNG
function Save-Screen([string]$Vm, [string]$Label) {
    New-Item -ItemType Directory -Force $Shots | Out-Null
    $path = Join-Path $Shots ("{0}-{1}.png" -f $Vm, $Label)
    VBox controlvm $Vm screenshotpng $path
    $path
}

# SSH avec la cle du labo
function Invoke-Ssh([string]$Target, [string]$Command, [string]$Jump) {
    # Le chemin contient des espaces : guillemets pour le parseur d'options de ssh
    $opts = @("-i", $SshKey, "-o", "BatchMode=yes", "-o", "StrictHostKeyChecking=accept-new",
              "-o", "UserKnownHostsFile=`"$Secrets\known_hosts`"", "-o", "ConnectTimeout=10")
    if ($Jump) { $opts += @("-J", $Jump) }
    & ssh @opts $Target $Command
}

# Options SSH pour joindre une VM interne (10.10.x.x) en rebondissant par OPNsense
function Get-JumpOpts {
    $k = $SshKey -replace '\\', '/'; $kh = "$Secrets\known_hosts" -replace '\\', '/'
    @("-o", "ProxyCommand=ssh -i `"$k`" -o BatchMode=yes -o StrictHostKeyChecking=accept-new -o UserKnownHostsFile=`"$kh`" -W %h:%p root@$($Ip.OpnWan)")
}

# Execute un script shell multiligne sur la cible (envoye a sh par l'entree standard :
# le shell de root sur OPNsense est csh, qui ne gere pas les blocs << FIN)
function Invoke-SshScript([string]$Target, [string]$Script, [string[]]$Extra = @()) {
    $opts = @("-i", $SshKey, "-o", "BatchMode=yes", "-o", "StrictHostKeyChecking=accept-new",
              "-o", "UserKnownHostsFile=`"$Secrets\known_hosts`"", "-o", "ConnectTimeout=10") + $Extra
    # PowerShell termine la derniere ligne par CRLF : une ligne de commentaire finale l'absorbe
    (($Script -replace "`r", "") + "`n# fin") | & ssh @opts $Target "sh -s"
}
