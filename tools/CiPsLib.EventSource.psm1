
function Create-EventSource {
    param
    (
        [string] $EventSourceName
    )
    if ([System.Diagnostics.EventLog]::SourceExists($EventSourceName) -eq $false)
    {
        Write-Host 'Creating event source'
        [System.Diagnostics.EventLog]::CreateEventSource($EventSourceName, "Application")
    }
    else
    {
        Write-Host 'Event source already created'
    }
}


Export-ModuleMember -function * -alias *

Write-Host 'Imported CsPsLib.EventSource.psm1'

