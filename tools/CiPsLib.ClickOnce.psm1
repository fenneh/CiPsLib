
function UpdateSetupExeUrl {
	param
	(
		[string] $SetupExePath,
		[string] $Url,
		[switch] $Verbose
	)
    if ($Verbose) {
        $VerbosePreference = 'Continue'
    }
	Write-Verbose "Updating '$SetupExePath' to URL '$Url'"
	& $SetupExePath /url=$Url | Write-Verbose
	CheckError "Failed to update '$SetupExePath' URL to $Url"
}

function ResignClickOnceApplication {
	param
	(
		[string] $ApplicationFilesDirectory,
		[string] $ManifestFilePath,
		[string] $ApplicationFilePath,
		[string] $CertificateFilePath,
		[string] $CertificateFilePassword,
		[string] $TempDirectory,
		[switch] $Verbose
	)
    if ($Verbose) {
        $VerbosePreference = 'Continue'
    }
	CopyAndStripFileName -Source $ApplicationFilesDirectory -Destination $TempDirectory -PartToStrip ".deploy" -Verbose
	$MageExePath = 'C:\Program Files (x86)\Microsoft SDKs\Windows\v8.0A\bin\NETFX 4.0 Tools\mage.exe'
	& $MageExePath -Update $ManifestFilePath -FromDirectory $TempDirectory | Write-Verbose
	CheckError "Failed to update $ManifestFilePath"
	& $MageExePath -Sign $ManifestFilePath -CertFile $CertificateFilePath -Password $CertificateFilePassword | Write-Verbose
	CheckError "Failed to sign $ManifestFilePath"
	& $MageExePath -Update $ApplicationFilePath -AppManifest $ManifestFilePath | Write-Verbose
	CheckError "Failed to update $ApplicationFilePath"
	& $MageExePath -Sign $ApplicationFilePath -CertFile $CertificateFilePath -Password $CertificateFilePassword | Write-Verbose
	CheckError "Failed to sign $ApplicationFilePath"
}

function CopyAndStripFileName {
	param
	(
		[string] $Source,
		[string] $Destination,
		[string] $PartToStrip,
		[switch] $Verbose
	)
    if ($Verbose) {
        $VerbosePreference = 'Continue'
    }
	$FileList = Get-ChildItem -Path $Source -Recurse
	foreach ($filePath in $FileList) {
		if ($filePath.PSIsContainer) {
			$newLocation = $filePath.FullName.Replace($Source, $Destination)
			Write-Verbose "Creating new directory at '$newLocation'"
			New-Item -ItemType directory $newLocation
		} else {
			$srcPath = $filePath.FullName
			$dstPath = $srcPath.Replace(".deploy","").Replace($Source, $Destination)
			Write-Verbose "Copying from '$srcPath' -> '$dstPath'"
			$fileContent = [System.IO.File]::ReadAllBytes($srcPath)
			[System.IO.File]::WriteAllBytes($dstPath, $fileContent)
		}
	}
}

Export-ModuleMember -function * -alias *

Write-Host 'Imported CiPsLib.ClickOnce.psm1'
