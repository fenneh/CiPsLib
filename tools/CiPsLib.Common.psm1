
function IsModuleAvailable {
	param
	(
		[string] $Name
	)
	return Get-Module -ListAvailable | Where-Object { $_.name -eq $Name }
}


function Set-FullControlDirectoryFilePermission {
	param
	(
		[string] $Path,
		[string] $Usermname,
		[switch] $Verbose
	)
    if ($Verbose) {
        $VerbosePreference = 'Continue'
    }
	Write-Verbose "Setting FullControll for user $Usermname to path: $Path"
	$acl = Get-Acl $Path
	$permission = $Usermname,"FullControl","Allow"
	$accessRule = New-Object System.Security.AccessControl.FileSystemAccessRule($Usermname,"FullControl", "ContainerInherit, ObjectInherit", "None", "Allow")
	$acl.AddAccessRule($accessRule)
	Set-Acl $Path $acl
	Get-Acl $Path | Format-List | Write-Verbose
}


function CreateAndAddTestCertificate {
	param
	(
		[string]$certificateName
	)
	
	Invoke-Expression -command 'makecert -r -pe -n $certificateName -b 07/01/2008 -e 07/01/2099 -eku 1.3.6.1.5.5.7.3.1 -ss my -sr localMachine -sky exchange -sp "Microsoft RSA SChannel Cryptographic Provider" -sy 12'
}


function SetFilePermission {
	param
	(
		[string] $FilePath,
		[string] $Permission,
		[string] $Username,
		[switch] $Verbose
	)
    if ($Verbose) {
        $VerbosePreference = 'Continue'
    }
	Write-Verbose "SetFilePermission: Setting '$Permission' permission for $username on $FilePath"
	$Acl = Get-Acl $FilePath
	Write-Verbose Permissions before:
	$Acl| Format-List | Write-Verbose
	$Ar = New-Object  system.security.accesscontrol.filesystemaccessrule($Username,$Permission,"Allow")
	$Acl.SetAccessRule($Ar)
	Set-Acl $fullPath $Acl
	Write-Verbose 'Permissions after:'
	$Acl| Format-List | Write-Verbose
}


function XmlPeek {
	param
	(
		[string] $FilePath,
		[string] $XPath
	)
    [xml] $xml = Get-Content $FilePath -Encoding UTF8
    return $xml.SelectSingleNode($XPath).Value 
} 


function XmlPoke {
	param
	(
		[string] $FilePath,
		[string] $XPath,
		[string] $Value,
		[switch] $Verbose
	)
    if ($Verbose) {
        $VerbosePreference = 'Continue'
    }
    [xml] $xml = Get-Content $FilePath -Encoding UTF8
	$FoundNode = $false
    $xml.SelectNodes($XPath) | ForEach-Object {
		Write-Verbose "XmlPoke: Changing '$XPath' to '$Value'"
        $_.InnerText = $Value
		$FoundNode = $true
	}
	if ($FoundNode -eq $true) {
    	$xml.Save($FilePath)
	} else {
		throw "XmlPoke ERROR: Failed to find any nodes with XPath '$XPath'"
	}
}


function XmlRemoveNode {
	param
	(
		[string] $XmlFilePath,
		[string] $XPath,
		[switch] $Verbose
	)
    if ($Verbose) {
        $VerbosePreference = 'Continue'
    }
	[xml] $xml = Get-Content $XmlFilePath -Encoding UTF8
	$xml.SelectNodes($XPath) | ForEach-Object {
		Write-Verbose "Removing node with path $XPath"
		$_.ParentNode.RemoveChild($_)
	}
	$xml.Save($XmlFilePath)
}


function Get-AssemblyVersion {
    param
	(
		$file
	)
	
    return [System.Diagnostics.FileVersionInfo]::GetVersionInfo($file).FileVersion
}


function Update-AssemblyVersion {
	param
	(
		[string] $FilePath,
		[string] $Version,
		[switch] $Verbose
	)
    if ($Verbose) {
        $VerbosePreference = 'Continue'
    }
	$assemblyVersionPattern = 'AssemblyVersion\("[0-9]+(\.([0-9]+|\*)){1,3}"\)'
    $fileVersionPattern = 'AssemblyFileVersion\("[0-9]+(\.([0-9]+|\*)){1,3}"\)'
    $assemblyVersion = 'AssemblyVersion("' + $Version + '")';
    $fileVersion = 'AssemblyFileVersion("' + $Version + '")';
	Write-Verbose "Updating assembly version to '$Version' in file '$FilePath'"
	(Get-Content $FilePath -Encoding UTF8) `
		-replace $assemblyVersionPattern, $assemblyVersion `
		-replace $fileVersionPattern,  $fileVersion `
		| Set-Content $FilePath
}


function Update-AllAssemblyVersion {
	param
	(
		[string] $RootPath,
		[string] $Version,
		[switch] $Verbose
	)
    if ($Verbose) {
        $VerbosePreference = 'Continue'
    }
	Write-Verbose "Update ALL AssemblyInfo.cs files found in '$RootPath'!"
	Get-ChildItem -Path $RootPath -Filter AssemblyInfo.cs -Recurse | ForEach-Object {
		Update-AssemblyVersion -FilePath $_.FullName -Version $version -Verbose
	}
}


function Call {
	param
	(
		[scriptblock] $Command,
		[string] $ThrowMessage,
		[switch] $Verbose
	)
    if ($Verbose) {
        $VerbosePreference = 'Continue'
    }
	& $Command | Write-Verbose
	if ($lastExitCode -ne 0) {
        throw "$ThrowMessage"
    }
}


function CheckSetVarDefault {
	param
	(
		[string] $Name,
		[string] $Default = "",
		[switch] $Verbose
	)
    if ($Verbose) {
        $VerbosePreference = 'Continue'
    }
	$variable = Get-Variable -Scope Global -Name $Name -ErrorAction SilentlyContinue
	if ($variable -eq $null) {
		Write-Verbose "CheckSetVarDefault: Variable '$Name' not set, setting to '$Default'"
		Set-Variable -Scope Global -Name $Name -Value $Default
	}
}


function CreateTempDir {
	param
	(
		[switch] $Verbose
	)
    if ($Verbose) {
        $VerbosePreference = 'Continue'
    }
	$tmpDir = [System.IO.Path]::GetTempPath()
	$tmpDir = [System.IO.Path]::Combine($tmpDir, [System.IO.Path]::GetRandomFileName())
	Write-Verbose "Creating temp directory at '$tmpDir'"
	[System.IO.Directory]::CreateDirectory($tmpDir) | Out-Null
	$tmpDir
}


function CheckError {
	param (
		[Parameter(Position=0, Mandatory=$true)]
		[string]$message
	)
	if ($lastExitCode -ne 0) {
        throw "$message"
    }
}

Export-ModuleMember -function * -alias *

Write-Host 'Imported CsPsLib.Common.psm1'
