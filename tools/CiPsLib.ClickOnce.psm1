
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
	Write-Verbose "UpdateSetupExeUrl: Updating '$SetupExePath' to URL '$Url'"
	Call -Command { & $SetupExePath "/url=$Url" } -ThrowMessage "Configuring '$SetupExePath' failed" -Verbose
}

function ResignClickOnceApplication {
	param
	(
		[string] $ApplicationFilesDirectory,
		[string] $ManifestFilePath,
		[string] $ApplicationFilePath,
		[string] $CertificateFilePath,
		[string] $CertificateFilePassword = "",
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
	if ($CertificateFilePassword -eq "") {
		& $MageExePath -Sign $ManifestFilePath -CertFile $CertificateFilePath | Write-Verbose
	} else {
		& $MageExePath -Sign $ManifestFilePath -CertFile $CertificateFilePath -Password $CertificateFilePassword | Write-Verbose
	}
	CheckError "Failed to sign $ManifestFilePath"
	& $MageExePath -Update $ApplicationFilePath -AppManifest $ManifestFilePath | Write-Verbose
	CheckError "Failed to update $ApplicationFilePath"
	if ($CertificateFilePassword -eq "") {
		& $MageExePath -Sign $ApplicationFilePath -CertFile $CertificateFilePath | Write-Verbose
	} else {
		& $MageExePath -Sign $ApplicationFilePath -CertFile $CertificateFilePath -Password $CertificateFilePassword | Write-Verbose
	}
	CheckError "Failed to sign $ApplicationFilePath"
}

function SetClickOnceInformation {
	param
	(
		[string] $ApplicationFilePath,
		[string] $ProviderUrl = "",
		[string] $SupportUrl = "",
		[string] $Name = "",
		[string] $Publisher = "",
		[switch] $Verbose
	)
    if ($Verbose) {
        $VerbosePreference = 'Continue'
    }
	if ($ProviderUrl -ne "") {
		XmlPoke $ApplicationFilePath "//*[local-name() = 'deploymentProvider']/@codebase" $ProviderUrl -Verbose
	}
	if ($Name -ne "") {
		XmlPoke $ApplicationFilePath "//*[local-name() = 'assemblyIdentity']/@name" $Name -Verbose
		XmlPoke $ApplicationFilePath "//*[local-name() = 'description']/@*[namespace-uri()='urn:schemas-microsoft-com:asm.v2' and local-name() = 'product']" $Name -Verbose
	}
	if ($Publisher -ne "") {
		XmlPoke $ApplicationFilePath "//*[local-name() = 'description']/@*[namespace-uri()='urn:schemas-microsoft-com:asm.v2' and local-name() = 'publisher']" $Publisher -Verbose
	}
	if ($SupportUrl -ne "") {
		XmlPoke $ApplicationFilePath "//*[local-name() = 'description']/@*[namespace-uri()='urn:schemas-microsoft-com:asm.v2' and local-name() = 'supportUrl']" $SupportUrl -Verbose
	}
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
