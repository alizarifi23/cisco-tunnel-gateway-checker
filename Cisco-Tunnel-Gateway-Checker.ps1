# ============================================================
# Cisco Tunnel Gateway Checker
 # ============================================================
#
# Powered By Ali Zarifi
#
# ============================================================

$ErrorActionPreference = "Stop"

 
$ScriptDirectory = Split-Path -Parent $MyInvocation.MyCommand.Path
$ConfigPath = Join-Path $ScriptDirectory "config.json"
$DefaultRouterFile = Join-Path $ScriptDirectory "routers.csv"

  

# ============================================================
# ASYNC CISCO STDOUT READER
# ============================================================
# IMPORTANT:
# We do NOT use StreamReader.Peek() for interactive Cisco output.
# Plink/Cisco can stop sending data while Cisco is waiting for a
# password. Peek() can block in that exact situation and cause a
# deadlock. This helper continuously reads stdout in a background
# thread and puts characters into a thread-safe queue.

if (-not ("CiscoOutputReader" -as [type])) {

    Add-Type -TypeDefinition @"
using System;
using System.IO;
using System.Text;
using System.Threading;
using System.Collections.Concurrent;

public sealed class CiscoOutputReader : IDisposable
{
    private readonly TextReader _reader;
    private readonly ConcurrentQueue<char> _queue = new ConcurrentQueue<char>();
    private readonly Thread _thread;
    private volatile bool _stop;
    private volatile bool _ended;

    public bool Ended { get { return _ended; } }
    public int Count { get { return _queue.Count; } }

    public CiscoOutputReader(TextReader reader)
    {
        if (reader == null) throw new ArgumentNullException("reader");

        _reader = reader;
        _thread = new Thread(ReadLoop);
        _thread.IsBackground = true;
        _thread.Name = "CiscoOutputReader";
        _thread.Start();
    }

    private void ReadLoop()
    {
        try
        {
            while (!_stop)
            {
                int value = _reader.Read();

                if (value < 0)
                {
                    _ended = true;
                    break;
                }

                _queue.Enqueue((char)value);
            }
        }
        catch
        {
            _ended = true;
        }
    }

    public string ReadAvailable()
    {
        StringBuilder result = new StringBuilder();
        char value;

        while (_queue.TryDequeue(out value))
        {
            result.Append(value);
        }

        return result.ToString();
    }

    public void Clear()
    {
        char value;
        while (_queue.TryDequeue(out value)) { }
    }

    public void Stop()
    {
        _stop = true;
    }

    public void Dispose()
    {
        Stop();

        try
        {
            if (_thread != null && _thread.IsAlive)
            {
                _thread.Join(250);
            }
        }
        catch { }

        try
        {
            _reader.Dispose();
        }
        catch { }
    }
}
"@
}


# ============================================================
# UI
# ============================================================

function Show-Header {

    param(
        [string]$Title = "CISCO TUNNEL GATEWAY CHECKER",

        [switch]$NoClear
    )

 
    if (-not $NoClear) {
        Clear-Host
    }

    Write-Host ""
    Write-Host "╔══════════════════════════════════════════════════════════════════════╗" -ForegroundColor Cyan

    $PaddingLeft = [Math]::Floor((68 - $Title.Length) / 2)
    $PaddingRight = 70 - $Title.Length - $PaddingLeft

    if ($PaddingLeft -lt 0) {
        $PaddingLeft = 0
    }

    if ($PaddingRight -lt 0) {
        $PaddingRight = 0
    }

    Write-Host (
        "║" +
        (" " * $PaddingLeft) +
        $Title +
        (" " * $PaddingRight) +
        "║"
    ) -ForegroundColor Cyan

    Write-Host "╠══════════════════════════════════════════════════════════════════════╣" -ForegroundColor Cyan
}


function Show-Footer {

 
    Write-Host "╚══════════════════════════════════════════════════════════════════════╝" -ForegroundColor Cyan
    Write-Host ""
    Write-Host "                         Powered By Ali Zarifi" -ForegroundColor DarkGray
}


function Show-Status {

    param(
        [string]$Message,
        [ConsoleColor]$Color = [ConsoleColor]::White
    )

 
    Write-Host ""
    Write-Host "  $Message" -ForegroundColor $Color
}


function Pause-Program {

 
    Write-Host ""
    $null = Read-Host "Press ENTER to continue"
}


function Show-Box {

    param(
        [Parameter(Mandatory)]
        [string]$Title,

        [string[]]$Lines,

        [ConsoleColor]$TitleColor = [ConsoleColor]::Cyan,

        [ConsoleColor]$TextColor = [ConsoleColor]::White
    )

 

    Write-Host "╔══════════════════════════════════════════════════════════════════════╗" -ForegroundColor $TitleColor

    $Left = [Math]::Floor((66 - $Title.Length) / 2)
    $Right = 68 - $Title.Length - $Left

    if ($Left -lt 0) {
        $Left = 0
    }

    if ($Right -lt 0) {
        $Right = 0
    }


       Write-Host  "║"(" " * $Left) -ForegroundColor $TitleColor -NoNewline
       Write-Host  $Title -ForegroundColor $TitleColor -NoNewline
       Write-Host  (" " * $Right)"║" -ForegroundColor $TitleColor

    Write-Host "╠══════════════════════════════════════════════════════════════════════╣" -ForegroundColor $TitleColor

    if ($null -eq $Lines -or $Lines.Count -eq 0) {

        Write-Host "║                                                                      ║" -ForegroundColor $TitleColor
    }
    else {

        foreach ($Line in $Lines) {

            if ($null -eq $Line) {
                $Line = ""
            }

            $Line = [string]$Line

            if ($Line.Length -gt 68) {
                $Line = $Line.Substring(0, 68)
            }

            Write-Host "║ " -ForegroundColor $TitleColor -NoNewline
              Write-Host  $Line.PadRight(68)  -ForegroundColor $TextColor -NoNewline
             Write-Host " ║" -ForegroundColor $TitleColor
        }
    }

    Write-Host "╚══════════════════════════════════════════════════════════════════════╝" -ForegroundColor $TitleColor
}


# ============================================================
# CONFIGURATION
# ============================================================

function New-DefaultConfig {

 
    return [PSCustomObject]@{

        Credentials = [PSCustomObject]@{
            SaveCredentials = $false
            Username = ""
            Password = ""
            EnablePassword = ""
        }

        Network = [PSCustomObject]@{
            GatewayOffset = ""
        }

        Ping = [PSCustomObject]@{
            Count = 5
            Timeout = 15
        }

        Cisco = [PSCustomObject]@{
            SSHPort = 22
            CommandTimeout = 15
        }

        Files = [PSCustomObject]@{
            Routers = ".\routers.csv"
            Plink = ""
        }
    }
}


function Save-Config {

    param(
        [Parameter(Mandatory)]
        $Config
    )

 
    try {

        $Config |
            ConvertTo-Json -Depth 10 |
            Set-Content -Path $ConfigPath -Encoding UTF8

 
        return $true
    }
    catch {

 
        Write-Host ""
        Write-Host "Could not save configuration." -ForegroundColor Red
        Write-Host $_.Exception.Message -ForegroundColor Red

        return $false
    }
}


function Load-Config {

 
    if (-not (Test-Path $ConfigPath -PathType Leaf)) {

 
        $Config = New-DefaultConfig

        $null = Save-Config -Config $Config

 
        return $Config
    }

    try {

        $Config = Get-Content -Path $ConfigPath -Raw |
            ConvertFrom-Json

 
        return $Config
    }
    catch {

 
        Write-Host ""
        Write-Host "config.json is invalid." -ForegroundColor Red
        Write-Host "Creating a new configuration..." -ForegroundColor Yellow

        $Config = New-DefaultConfig

        $null = Save-Config -Config $Config

        return $Config
    }
}


