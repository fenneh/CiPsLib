
function IsModuleAvailable {
	param
	(
		[string] $Name
	)
	return Get-Module -ListAvailable | Where-Object { $_.name -eq $Name }
}

# http://poshcode.org/1937
# Examples:
#  Import-Certificate -CertFile “VeriSign_Expires-2028.08.01.cer” -StoreNames AuthRoot, Root -LocalMachine
#  Import-Certificate -CertFile “VeriSign_Expires-2018.05.18.p12” -StoreNames AuthRoot -LocalMachine -CurrentUser -CertPassword Password -Verbose
#  dir -Path C:\Certs -Filter *.cer | Import-Certificate -CertFile $_ -StoreNames AuthRoot, Root -LocalMachine -Verbose
function Import-Certificate
{
	param
	(
		[IO.FileInfo] $CertFile = $(throw "Paramerter -CertFile [System.IO.FileInfo] is required."),
		[string[]] $StoreNames = $(throw "Paramerter -StoreNames [System.String] is required."),
		[switch] $LocalMachine,
		[switch] $CurrentUser,
		[string] $CertPassword,
		[switch] $Verbose
	)
	
	begin
	{
		[void][System.Reflection.Assembly]::LoadWithPartialName("System.Security")
	}
	
	process 
	{
        if ($Verbose) {
            $VerbosePreference = 'Continue'
        }
		if (-not $LocalMachine -and -not $CurrentUser) {
			Write-Warning "One or both of the following parameters are required: '-LocalMachine' '-CurrentUser'. Skipping certificate '$CertFile'."
		}
		$StoreScopes = New-Object 'System.Collections.Generic.List[string]'
		if ($LocalMachine) {
			$StoreScopes.Add('LocalMachine')
		}
		if ($CurrentUser) {
			$StoreScopes.Add('CurrentUser')
		}
		if ($_) {
            $certfile = $_
        }
        $cert = New-Object System.Security.Cryptography.X509Certificates.X509Certificate2
		$cert.Import($certfile,$CertPassword,"Exportable,PersistKeySet")
		$thumbPrint = $cert.Thumbprint
		$subject = $cert.Subject
		Write-Verbose "Loaded certificate '$subject' [$thumbPrint]"
		$StoreScopes | ForEach-Object {
			$StoreScope = $_
			$StoreNames | ForEach-Object {
				$StoreName = $_
				if (Test-Path "cert:\$StoreScope\$StoreName") {
					try {
						$store = New-Object System.Security.Cryptography.X509Certificates.X509Store $StoreName, $StoreScope
						$store.Open([System.Security.Cryptography.X509Certificates.OpenFlags]::MaxAllowed)
						
						# Remove old certificate
						$certificates = $store.Certificates
						$certificates | ForEach-Object {
								if ($_.Thumbprint -eq $cert.Thumbprint) {
								# We remove in case we have changed how we import certificates and to test we can import them correctly
								Write-Verbose "Found existing certificate thumbprint '$thumbPrint' in 'cert:\$StoreScope\$StoreName', removing it"
								$store.Remove($_)
							}
						}
						
						$store.Add($cert)
						$store.Close()
						Write-Verbose "Successfully added '$certfile' to 'cert:\$StoreScope\$StoreName'."
					} catch {
						Write-Error ("Error adding '$certfile' to 'cert:\$StoreScope\$StoreName': $_ .") -ErrorAction:Continue
					}
				} else {
					Write-Warning "Certificate store '$StoreName' does not exist. Skipping..."
				}
			}
		}
	}
	end
	{ }
}

function Grant-CertificateReadPermission {
	param
	(
		[string] $ThumbPrint,
		[string] $Username,
		[switch] $Verbose
	)
    if ($Verbose) {
        $VerbosePreference = 'Continue'
    }
	Write-Verbose "Granting certificate '$ThumbPrint' read permission to '$Username'"
	$certificateKeyRoot = "C:\ProgramData\Microsoft\Crypto\RSA\MachineKeys"
	$cert = Get-Item "cert:\LocalMachine\My\$ThumbPrint"
	Write-Verbose "Certificate"
	Write-Verbose $cert
	$certUniqueKeyContainerName = $cert.PrivateKey.CspKeyContainerInfo.UniqueKeyContainerName
	$certificateKeyPath = "$certificateKeyRoot"+"\"+$certUniqueKeyContainerName
	Write-Verbose "Certificate key path: $certificateKeyPath"
	SetFilePermission $certificateKeyPath "Read" $Username
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
    [xml] $xml = Get-Content $FilePath 
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
    [xml] $xml = Get-Content $FilePath
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
	[xml] $xml = Get-Content $XmlFilePath
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

function Call {
	param
	(
		[scriptblock] $Command,
		[string] $Message
	)
	& $Command
	if ($lastExitCode -ne 0) {
        throw "$message"
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
