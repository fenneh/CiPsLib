
function Install-TopShelfService {
    param
    (
        [string] $ExePath
    )
    Write-Host "Installing service"
    & $ExePath install | Write-Host
    if ($LastExitCode -ne 0) { throw 'Failed to install service' }

    Write-Host "Starting service"
    & $ExePath start | Write-Host
    if ($LastExitCode -ne 0) { throw 'Failed to start service' }    
}


function Uninstall-TopShelfService {
    param
    (
        [string] $ServiceName,
        [string] $ExePath
    )
    $Service = Get-Service -Name $ServiceName -ErrorAction SilentlyContinue
    if ($Service) {
        Write-Host 'Stopping and uninstalling service'
        & $ExePath stop | Write-Host
        & $ExePath uninstall | Write-Host
    }
    else
    {
        Write-Host 'Nothing to uninstall'
    }
}


Export-ModuleMember -function * -alias *

Write-Host 'Imported CsPsLib.TopShelf.psm1'