function Update-ConfigStructure {

    param(
        [Parameter(Mandatory)]
        $Config
    )

 
    $Changed = $false

    if (-not $Config.PSObject.Properties["Credentials"]) {

 
        $Config | Add-Member NoteProperty Credentials (
            [PSCustomObject]@{
                SaveCredentials = $false
                Username = ""
                Password = ""
                EnablePassword = ""
            }
        )

        $Changed = $true
    }

    if (-not $Config.Credentials.PSObject.Properties["SaveCredentials"]) {

 
        $Config.Credentials |
            Add-Member NoteProperty SaveCredentials $false

        $Changed = $true
    }

    if (-not $Config.Credentials.PSObject.Properties["Username"]) {

 
        $Config.Credentials |
            Add-Member NoteProperty Username ""

        $Changed = $true
    }

    if (-not $Config.Credentials.PSObject.Properties["Password"]) {

 
        $Config.Credentials |
            Add-Member NoteProperty Password ""

        $Changed = $true
    }

    if (-not $Config.Credentials.PSObject.Properties["EnablePassword"]) {

 
        $Config.Credentials |
            Add-Member NoteProperty EnablePassword ""

        $Changed = $true
    }


    if (-not $Config.PSObject.Properties["Network"]) {

 
        $Config | Add-Member NoteProperty Network (
            [PSCustomObject]@{
                GatewayOffset = ""
            }
        )

        $Changed = $true
    }

    if (-not $Config.Network.PSObject.Properties["GatewayOffset"]) {

 
        $Config.Network |
            Add-Member NoteProperty GatewayOffset ""

        $Changed = $true
    }


    if (-not $Config.PSObject.Properties["Ping"]) {

 
        $Config | Add-Member NoteProperty Ping (
            [PSCustomObject]@{
                Count = 5
                Timeout = 15
            }
        )

        $Changed = $true
    }

    if (-not $Config.Ping.PSObject.Properties["Count"]) {

 
        $Config.Ping |
            Add-Member NoteProperty Count 5

        $Changed = $true
    }

    if (-not $Config.Ping.PSObject.Properties["Timeout"]) {

 
        $Config.Ping |
            Add-Member NoteProperty Timeout 15

        $Changed = $true
    }


    if (-not $Config.PSObject.Properties["Cisco"]) {

 
        $Config | Add-Member NoteProperty Cisco (
            [PSCustomObject]@{
                SSHPort = 22
                CommandTimeout = 15
            }
        )

        $Changed = $true
    }

    if (-not $Config.Cisco.PSObject.Properties["SSHPort"]) {

 
        $Config.Cisco |
            Add-Member NoteProperty SSHPort 22

        $Changed = $true
    }

    if (-not $Config.Cisco.PSObject.Properties["CommandTimeout"]) {

 
        $Config.Cisco |
            Add-Member NoteProperty CommandTimeout 15

        $Changed = $true
    }


    if (-not $Config.PSObject.Properties["Files"]) {

 
        $Config | Add-Member NoteProperty Files (
            [PSCustomObject]@{
                Routers = ".\routers.csv"
                Plink = ""
            }
        )

        $Changed = $true
    }

    if (-not $Config.Files.PSObject.Properties["Routers"]) {

 
        $Config.Files |
            Add-Member NoteProperty Routers ".\routers.csv"

        $Changed = $true
    }

    if (-not $Config.Files.PSObject.Properties["Plink"]) {

 
        $Config.Files |
            Add-Member NoteProperty Plink ""

        $Changed = $true
    }


    if ($Changed) {

 
        $null = Save-Config -Config $Config
    }

 
    return $Config
}


# ============================================================
# PLINK
# ============================================================

function Find-Plink {

 
    try {

        $Command = Get-Command plink.exe -ErrorAction SilentlyContinue

        if ($Command -and $Command.Source) {

 
            if (Test-Path $Command.Source -PathType Leaf) {

                return (Resolve-Path $Command.Source).Path
            }
        }
    }
    catch {

     }


    $Paths = @(
        "$env:ProgramFiles\PuTTY\plink.exe"
        "${env:ProgramFiles(x86)}\PuTTY\plink.exe"
        "$ScriptDirectory\plink.exe"
        "$ScriptDirectory\Tools\plink.exe"
        "$ScriptDirectory\PuTTY\plink.exe"
    )


    foreach ($Path in $Paths) {

 
        if (
            -not [string]::IsNullOrWhiteSpace($Path) -and
            (Test-Path $Path -PathType Leaf)
        ) {

 
            return (Resolve-Path $Path).Path
        }
    }


 
    return $null
}


function Test-PlinkPath {

    param(
        [Parameter(Mandatory)]
        [string]$Path
    )

 
    try {

        if ([string]::IsNullOrWhiteSpace($Path)) {
            return $false
        }

        if (-not (Test-Path $Path -PathType Leaf)) {
            return $false
        }

        if ([System.IO.Path]::GetFileName($Path) -ine "plink.exe") {
            return $false
        }

        return $true
    }
    catch {

        return $false
    }
}


function Get-Plink {

    param(
        [Parameter(Mandatory)]
        $Config
    )

 
    $SavedPath = [string]$Config.Files.Plink

 
    if (-not [string]::IsNullOrWhiteSpace($SavedPath)) {

        if ([System.IO.Path]::IsPathRooted($SavedPath)) {
            $FullPath = $SavedPath
        }
        else {
            $FullPath = Join-Path $ScriptDirectory $SavedPath
        }

 
        if (Test-PlinkPath -Path $FullPath) {

 
            return (Resolve-Path $FullPath).Path
        }
    }


    while ($true) {

        Show-Header "PLINK SETUP"

        Write-Host ""
        Write-Host "[1] Search automatically" -ForegroundColor Cyan
        Write-Host "[2] Select plink.exe manually" -ForegroundColor Cyan
        Write-Host "[3] Exit" -ForegroundColor Cyan
        Write-Host ""

        $Choice = Read-Host "Select option"

 
        switch ($Choice) {

            "1" {

                Show-Header "PLINK SETUP"

                Write-Host ""
                Write-Host "Searching for plink.exe..." -ForegroundColor Cyan

                $Found = Find-Plink

                if ($Found) {

                    $Config.Files.Plink = $Found

                    $null = Save-Config -Config $Config

                    Write-Host ""
                    Write-Host "Plink found successfully." -ForegroundColor Green
                    Write-Host $Found -ForegroundColor White

                    Pause-Program

                    return [string]$Found
                }

                Write-Host ""
                Write-Host "plink.exe was not found." -ForegroundColor Red
                Write-Host "Install PuTTY and try again." -ForegroundColor Yellow

                Pause-Program
            }

            "2" {

                Show-Header "PLINK SETUP"

                Write-Host ""
                Write-Host 'Example: C:\Program Files\PuTTY\plink.exe' -ForegroundColor DarkGray
                Write-Host ""

                $Path = Read-Host "Enter full path to plink.exe"
                $Path = $Path.Trim().Trim('"')

                if (Test-PlinkPath -Path $Path) {

                    $Found = (Resolve-Path $Path).Path

                    $Config.Files.Plink = $Found

                    $null = Save-Config -Config $Config

                    Write-Host ""
                    Write-Host "Plink path saved successfully." -ForegroundColor Green

                    Pause-Program

                    return [string]$Found
                }

                Write-Host ""
                Write-Host "Invalid plink.exe path." -ForegroundColor Red

                Pause-Program
            }

            "3" {
                return $null
            }

            default {

                Write-Host ""
                Write-Host "Invalid option." -ForegroundColor Red

                Start-Sleep -Seconds 1
            }
        }
    }
}


# ============================================================
# ROUTER CSV
# ============================================================

function Get-RouterFile {

    param(
        [Parameter(Mandatory)]
        $Config
    )

 
    $Path = [string]$Config.Files.Routers

    if ([string]::IsNullOrWhiteSpace($Path)) {
        $Path = ".\routers.csv"
    }

    if ([System.IO.Path]::IsPathRooted($Path)) {
        return $Path
    }

    return (Join-Path $ScriptDirectory $Path)
}


function Ensure-RouterFile {

    param(
        [Parameter(Mandatory)]
        $Config
    )

 
    $Path = Get-RouterFile -Config $Config

 
    if (-not (Test-Path $Path -PathType Leaf)) {

 
        [PSCustomObject]@{
            ID = $null
            Name = ""
            IP = ""
        } |
        Export-Csv -Path $Path -NoTypeInformation -Encoding UTF8
    }

    return $Path
}


function Get-Routers {

    param(
        [Parameter(Mandatory)]
        $Config
    )

 
    $Path = Ensure-RouterFile -Config $Config

    try {

        $Routers = @(Import-Csv $Path)

 
        return $Routers
    }
    catch {

 
        Write-Host ""
        Write-Host "Could not read routers.csv." -ForegroundColor Red
        Write-Host $_.Exception.Message -ForegroundColor Yellow

        return @()
    }
}


# ============================================================
# ROUTER LIST
# ============================================================

