#requires -version 5.0

<#PSScriptInfo
 
.VERSION 1.0
 
.GUID
 
.AUTHOR Bindusar Kushwaha
 
.COMPANYNAME Microsoft
 
.COPYRIGHT
 
.TAGS
 
.LICENSEURI
 
.PROJECTURI
 
.ICONURI
 
.EXTERNALMODULEDEPENDENCIES
 
.REQUIREDSCRIPTS
 
.EXTERNALSCRIPTDEPENDENCIES
 
.RELEASENOTES
The purpose of this script is to trigger Intune Device Sync in bulk by passing a group ID (Group's Object ID).
All the devices in that group will be synced with Intune.

This needs Azure AD admin and INtune ADmin rights to execute the script.
#>

<#
DISCLAIMER STARTS 
This Sample Code is provided for the purpose of illustration only and is not intended to be used in a #production environment. THIS SAMPLE CODE AND ANY RELATED INFORMATION ARE PROVIDED "AS IS" #WITHOUT WARRANTY OF ANY KIND, EITHER EXPRESSED OR IMPLIED, INCLUDING BUT NOT LIMITED TO #THE IMPLIED WARRANTIES OF MERCHANTABILITY AND/OR FITNESS FOR A PARTICULAR PURPOSE. We #grant You a nonexclusive, royalty-free right to use and modify the Sample Code and to reproduce and #distribute the object code form of the Sample Code, provided that You agree:(i) to not use Our name, #logo, or trademarks to market Your software product in which the Sample Code is embedded; (ii) to #include a valid copyright notice on Your software product in which the Sample Code is embedded; and #(iii) to indemnify, hold harmless, and defend Us and Our suppliers from and against any claims or #lawsuits, including attorneys’ fees, that arise or result from the use or distribution of the Sample Code." 
"This sample script is not supported under any Microsoft standard support program or service. The #sample script is provided AS IS without warranty of any kind. Microsoft further disclaims all implied #warranties including, without limitation, any implied warranties of merchantability or of fitness for a #particular purpose. The entire risk arising out of the use or performance of the sample scripts and documentation remains with you. In no event shall Microsoft, its authors, or anyone else involved in #the creation, production, or delivery of the scripts be liable for any damages whatsoever (including, #without limitation, damages for loss of business profits, business interruption, loss of business information, or other pecuniary loss) arising out of the use of or inability to use the sample scripts or #documentation, even if Microsoft has been advised of the possibility of such damages" 
DISCLAIMER ENDS 
#>

Function Write-Host()
{
    <#
    .SYNOPSIS
    This function is used to configure the logging.
    .DESCRIPTION
    This function is used to configure the logging.
    .EXAMPLE
    Logging -Message "Starting installation" -severity 1 -component "Installation"
    Logging -Message "Something went wrong" -severity 2 -component "Installation"
    Logging -Message "BIG Error Message" -severity 3 -component "Installation"
    .NOTES
    NAME: Logging
    #>
    PARAM(
        [Parameter(Mandatory=$true)]$Message,
         #[String]$Path = "c:\Windows\Temp\Autopilot_Custom.log",
         [int]$severity=1,
         [string]$component="Main"
         )

         $logdir="C:\Temp"

        If(!(Test-Path $logdir))
        {
            $null = New-Item -Path $logdir -ItemType Directory -Force -ErrorAction SilentlyContinue
        }
        
        $StartTime = Get-Date -Format "dd-MM-yyyy"
        [String]$Path = "$Logdir\SyncStatus_$StartTime.log"
        
        $today=Get-Date -Format yyyyMMdd-HH
        $TimeZoneBias = Get-CimInstance -Query "Select Bias from Win32_TimeZone"
        $Date = Get-Date -Format "HH:mm:ss.fff"
        $Date2 = Get-Date -Format "MM-dd-yyyy"
        #$type =1

         "<![LOG[$Message]LOG]!><time=$([char]34)$date$($TimeZoneBias.bias)$([char]34) date=$([char]34)$date2$([char]34) component=$([char]34)$component$([char]34) context=$([char]34)$([char]34) type=$([char]34)$severity$([char]34) thread=$([char]34)$([char]34) file=$([char]34)$([char]34)>"| Out-File -FilePath $Path -Append -NoClobber -Encoding default 

}

$Error.Clear()

Write-Host "====================Starting the Script $($MyInvocation.MyCommand.Name)"
Write-Host "Running as: $([char]34)$(whoami)$([char]34)"
Write-Host "Running under: $([char]34)$((Get-WMIObject -Class Win32_ComputerSystem -ErrorAction SilentlyContinue).UserName)$([char]34)"
Write-Host "Running on: $([char]34)$(hostname)$([char]34)"
Write-Host "Importing Powershell modules for Intune"

if((Get-Module Microsoft.Graph.Intune) -eq $null)
{
    Write-Host "Intune Module is missing. Installing Microsoft.Graph.Intune"
    try 
    { 
        Import-Module -Name Microsoft.Graph.Intune -ErrorAction Stop
    }
    catch
    {
        Write-Host $Error[0]
        Write-host "Microsoft.Graph.Intune module not found in common module path, installing in the current user scope..."
        Install-Module -Name Microsoft.Graph.Intune -Scope CurrentUser -Force
        Import-Module Microsoft.Graph.Intune -Force
    }
}
if((Get-Module AzureAD) -eq $null)
{
    Write-Host "AzureAD Module is missing. Installing AzureAD"
    Try
    {
        Install-Module -Name AzureAD -Force
        Write-Host "Successfully INstalled Azure AD module..."
    }
    Catch
    {
        Write-Host "Failed to install Azure AD module. Please install it manually and try again..."
    }
}

Write-Host "Connecting to AzureAD"
Try
{
    Connect-AzureAD -ErrorAction Stop
    Write-Host "Successfully COnnected to Azure AD"
}
Catch
{
    Write-Error "Failed to connect to Azure AD..."
    Write-Host $Error[0]
    Exit 1
}

Write-host "Connecting to Graph API..."

try
{
    Connect-MSGraph -ErrorAction Stop
    Write-Host "Successfully Connected to Graph API"
} 
catch
{
    Write-Error "Failed to connect to MSGraph"
    Write-Host $Error[0]
    Exit 1
}

Write-Host "Waiting for Azure AD group ID Input..."
$AADGrpID=Read-Host "Please provide the Azure AD Group's Object ID... (Only One)"

Write-host "Getting a list of devices from Group $AADGrpID"

try
{
    $AADMemDevices=Get-AzureADGroupMember -ObjectId "$AADGrpID" -ErrorAction Stop
    Write-Host "Successfully retrieved devices from group $AADGrpID"
}
catch
{
    Write-Error "Failed to fetch devices from group..."
    Write-Host $Error[0]
    Exit 1
}

Write-Host "Fetching devices from Intune Portal"

Try
{
    $intuneDevices = Get-IntuneManagedDevice -Filter "contains(operatingsystem, 'Windows')" | Get-MSGraphAllPages
    Write-Host "Successfully retrieved devices from INtune..."
}
Catch
{
    Write-Error "Failed to fetch devices from Intune..."
    Write-Host $Error[0]
    Exit 1
}

Write-Host "Reading Azure AD devices one by one..."

if (($AADMemDevices).count -gt 0)
{
    Write-Host "Found $($AADMemDevices.count) devices in Azure AD group supplied..."
    Foreach($AADDev in $AADMemDevices)
    {
        Write-Host "Initiating Sync on: $($AADDev.DisplayName)"
        
        If($AADDev.DeviceOSType -eq "Windows" -and $AADDev.IsManaged -eq "True" -and $AADDev.ObjectType -eq "Device")
        {

            Try
            {
                $DevToSync=$intuneDevices | where-object{$_.azureADDeviceId -eq $AADDev.DeviceId}
                $DevToSync | Invoke-IntuneManagedDeviceSyncDevice -ErrorAction Stop
                Write-Host "Sync Completed on : $($AADDev.DisplayName)"
            }
            Catch
            {
                Write-Error "Failed to sync..."
                Write-Host $Error[0]
            }
        }
        Else
        {
            Write-Host "Device : $($AADDev.DisplayName) is NON Windows or NOT Managed by Intune or its USER Record... Skipping it..."
        }
    }
} 
else 
{
    Write-host "No Device found in this group... please check manually..."
}

Write-Host "====================ENding the Script $($MyInvocation.MyCommand.Name)"