function Show-RouterList {

    param(
        [Parameter(Mandatory)]
        $Config
    )

 
    $Routers = Get-Routers -Config $Config

    Write-Host ""
    Write-Host "╔══════════════════════════════════════════════════════════════════════╗" -ForegroundColor Cyan
    Write-Host "║                         " -ForegroundColor Cyan -NoNewline
    Write-Host "ROUTER LIST" -ForegroundColor White -NoNewline
    Write-Host "                                  ║" -ForegroundColor Cyan
    Write-Host "╠══════╦════════════════════════════════╦══════════════════════════════╣" -ForegroundColor Cyan
    Write-Host "║ " -ForegroundColor Cyan -NoNewline
    Write-Host "ID" -ForegroundColor Gray -NoNewline
    Write-Host "   ║ " -ForegroundColor Cyan -NoNewline
    Write-Host "Name" -ForegroundColor Gray -NoNewline
    Write-Host "                           ║ " -ForegroundColor Cyan -NoNewline
    Write-Host "IP" -ForegroundColor Gray -NoNewline
    Write-Host "                           ║" -ForegroundColor Cyan 
    Write-Host "╠══════╬════════════════════════════════╬══════════════════════════════╣" -ForegroundColor Cyan

    foreach ($Router in $Routers) {

        $ID = ([string]$Router.ID).PadRight(4)

        $Name = [string]$Router.Name

        if ($Name.Length -gt 30) {
            $Name = $Name.Substring(0, 30)
        }

        $Name = $Name.PadRight(30)

        $IP = [string]$Router.IP

        if ($IP.Length -gt 28) {
            $IP = $IP.Substring(0, 28)
        }

        $IP = $IP.PadRight(28)

        Write-Host "║ " -ForegroundColor Cyan -NoNewline
        Write-Host $ID -ForegroundColor Yellow -NoNewline
        Write-Host " ║ " -ForegroundColor Cyan -NoNewline
        Write-Host $Name -ForegroundColor Yellow -NoNewline
        Write-Host " ║ " -ForegroundColor Cyan -NoNewline
        Write-Host $IP -ForegroundColor Yellow -NoNewline
        Write-Host " ║" -ForegroundColor Cyan
    }

    Write-Host "╚══════╩════════════════════════════════╩══════════════════════════════╝" -ForegroundColor Cyan
}


function Add-Router {

    param(
        [Parameter(Mandatory)]
        $Config
    )

 
    $Path = Ensure-RouterFile -Config $Config
    $Routers = @(Import-Csv $Path)

    $Name = Read-Host "Router Name"

    if ([string]::IsNullOrWhiteSpace($Name)) {

        Write-Host ""
        Write-Host "Router name cannot be empty." -ForegroundColor Red

        Pause-Program
        return
    }

    $IP = Read-Host "Router IP"

    try {
        [System.Net.IPAddress]::Parse($IP) | Out-Null
    }
    catch {

        Write-Host ""
        Write-Host "Invalid IP address." -ForegroundColor Red

        Pause-Program
        return
    }

    $MaxID = 0

    foreach ($Router in $Routers) {

        $ID = 0

        if ([int]::TryParse([string]$Router.ID, [ref]$ID)) {

            if ($ID -gt $MaxID) {
                $MaxID = $ID
            }
        }
    }

    $Routers += [PSCustomObject]@{
        ID = $MaxID + 1
        Name = $Name
        IP = $IP
    }

    $Routers |
        Export-Csv -Path $Path -NoTypeInformation -Encoding UTF8

    Write-Host ""
    Write-Host "Router added successfully." -ForegroundColor Green

    Pause-Program
}


function Remove-Router {

    param(
        [Parameter(Mandatory)]
        $Config
    )

 
    $Path = Ensure-RouterFile -Config $Config
    $Routers = @(Import-Csv $Path)

    Show-RouterList -Config $Config

    Write-Host ""

    $ID = Read-Host "Enter Router ID to delete"

    $Router =
        $Routers |
        Where-Object {
            [string]$_.ID -eq [string]$ID
        } |
        Select-Object -First 1

    if (-not $Router) {

        Write-Host ""
        Write-Host "Router not found." -ForegroundColor Red

        Pause-Program
        return
    }

    $Confirm = Read-Host "Delete $($Router.Name)? [Y/N]"

    if ($Confirm -notmatch "^[Yy]$") {

        Write-Host ""
        Write-Host "Operation cancelled." -ForegroundColor Yellow

        Pause-Program
        return
    }

    @(
        $Routers |
        Where-Object {
            [string]$_.ID -ne [string]$ID
        }
    ) |
    Export-Csv -Path $Path -NoTypeInformation -Encoding UTF8

    Write-Host ""
    Write-Host "Router deleted successfully." -ForegroundColor Green

    Pause-Program
}


function Edit-Router {

    param(
        [Parameter(Mandatory)]
        $Config
    )

 
    $Path = Ensure-RouterFile -Config $Config
    $Routers = @(Import-Csv $Path)

    Show-RouterList -Config $Config

    Write-Host ""

    $ID = Read-Host "Enter Router ID to edit"

    $Router =
        $Routers |
        Where-Object {
            [string]$_.ID -eq [string]$ID
        } |
        Select-Object -First 1

    if (-not $Router) {

        Write-Host ""
        Write-Host "Router not found." -ForegroundColor Red

        Pause-Program
        return
    }

    Write-Host ""

    $NewName = Read-Host "New Name [$($Router.Name)]"
    $NewIP = Read-Host "New IP [$($Router.IP)]"

    if ([string]::IsNullOrWhiteSpace($NewName)) {
        $NewName = $Router.Name
    }

    if ([string]::IsNullOrWhiteSpace($NewIP)) {
        $NewIP = $Router.IP
    }

    try {
        [System.Net.IPAddress]::Parse($NewIP) | Out-Null
    }
    catch {

        Write-Host ""
        Write-Host "Invalid IP address." -ForegroundColor Red

        Pause-Program
        return
    }

    foreach ($Item in $Routers) {

        if ([string]$Item.ID -eq [string]$Router.ID) {

            $Item.Name = $NewName
            $Item.IP = $NewIP
        }
    }

    $Routers |
        Export-Csv -Path $Path -NoTypeInformation -Encoding UTF8

    Write-Host ""
    Write-Host "Router updated successfully." -ForegroundColor Green

    Pause-Program
}


function Router-Management {

    param(
        [Parameter(Mandatory)]
        $Config
    )

 
    while ($true) {

        Show-Header "ROUTER MANAGEMENT"

       
        Write-Host "║                                                                      ║" -ForegroundColor Cyan
        Write-Host "║  [1] " -ForegroundColor Cyan -NoNewline
        Write-Host "Show Routers" -ForegroundColor White -NoNewline
        Write-Host "                                                    ║" -ForegroundColor Cyan
      
        Write-Host "║  [2] " -ForegroundColor Cyan -NoNewline
        Write-Host "Add Router" -ForegroundColor White -NoNewline
        Write-Host "                                                      ║" -ForegroundColor Cyan

        Write-Host "║  [3] " -ForegroundColor Cyan -NoNewline
        Write-Host "Edit Router" -ForegroundColor White -NoNewline
        Write-Host "                                                     ║" -ForegroundColor Cyan
       
        Write-Host "║  [4] " -ForegroundColor Cyan -NoNewline
        Write-Host "Delete Router" -ForegroundColor White -NoNewline
        Write-Host "                                                   ║" -ForegroundColor Cyan
       
        Write-Host "║  [5] " -ForegroundColor Cyan -NoNewline
        Write-Host "Back" -ForegroundColor White -NoNewline
        Write-Host "                                                            ║" -ForegroundColor Cyan
        Write-Host "╚══════════════════════════════════════════════════════════════════════╝" -ForegroundColor Cyan
       
       Write-Host " "

        $Choice = Read-Host "Select option"

 
        switch ($Choice) {

            "1" {
                Show-RouterList -Config $Config
                Pause-Program
            }

            "2" {
                Add-Router -Config $Config
            }

            "3" {
                Edit-Router -Config $Config
            }

            "4" {
                Remove-Router -Config $Config
            }

            "5" {
                return
            }

            default {

                Write-Host ""
                Write-Host "Invalid option." -ForegroundColor Red
                Start-Sleep -Seconds 1
            }
        }
    }
}


# ============================================================
# SELECT ROUTER
# ============================================================

function Select-Router {

    param(
        [Parameter(Mandatory)]
        $Config
    )

 
    $Routers = Get-Routers -Config $Config

    if ($Routers.Count -eq 0) {

        Write-Host ""
        Write-Host "No routers found." -ForegroundColor Red

        Pause-Program

        return $null
    }

    #Show-Header "SELECT ROUTER"
    Clear-Host
    Show-RouterList -Config $Config

    Write-Host ""

    $Choice = Read-Host "Enter Router ID"

 
    $Selected =
        $Routers |
        Where-Object {
            [string]$_.ID -eq [string]$Choice
        } |
        Select-Object -First 1

    if (-not $Selected) {

        Write-Host ""
        Write-Host "Invalid router selection." -ForegroundColor Red

        Pause-Program

        return $null
    }

 
    return $Selected
}


# ============================================================
# SECURE STRING
# ============================================================

function Convert-SecureStringToPlainText {

    param(
        [Parameter(Mandatory)]
        [Security.SecureString]$SecureString
    )

 
    $BSTR =
        [Runtime.InteropServices.Marshal]::SecureStringToBSTR(
            $SecureString
        )

    try {

        return (
            [Runtime.InteropServices.Marshal]::PtrToStringBSTR(
                $BSTR
            )
        )
    }
    finally {

        [Runtime.InteropServices.Marshal]::ZeroFreeBSTR($BSTR)
    }
}


# ============================================================
# CREDENTIALS
# ============================================================

function Get-Credentials {

    param(
        [Parameter(Mandatory)]
        $Config
    )

 
    if (
        $Config.Credentials.SaveCredentials -eq $true -and
        -not [string]::IsNullOrWhiteSpace(
            [string]$Config.Credentials.Username
        ) -and
        -not [string]::IsNullOrWhiteSpace(
            [string]$Config.Credentials.Password
        )
    ) {

 
        try {

            $SecurePassword =
                ConvertTo-SecureString $Config.Credentials.Password

            $Password =
                Convert-SecureStringToPlainText -SecureString $SecurePassword

            $EnablePassword = ""

            if (
                -not [string]::IsNullOrWhiteSpace(
                    [string]$Config.Credentials.EnablePassword
                )
            ) {

                $SecureEnablePassword =
                    ConvertTo-SecureString $Config.Credentials.EnablePassword

                $EnablePassword =
                    Convert-SecureStringToPlainText -SecureString $SecureEnablePassword
            }

 
            return [PSCustomObject]@{
                Username = [string]$Config.Credentials.Username
                Password = [string]$Password
                EnablePassword = [string]$EnablePassword
            }
        }
        catch {

 
            Write-Host ""
            Write-Host "Saved credentials could not be loaded." -ForegroundColor Yellow
            Write-Host "Please enter them again." -ForegroundColor Yellow
        }
    }

    Show-Header "CREDENTIALS"

    Write-Host ""

    $Username = Read-Host "SSH Username"

 
    $SecurePassword =
        Read-Host "SSH Password" -AsSecureString

 
    Write-Host ""
    Write-Host "Enable password is optional." -ForegroundColor DarkGray
    Write-Host "If a router does not ask for it, it will not be used." -ForegroundColor DarkGray
    Write-Host ""

    $SecureEnablePassword =
        Read-Host "Enable Password (leave empty if not required)" -AsSecureString

 
    Write-Host ""

    $Save = Read-Host "Save credentials for future use? [Y/N]"

 
    if ($Save -match '^[Yy]$') {

        $EncryptedPassword =
            ConvertFrom-SecureString $SecurePassword

        $EnablePlain =
            Convert-SecureStringToPlainText -SecureString $SecureEnablePassword

        if ([string]::IsNullOrWhiteSpace($EnablePlain)) {
            $EncryptedEnablePassword = ""
        }
        else {
            $EncryptedEnablePassword =
                ConvertFrom-SecureString $SecureEnablePassword
        }

        $Config.Credentials.SaveCredentials = $true
        $Config.Credentials.Username = $Username
        $Config.Credentials.Password = $EncryptedPassword
        $Config.Credentials.EnablePassword = $EncryptedEnablePassword

        $null = Save-Config -Config $Config

        Write-Host ""
        Write-Host "Credentials saved successfully." -ForegroundColor Green
    }
    else {

        $Config.Credentials.SaveCredentials = $false
        $Config.Credentials.Username = ""
        $Config.Credentials.Password = ""
        $Config.Credentials.EnablePassword = ""

        $null = Save-Config -Config $Config
    }

    $Password =
        Convert-SecureStringToPlainText -SecureString $SecurePassword

    $EnablePassword =
        Convert-SecureStringToPlainText -SecureString $SecureEnablePassword

 
    return [PSCustomObject]@{
        Username = $Username
        Password = $Password
        EnablePassword = $EnablePassword
    }
}


# ============================================================
# GATEWAY OFFSET
# ============================================================

function Get-GatewayOffset {

    param(
        [Parameter(Mandatory)]
        $Config
    )

 
    $Value = [string]$Config.Network.GatewayOffset

    if ($Value -match '^[+-]?\d+$') {

 
        return [int]$Value
    }

    while ($true) {

        Show-Header "GATEWAY OFFSET"

        Write-Host ""
        Write-Host "Examples:"
        Write-Host "  -1 = one IP before Tunnel IP" -ForegroundColor Yellow
        Write-Host "  +1 = one IP after Tunnel IP" -ForegroundColor Green
        Write-Host "  -2 = two IPs before Tunnel IP" -ForegroundColor Yellow
        Write-Host "  +2 = two IPs after Tunnel IP" -ForegroundColor Green
        Write-Host ""

        $Offset = Read-Host "Gateway Offset"

 
        if ($Offset -match '^[+-]?\d+$') {

            $Config.Network.GatewayOffset = [int]$Offset

            $null = Save-Config -Config $Config

            Write-Host ""
            Write-Host "Gateway Offset saved: $Offset" -ForegroundColor Green

            Start-Sleep -Seconds 1

            return [int]$Offset
        }

        Write-Host ""
        Write-Host "Invalid offset." -ForegroundColor Red

        Start-Sleep -Seconds 1
    }
}


# ============================================================
# IPv4 OFFSET
# ============================================================

function Add-IPv4Offset {

    param(
        [Parameter(Mandatory)]
        [string]$IPAddress,

        [Parameter(Mandatory)]
        [int]$Offset
    )

 
    try {

        $IP = [System.Net.IPAddress]::Parse($IPAddress)

        if (
            $IP.AddressFamily -ne
            [System.Net.Sockets.AddressFamily]::InterNetwork
        ) {
            throw "Only IPv4 addresses are supported."
        }

        $Bytes = $IP.GetAddressBytes()

        [Array]::Reverse($Bytes)

        $Value =
            [BitConverter]::ToUInt32($Bytes, 0)

        $NewValue =
            [int64]$Value + $Offset

        if (
            $NewValue -lt 0 -or
            $NewValue -gt 4294967295
        ) {
            throw "IP address overflow."
        }

        $NewBytes =
            [BitConverter]::GetBytes([uint32]$NewValue)

        [Array]::Reverse($NewBytes)

        $Result =
            ([System.Net.IPAddress]::new($NewBytes)).ToString()

 
        return $Result
    }
    catch {

 
        return $null
    }
}


# ============================================================
# CLEAN TERMINAL
# ============================================================

function Remove-TerminalControlCharacters {

    param(
        [string]$Text
    )

    if ($null -eq $Text) {
        return ""
    }

    $Text =
        [regex]::Replace(
            $Text,
            "`e\[[0-9;?]*[ -/]*[@-~]",
            ""
        )

    $Text =
        $Text.Replace("`0", "")

    return $Text
}


# ============================================================
# READ AVAILABLE OUTPUT
# ============================================================

function Read-AvailableOutput {

    param(
        [Parameter(Mandatory)]
        $Reader
    )

    if ($null -eq $Reader) {
        return ""
    }

    try {
        # CiscoOutputReader exposes a completely non-blocking read.
        return [string]$Reader.ReadAvailable()
    }
    catch {
        return ""
    }
}

function Clear-CiscoStdout {

    param(
        [Parameter(Mandatory)]
        $Reader
    )

 
    if ($null -eq $Reader) {
        return
    }

    try {
        $Reader.Clear()
    }
    catch {
     }
}

function Test-CiscoPrompt {

    param(
        [string]$Text
    )

    if ([string]::IsNullOrWhiteSpace($Text)) {
        return $false
    }

    $Clean =
        Remove-TerminalControlCharacters -Text $Text

    $Clean =
        $Clean.Trim()

    $Lines =
        $Clean -split "`r?`n"

    foreach ($Line in $Lines) {

        $Line = $Line.Trim()

        if ([string]::IsNullOrWhiteSpace($Line)) {
            continue
        }

        if (
            $Line -match
            '^[^\s]+[>#]\s*$'
        ) {
            return $true
        }
    }

    return $false
}


# ============================================================
# READ UNTIL PROMPT
# ============================================================

function Read-UntilPrompt {

    param(
        [Parameter(Mandatory)]
        $Reader,

        [int]$Timeout = 10
    )

 
    if ($null -eq $Reader) {
        return ""
    }

    $Output = New-Object System.Text.StringBuilder
    $Stopwatch = [System.Diagnostics.Stopwatch]::StartNew()

    while ($Stopwatch.Elapsed.TotalSeconds -lt $Timeout) {

        $Chunk = Read-AvailableOutput -Reader $Reader

        if (-not [string]::IsNullOrEmpty($Chunk)) {

            [void]$Output.Append($Chunk)

            $Current = $Output.ToString()
            $CleanCurrent = Remove-TerminalControlCharacters -Text $Current

            if (Test-CiscoPrompt -Text $CleanCurrent) {

                $Stopwatch.Stop()

 
                return $CleanCurrent
            }
        }

        Start-Sleep -Milliseconds 50
    }

    $Stopwatch.Stop()

    # One final non-blocking drain.
    $FinalChunk = Read-AvailableOutput -Reader $Reader

    if (-not [string]::IsNullOrEmpty($FinalChunk)) {
        [void]$Output.Append($FinalChunk)
    }

 
    return (Remove-TerminalControlCharacters -Text $Output.ToString())
}

function Read-UntilPasswordOrPrompt {

    param(
        [Parameter(Mandatory)]
        $Reader,

        [int]$Timeout = 5
    )

 
    if ($null -eq $Reader) {
        return ""
    }

    $Output = New-Object System.Text.StringBuilder
    $Stopwatch = [System.Diagnostics.Stopwatch]::StartNew()

    while ($Stopwatch.Elapsed.TotalSeconds -lt $Timeout) {

        $Chunk = Read-AvailableOutput -Reader $Reader

        if (-not [string]::IsNullOrEmpty($Chunk)) {

            [void]$Output.Append($Chunk)

            $Current = $Output.ToString()
            $CleanCurrent = Remove-TerminalControlCharacters -Text $Current

             

            # Password prompt may be: Password:, password:, Password: , etc.
            if ($CleanCurrent -match '(?im)password\s*:\s*') {

                 $Stopwatch.Stop()
                return $CleanCurrent
            }

            if (Test-CiscoPrompt -Text $CleanCurrent) {

                 $Stopwatch.Stop()
                return $CleanCurrent
            }
        }

        Start-Sleep -Milliseconds 50
    }

    $Stopwatch.Stop()

    $FinalChunk = Read-AvailableOutput -Reader $Reader
    if (-not [string]::IsNullOrEmpty($FinalChunk)) {
        [void]$Output.Append($FinalChunk)
    }

    

    return (Remove-TerminalControlCharacters -Text $Output.ToString())
}

function Start-CiscoSession {

    param(
        [Parameter(Mandatory)]
        [string]$PlinkPath,

        [Parameter(Mandatory)]
        [string]$RouterIP,

        [Parameter(Mandatory)]
        [int]$Port,

        [Parameter(Mandatory)]
        [string]$Username,

        [Parameter(Mandatory)]
        [string]$Password
    )

 
    if (-not (Test-PlinkPath -Path $PlinkPath)) {
        throw "Plink executable was not found: $PlinkPath"
    }

    $ProcessInfo = New-Object System.Diagnostics.ProcessStartInfo
    $ProcessInfo.FileName = $PlinkPath

    # -t is IMPORTANT: Cisco CLI interaction is much more reliable with a PTY.
    $ProcessInfo.Arguments = "-ssh -t -P $Port $Username@$RouterIP -pw `"$Password`""

 
    $ProcessInfo.UseShellExecute = $false
    $ProcessInfo.RedirectStandardInput = $true
    $ProcessInfo.RedirectStandardOutput = $true
    $ProcessInfo.RedirectStandardError = $true
    $ProcessInfo.CreateNoWindow = $true

    try {
        $Process = [System.Diagnostics.Process]::Start($ProcessInfo)

 
        return $Process
    }
    catch {
         throw "Could not start Plink: $($_.Exception.Message)"
    }
}

function Connect-Cisco {

    param(
        [Parameter(Mandatory)]
        [string]$PlinkPath,

        [Parameter(Mandatory)]
        [string]$RouterIP,

        [Parameter(Mandatory)]
        [int]$Port,

        [Parameter(Mandatory)]
        [string]$Username,

        [Parameter(Mandatory)]
        [string]$Password
    )

 
    Show-Header "CONNECTING"

    Write-Host ""
    Write-Host "Router : " -NoNewline
    Write-Host $RouterIP -ForegroundColor Green
    Write-Host "Port   : " -NoNewline
    Write-Host $Port -ForegroundColor Green
    Write-Host ""
    Write-Host "Establishing SSH connection..." -ForegroundColor Cyan

    $Process = Start-CiscoSession `
        -PlinkPath $PlinkPath `
        -RouterIP $RouterIP `
        -Port $Port `
        -Username $Username `
        -Password $Password

 
    $stdin = $Process.StandardInput
    $stdoutRaw = $Process.StandardOutput
    $stderr = $Process.StandardError

  
    # Start ONE permanent stdout reader. All later reads are queue-based and non-blocking.
    $stdout = [CiscoOutputReader]::new($stdoutRaw)

    Start-Sleep -Milliseconds 1200

 
    if ($Process.HasExited) {

 
        $ErrorText = ""
        try { $ErrorText = $stderr.ReadToEnd() } catch { }

 
        try { $stdout.Dispose() } catch { }
        $Process.Dispose()

        throw "SSH connection failed. $ErrorText"
    }

 
    $InitialOutput = ""
    $InitialStopwatch = [System.Diagnostics.Stopwatch]::StartNew()

    while ($InitialStopwatch.Elapsed.TotalSeconds -lt 5) {

        $Chunk = Read-AvailableOutput -Reader $stdout

        if (-not [string]::IsNullOrEmpty($Chunk)) {
            $InitialOutput += $Chunk
            break
        }

        if ($stdout.Ended -and $Process.HasExited) {
            break
        }

        Start-Sleep -Milliseconds 50
    }

    $InitialStopwatch.Stop()

    # Drain any characters that arrived immediately after the first chunk.
    $InitialOutput += Read-AvailableOutput -Reader $stdout

     Write-Host $InitialOutput -ForegroundColor White
      Write-Host $InitialOutput -ForegroundColor DarkGray

    if ([string]::IsNullOrWhiteSpace($InitialOutput) -and $Process.HasExited) {
        $ErrorText = ""
        try { $ErrorText = $stderr.ReadToEnd() } catch { }
        try { $stdout.Dispose() } catch { }
        $Process.Dispose()
        throw "SSH connection failed or Cisco did not provide a CLI prompt. $ErrorText"
    }

    return [PSCustomObject]@{
        Process = $Process
        Stdin = $stdin
        Stdout = $stdout
        Stderr = $stderr
    }
}

function Enter-EnableMode {

    param(
        [Parameter(Mandatory)]
        $Session,

        [string]$EnablePassword = ""
    )

 
    if ($null -eq $Session -or $null -eq $Session.Process -or $null -eq $Session.Stdin -or $null -eq $Session.Stdout) {
        throw "Invalid SSH session."
    }

    if ($Session.Process.HasExited) {
        throw "SSH session has already closed."
    }

    # Do NOT clear and then blindly send 'enable'. First ask for the prompt.
    # This makes the current mode explicit and avoids sending commands into stale output.
    Clear-CiscoStdout -Reader $Session.Stdout

    $Session.Stdin.WriteLine("")
    $Session.Stdin.Flush()

 
    $Output = Read-UntilPrompt -Reader $Session.Stdout -Timeout 5

    if ([string]::IsNullOrWhiteSpace($Output)) {
        throw "No Cisco prompt was received after SSH connection."
    }

    $Clean = Remove-TerminalControlCharacters -Text $Output
    $Lines = $Clean -split "`r?`n"
    $LastPrompt = $null

    foreach ($Line in $Lines) {
        $Line = $Line.Trim()
        if ($Line -match '^[^\s]+[>#]\s*$') {
            $LastPrompt = $Line
        }
    }

 
    # Already privileged.
    if ($LastPrompt -and $LastPrompt.EndsWith("#")) {
         return $true
    }

    # We should be in user EXEC here.
    if (-not ($LastPrompt -and $LastPrompt.EndsWith(">"))) {
        throw "Could not determine Cisco EXEC mode. Last prompt: $LastPrompt"
    }

    Clear-CiscoStdout -Reader $Session.Stdout

    $Session.Stdin.WriteLine("enable")
    $Session.Stdin.Flush()

 
    $Output = Read-UntilPasswordOrPrompt -Reader $Session.Stdout -Timeout 5

    # Write-Host $Output -ForegroundColor DarkGray

    # Cisco can return a prompt immediately if no enable secret is configured.
    $Clean = Remove-TerminalControlCharacters -Text $Output

    if ($Clean -match '(?im)(bad secrets|% ?bad|invalid password|authentication failed|incorrect password)') {
        throw "Enable password was rejected by the Cisco router."
    }

    if ($Clean -match '(?im)password\s*:\s*') {

 
        if ([string]::IsNullOrWhiteSpace($EnablePassword)) {
            Write-Host ""
            Write-Host "Enable password is required." -ForegroundColor Yellow
            Write-Host ""

            $SecureEnable = Read-Host "Enable Password" -AsSecureString
            $EnablePassword = Convert-SecureStringToPlainText -SecureString $SecureEnable
        }

        if ([string]::IsNullOrEmpty($EnablePassword)) {
            throw "Cisco requested an enable password, but no enable password was provided."
        }

 
        # IMPORTANT: this WriteLine is now reached immediately after detecting Password:.
        $Session.Stdin.WriteLine($EnablePassword)
        $Session.Stdin.Flush()

 
        $Output = Read-UntilPrompt -Reader $Session.Stdout -Timeout 5
        $Clean = Remove-TerminalControlCharacters -Text $Output

     #    Write-Host $Clean -ForegroundColor DarkGray

        if ($Clean -match '(?im)(bad secrets|% ?bad|invalid password|authentication failed|incorrect password)') {
            throw "Enable password was rejected by the Cisco router."
        }
    }

    $Clean = Remove-TerminalControlCharacters -Text $Output
    $Lines = $Clean -split "`r?`n"
    $LastPrompt = $null

    foreach ($Line in $Lines) {
        $Line = $Line.Trim()
        if ($Line -match '^[^\s]+[>#]\s*$') {
            $LastPrompt = $Line
        }
    }

 
    if ($LastPrompt -and $LastPrompt.EndsWith("#")) {
         return $true
    }

    # One final prompt check in case the prompt arrived just after the previous read.
    Start-Sleep -Milliseconds 100
    $FinalOutput = Read-AvailableOutput -Reader $Session.Stdout
    if (-not [string]::IsNullOrEmpty($FinalOutput)) {
        $FinalClean = Remove-TerminalControlCharacters -Text $FinalOutput
        if (Test-CiscoPrompt -Text $FinalClean -and $FinalClean.Trim().EndsWith("#")) {
             return $true
        }
    }

    throw "Could not confirm Cisco privileged EXEC mode. Last prompt: $LastPrompt"
}

function Get-TunnelInformation {

    param(
        [Parameter(Mandatory)]
        $Session,

        [Parameter(Mandatory)]
        [string]$Tunnel,

        [string]$EnablePassword = ""
    )

 
    Enter-EnableMode `
        -Session $Session `
        -EnablePassword $EnablePassword |
        Out-Null

 
    Clear-CiscoStdout -Reader $Session.Stdout

 
    $Command =
        "show run interface tunnel $Tunnel"

 
    $Session.Stdin.WriteLine($Command)
    $Session.Stdin.Flush()

 
    $Output =
        Read-UntilPrompt `
            -Reader $Session.Stdout `
            -Timeout 10

    if ([string]::IsNullOrWhiteSpace($Output)) {

 
        throw "No response received from Cisco router."
    }

    $SourceMatch =
        [regex]::Match(
            $Output,
            "(?im)^\s*tunnel\s+source\s+(\d+\.\d+\.\d+\.\d+)"
        )

 
    $DestinationMatch =
        [regex]::Match(
            $Output,
            "(?im)^\s*tunnel\s+destination\s+(\d+\.\d+\.\d+\.\d+)"
        )

 
    if (-not $SourceMatch.Success) {

 
        throw "Could not find Tunnel Source IP."
    }

    if (-not $DestinationMatch.Success) {

 
        throw "Could not find Tunnel Destination IP."
    }

    $Source =
        $SourceMatch.Groups[1].Value

    $Destination =
        $DestinationMatch.Groups[1].Value

 
    return [PSCustomObject]@{
        Source = $Source
        Destination = $Destination
        RawOutput = $Output
    }
}


# ============================================================
# CISCO PING
# ============================================================

function Invoke-CiscoPing {

    param(
        [Parameter(Mandatory)]
        $Session,

        [Parameter(Mandatory)]
        [string]$IPAddress,

        [int]$Count = 5,

        [int]$Timeout = 15
    )

  
    Clear-CiscoStdout -Reader $Session.Stdout

 
    $Command =
        "ping $IPAddress repeat $Count"

 
    $Session.Stdin.WriteLine($Command)
    $Session.Stdin.Flush()

 
    $Output =
        Read-UntilPrompt `
            -Reader $Session.Stdout `
            -Timeout $Timeout

 
    return $Output
}


# ============================================================
# OUTPUT TO BOX
# ============================================================

function Convert-OutputToBoxLines {

    param(
        [string]$Output
    )

 
    if ([string]::IsNullOrWhiteSpace($Output)) {

        return @(
            "No output received."
        )
    }

    $Result = @()

    foreach ($Line in ($Output -split "`r?`n")) {

        if ([string]::IsNullOrWhiteSpace($Line)) {
            continue
        }

        $CleanLine =
            $Line.Trim()

        if ($CleanLine.Length -gt 70) {

            $CleanLine =
                $CleanLine.Substring(0, 70)
        }

        $Result += $CleanLine
    }

    if ($Result.Count -eq 0) {

        $Result = @(
            "No output received."
        )
    }

    return $Result
}


# ============================================================
# SHOW TUNNEL INFORMATION
# ============================================================

function Show-TunnelInformation {

    param(
        [Parameter(Mandatory)]
        [string]$RouterName,

        [Parameter(Mandatory)]
        [string]$RouterIP,

        [Parameter(Mandatory)]
        [string]$Tunnel,

        [Parameter(Mandatory)]
        [string]$Source,

        [Parameter(Mandatory)]
        [string]$Destination,

        [Parameter(Mandatory)]
        [string]$SourceGateway,

        [Parameter(Mandatory)]
        [string]$DestinationGateway,

        [Parameter(Mandatory)]
        [int]$GatewayOffset
    )

 
  #  Show-Header "TUNNEL INFORMATION"

    $Lines = @(
        "Router Name         : $RouterName"
        "Router IP           : $RouterIP"
        "Tunnel Number       : $Tunnel"
        ""
        "Tunnel Source       : $Source"
        "Source Gateway      : $SourceGateway"
        ""
        "Tunnel Destination  : $Destination"
        "Destination Gateway : $DestinationGateway"
        ""
        "Gateway Offset      : $GatewayOffset"
    )

    Show-Box `
        -Title "TUNNEL INFORMATION" `
        -Lines $Lines `
        -TitleColor White `
        -TextColor Yellow
}


# ============================================================
# SHOW PING RESULT
# ============================================================

function Show-PingResult {

    param(
        [Parameter(Mandatory)]
        [string]$Title,

        [Parameter(Mandatory)]
        [string]$IPAddress,

        [Parameter(Mandatory)]
        [string]$Output
    )

 
    $Lines = @()

    $Lines += "Target : $IPAddress"
    $Lines += ""

    $OutputLines =
        Convert-OutputToBoxLines -Output $Output

    $Lines += $OutputLines

    Show-Box `
        -Title $Title `
        -Lines $Lines `
        -TitleColor Cyan `
        -TextColor White
}


# ============================================================
# MAIN TUNNEL CHECK
# ============================================================

function Start-TunnelCheck {

    param(
        [Parameter(Mandatory)]
        $Config,

        [Parameter(Mandatory)]
        [string]$PlinkPath,

        [Parameter(Mandatory)]
        $Credential
    )

 
    $Session = $null

    $SelectedRouter =
        Select-Router -Config $Config

 
    if (-not $SelectedRouter) {

 
        return
    }

    Show-Header "TUNNEL CHECK"

    Write-Host ""
    Write-Host "Selected Router" -ForegroundColor Cyan
    Write-Host ""
    Write-Host "Name : $($SelectedRouter.Name)"
    Write-Host "IP   : $($SelectedRouter.IP)"
    Write-Host ""

    do {

        Write-Host "Enter Tunnel Number" -ForegroundColor Yellow
        Write-Host "Example: 0, 1, 10, 100, 1000, ..." -ForegroundColor DarkGray

        $Tunnel =
            Read-Host "Tunnel Number"

 
        if (
            $Tunnel -notmatch '^\d+$'
        ) {

            Write-Host ""
            Write-Host "Invalid Tunnel Number!" -ForegroundColor Red
            Write-Host "Please enter a valid number." -ForegroundColor Yellow
            Write-Host ""

            $ValidTunnel = $false

            continue
        }

        try {

            $TunnelNumber =
                [int64]$Tunnel

            $ValidTunnel = $true
        }
        catch {

            Write-Host ""
            Write-Host "Invalid Tunnel Number!" -ForegroundColor Red

            $ValidTunnel = $false
        }

    }
    while (-not $ValidTunnel)

    $Tunnel =
        [string]$TunnelNumber

 
    try {

 
        $Session =
            Connect-Cisco `
                -PlinkPath $PlinkPath `
                -RouterIP $SelectedRouter.IP `
                -Port ([int]$Config.Cisco.SSHPort) `
                -Username $Credential.Username `
                -Password $Credential.Password

 
        if (-not $Session) {

 
            Pause-Program
            return
        }

 
        Show-Header "FETCHING TUNNEL INFORMATION"


        $TunnelInfo =
            Get-TunnelInformation `
                -Session $Session `
                -Tunnel $Tunnel `
                -EnablePassword $Credential.EnablePassword
         Clear-Host
 
        $GatewayOffset =
            [int]$Config.Network.GatewayOffset

 
        $SourceGateway =
            Add-IPv4Offset `
                -IPAddress $TunnelInfo.Source `
                -Offset $GatewayOffset

 
        $DestinationGateway =
            Add-IPv4Offset `
                -IPAddress $TunnelInfo.Destination `
                -Offset $GatewayOffset

 
        if (-not $SourceGateway) {
            throw "Could not calculate Source Gateway."
        }

        if (-not $DestinationGateway) {
            throw "Could not calculate Destination Gateway."
        }

        Show-TunnelInformation `
            -RouterName $SelectedRouter.Name `
            -RouterIP $SelectedRouter.IP `
            -Tunnel $Tunnel `
            -Source $TunnelInfo.Source `
            -Destination $TunnelInfo.Destination `
            -SourceGateway $SourceGateway `
            -DestinationGateway $DestinationGateway `
            -GatewayOffset $GatewayOffset

 
 #       Show-Header "PINGING SOURCE GATEWAY"  
        $SourcePing =
            Invoke-CiscoPing `
                -Session $Session `
                -IPAddress $SourceGateway `
                -Count ([int]$Config.Ping.Count) `
                -Timeout ([int]$Config.Ping.Timeout)


        Show-PingResult `
            -Title "SOURCE GATEWAY RESULT" `
            -IPAddress $SourceGateway `
            -Output $SourcePing


    #    Show-Header "PINGING DESTINATION GATEWAY"  -NoClear
        $DestinationPing =
            Invoke-CiscoPing `
                -Session $Session `
                -IPAddress $DestinationGateway `
                -Count ([int]$Config.Ping.Count) `
                -Timeout ([int]$Config.Ping.Timeout)


        Show-PingResult `
            -Title "DESTINATION GATEWAY RESULT" `
            -IPAddress $DestinationGateway `
            -Output $DestinationPing


        Show-Box `
            -Title "CHECK COMPLETE" `
            -Lines @(
                "Router : $($SelectedRouter.Name)"
                "Tunnel : $Tunnel"
                ""
                "Source Gateway      : $SourceGateway"
                "Destination Gateway : $DestinationGateway"
            ) `
            -TitleColor Green `
            -TextColor White

        Pause-Program
    }
    catch {


        $Message =
            $_.Exception.Message

        Show-Box `
            -Title "ERROR" `
            -Lines @(
                $Message
                ""
                "Router : $($SelectedRouter.Name)"
                "Tunnel : $Tunnel"
            ) `
            -TitleColor Red `
            -TextColor Yellow

        Pause-Program
    }
    finally {


        if ($Session) {

            try {

                if (
                    $Session.Stdin -and
                    -not $Session.Process.HasExited
                ) {


                    $Session.Stdin.WriteLine("exit")
                    $Session.Stdin.Flush()

                    Start-Sleep -Milliseconds 300
                }
            }
            catch {
            }

            try {

                if (
                    $Session.Process -and
                    -not $Session.Process.HasExited
                ) {


                    $Session.Process.Kill()
                }
            }
            catch {
            }

            try {

                if ($Session.Stdout) {
                    $Session.Stdout.Dispose()
                }
            }
            catch {
            }

            try {

                if ($Session.Process) {


                    $Session.Process.Dispose()
                }
            }
            catch {
            }
        }

    }
}


# ============================================================
# CONFIGURATION MENU
# ============================================================

function Configuration-Menu {

    param(
        [Parameter(Mandatory)]
        $Config
    )


    while ($true) {

        Show-Header "CONFIGURATION"
               
        Write-Host "║                                                                      ║" -ForegroundColor Cyan
        Write-Host "║  [1] " -ForegroundColor Cyan -NoNewline
        Write-Host "Credentials" -ForegroundColor White -NoNewline
        Write-Host "                                                     ║" -ForegroundColor Cyan
      
        Write-Host "║  [2] " -ForegroundColor Cyan -NoNewline
        Write-Host "Gateway Offset" -ForegroundColor White -NoNewline
        Write-Host "                                                  ║" -ForegroundColor Cyan

        Write-Host "║  [3] " -ForegroundColor Cyan -NoNewline
        Write-Host "Plink Path" -ForegroundColor White -NoNewline
        Write-Host "                                                      ║" -ForegroundColor Cyan
       
        Write-Host "║  [4] " -ForegroundColor Cyan -NoNewline
        Write-Host "Ping Settings" -ForegroundColor White -NoNewline
        Write-Host "                                                   ║" -ForegroundColor Cyan
       
        Write-Host "║  [5] " -ForegroundColor Cyan -NoNewline
        Write-Host "Cisco SSH Settings" -ForegroundColor White -NoNewline
        Write-Host "                                              ║" -ForegroundColor Cyan

        Write-Host "║  [6] " -ForegroundColor Cyan -NoNewline
        Write-Host "Show Current Configuration" -ForegroundColor White -NoNewline
        Write-Host "                                      ║" -ForegroundColor Cyan
        Write-Host "║  [7] " -ForegroundColor Cyan -NoNewline
        Write-Host "Reset Saved Credentials" -ForegroundColor White -NoNewline
        Write-Host "                                         ║" -ForegroundColor Cyan
        Write-Host "║  [8] " -ForegroundColor Cyan -NoNewline
        Write-Host "Back" -ForegroundColor White -NoNewline
        Write-Host "                                                            ║" -ForegroundColor Cyan



        Write-Host "╚══════════════════════════════════════════════════════════════════════╝" -ForegroundColor Cyan
       
       Write-Host " "

  

        $Choice =
            Read-Host "Select option"


        switch ($Choice) {

            "1" {


                $Config.Credentials.SaveCredentials = $false
                $Config.Credentials.Username = ""
                $Config.Credentials.Password = ""
                $Config.Credentials.EnablePassword = ""

                $null = Save-Config -Config $Config

                $null =
                    Get-Credentials -Config $Config
            }

            "2" {

                Show-Header "GATEWAY OFFSET"

                Write-Host ""
                Write-Host "Current Offset: $($Config.Network.GatewayOffset)" -ForegroundColor Cyan
                Write-Host ""

                $Offset =
                    Read-Host "New Gateway Offset"

                if ($Offset -match '^[+-]?\d+$') {

                    $Config.Network.GatewayOffset =
                        [int]$Offset

                    $null = Save-Config -Config $Config

                    Write-Host ""
                    Write-Host "Gateway Offset updated." -ForegroundColor Green
                }
                else {

                    Write-Host ""
                    Write-Host "Invalid offset." -ForegroundColor Red
                }

                Pause-Program
            }

            "3" {


                $Config.Files.Plink = ""

                $null = Save-Config -Config $Config

                $NewPlink =
                    Get-Plink -Config $Config

                if ($NewPlink) {

                    Write-Host ""
                    Write-Host "Plink path updated successfully." -ForegroundColor Green
                    Write-Host $NewPlink -ForegroundColor DarkGray

                    Start-Sleep -Seconds 1
                }
            }

            "4" {

                Show-Header "PING SETTINGS"

                Write-Host ""

                $Count =
                    Read-Host "Ping Count [$($Config.Ping.Count)]"

                $Timeout =
                    Read-Host "Ping Timeout [$($Config.Ping.Timeout)]"

                if ([string]::IsNullOrWhiteSpace($Count)) {
                    $Count = $Config.Ping.Count
                }

                if ([string]::IsNullOrWhiteSpace($Timeout)) {
                    $Timeout = $Config.Ping.Timeout
                }

                if (
                    $Count -match '^\d+$' -and
                    $Timeout -match '^\d+$' -and
                    [int]$Count -gt 0 -and
                    [int]$Timeout -gt 0
                ) {

                    $Config.Ping.Count =
                        [int]$Count

                    $Config.Ping.Timeout =
                        [int]$Timeout

                    $null = Save-Config -Config $Config

                    Write-Host ""
                    Write-Host "Ping settings updated." -ForegroundColor Green
                }
                else {

                    Write-Host ""
                    Write-Host "Invalid value." -ForegroundColor Red
                }

                Pause-Program
            }

            "5" {

                Show-Header "CISCO SSH SETTINGS"

                Write-Host ""

                $Port =
                    Read-Host "SSH Port [$($Config.Cisco.SSHPort)]"

                $Timeout =
                    Read-Host "Command Timeout [$($Config.Cisco.CommandTimeout)]"

                if ([string]::IsNullOrWhiteSpace($Port)) {
                    $Port = $Config.Cisco.SSHPort
                }

                if ([string]::IsNullOrWhiteSpace($Timeout)) {
                    $Timeout = $Config.Cisco.CommandTimeout
                }

                if (
                    $Port -match '^\d+$' -and
                    $Timeout -match '^\d+$' -and
                    [int]$Port -gt 0 -and
                    [int]$Timeout -gt 0
                ) {

                    $Config.Cisco.SSHPort =
                        [int]$Port

                    $Config.Cisco.CommandTimeout =
                        [int]$Timeout

                    $null = Save-Config -Config $Config

                    Write-Host ""
                    Write-Host "Cisco settings updated." -ForegroundColor Green
                }
                else {

                    Write-Host ""
                    Write-Host "Invalid value." -ForegroundColor Red
                }

                Pause-Program
            }

            "6" {

                Show-Header "CURRENT CONFIGURATION"

                Write-Host ""

                Write-Host "Credentials:" -ForegroundColor Cyan
                Write-Host "  Save Credentials : $($Config.Credentials.SaveCredentials)"
                Write-Host "  Username         : $($Config.Credentials.Username)"
                Write-Host "  SSH Password     : ********"
                Write-Host "  Enable Password  : ********"

                Write-Host ""

                Write-Host "Network:" -ForegroundColor Cyan
                Write-Host "  Gateway Offset   : $($Config.Network.GatewayOffset)"

                Write-Host ""

                Write-Host "Ping:" -ForegroundColor Cyan
                Write-Host "  Count            : $($Config.Ping.Count)"
                Write-Host "  Timeout          : $($Config.Ping.Timeout)"

                Write-Host ""

                Write-Host "Cisco:" -ForegroundColor Cyan
                Write-Host "  SSH Port         : $($Config.Cisco.SSHPort)"
                Write-Host "  Command Timeout  : $($Config.Cisco.CommandTimeout)"

                Write-Host ""

                Write-Host "Files:" -ForegroundColor Cyan
                Write-Host "  Routers          : $($Config.Files.Routers)"
                Write-Host "  Plink            : $($Config.Files.Plink)"

                Pause-Program
            }

            "7" {


                $Config.Credentials.SaveCredentials = $false
                $Config.Credentials.Username = ""
                $Config.Credentials.Password = ""
                $Config.Credentials.EnablePassword = ""

                $null = Save-Config -Config $Config

                Write-Host ""
                Write-Host "Saved credentials have been removed." -ForegroundColor Green

                Pause-Program
            }

            "8" {

                return
            }

            default {

                Write-Host ""
                Write-Host "Invalid option." -ForegroundColor Red

                Start-Sleep -Seconds 1
            }
        }
    }
}


# ============================================================
# MAIN MENU
# ============================================================

function Main-Menu {

    param(
        [Parameter(Mandatory)]
        $Config,

        [Parameter(Mandatory)]
        [string]$PlinkPath,

        [Parameter(Mandatory)]
        $Credential
    )


    while ($true) {

        Show-Header

        Write-Host "║                                                                      ║" -ForegroundColor Cyan

        Write-Host "║  [1] " -ForegroundColor Cyan -NoNewline
        Write-Host "Check Tunnel" -ForegroundColor White -NoNewline
        Write-Host "                                                    ║" -ForegroundColor Cyan




        Write-Host "║  [2] " -ForegroundColor Cyan -NoNewline
        Write-Host "Router Management" -ForegroundColor White -NoNewline
        Write-Host "                                               ║" -ForegroundColor Cyan

        Write-Host "║  [3] " -ForegroundColor Cyan -NoNewline
        Write-Host "Configuration" -ForegroundColor White -NoNewline
        Write-Host "                                                   ║" -ForegroundColor Cyan

        Write-Host "║  [4] " -ForegroundColor Cyan -NoNewline
        Write-Host "Exit" -ForegroundColor White -NoNewline
        Write-Host "                                                            ║" -ForegroundColor Cyan
        Write-Host "╚══════════════════════════════════════════════════════════════════════╝" -ForegroundColor Cyan
        Write-Host ""




        Write-Host "  Plink   : " -NoNewline
        Write-Host $PlinkPath -ForegroundColor DarkGray

        Write-Host "  Offset  : " -NoNewline
        Write-Host $Config.Network.GatewayOffset -ForegroundColor Yellow

       

        $RouterCount =
            (Get-Routers -Config $Config).Count
        if($null -ne $RouterCount){
         Write-Host "  Routers : " -NoNewline
        Write-Host $RouterCount -ForegroundColor Green
        }
        Write-Host ""

        $Choice =
            Read-Host "Select option"


        switch ($Choice) {

            "1" {


                Start-TunnelCheck `
                    -Config $Config `
                    -PlinkPath $PlinkPath `
                    -Credential $Credential
            }

            "2" {


                Router-Management `
                    -Config $Config
            }

            "3" {


                Configuration-Menu `
                    -Config $Config


                $NewPlink =
                    Get-Plink -Config $Config

                if ($NewPlink) {

                    $PlinkPath =
                        [string]$NewPlink
                }
                else {

                    Write-Host ""
                    Write-Host "Plink is required to continue." -ForegroundColor Red

                    Pause-Program

                    continue
                }

                $Credential =
                    Get-Credentials -Config $Config

            }

            "4" {


                Clear-Host

                Show-Box `
                    -Title "THANK YOU" `
                    -Lines @(
                        "Cisco Tunnel Gateway Checker"
                        ""
                        "Powered By Ali Zarifi"
                    ) `
                    -TitleColor Cyan `
                    -TextColor White

                Read-Host "Press Enter To Exit..."

                return
            }

            default {

                Write-Host ""
                Write-Host "Invalid option." -ForegroundColor Red

                Start-Sleep -Seconds 1
            }
        }
    }
}


# ============================================================
# PROGRAM START
# ============================================================

try {


    $Config =
        Load-Config


    $Config =
        Update-ConfigStructure -Config $Config


    $null =
        Ensure-RouterFile -Config $Config


    $OffsetValue =
        [string]$Config.Network.GatewayOffset


    if (
        [string]::IsNullOrWhiteSpace($OffsetValue) -or
        $OffsetValue -notmatch '^[+-]?\d+$'
    ) {


        $null =
            Get-GatewayOffset -Config $Config
    }


    $PlinkPath =
        Get-Plink -Config $Config


    if (-not $PlinkPath) {


        Show-Box `
            -Title "PLINK REQUIRED" `
            -Lines @(
                "Plink is required to continue."
                ""
                "Please install PuTTY / Plink"
                "and run the program again."
            ) `
            -TitleColor Red `
            -TextColor Yellow

        Pause-Program

        exit
    }

    $PlinkPath =
        [string]$PlinkPath


    $Credential =
        Get-Credentials -Config $Config


    Main-Menu `
        -Config $Config `
        -PlinkPath $PlinkPath `
        -Credential $Credential

}
catch {

 
    Clear-Host

    $ErrorMessage =
        $_.Exception.Message

  
    if ($ErrorMessage.Length -gt 66) {

        $ErrorMessage =
            $ErrorMessage.Substring(0, 66)
    }

    Show-Box `
        -Title "FATAL ERROR" `
        -Lines @(
            $ErrorMessage
            ""
            "Line: $($_.InvocationInfo.ScriptLineNumber)"
        ) `
        -TitleColor Red `
        -TextColor Yellow

    Pause-Program
}

 