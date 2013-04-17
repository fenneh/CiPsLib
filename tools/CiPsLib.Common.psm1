#--------------------------------------------------------------------------
# Function Library
# http://technet.microsoft.com/en-us/library/ee790599.aspx
#--------------------------------------------------------------------------

if (Get-Command "ServerManager" -errorAction SilentlyContinue) {
	Import-Module ServerManager
}

Import-Module WebAdministration

function EnsureWebFeaturesAreInstalled {
	param
	(
		[switch] $Verbose
	)
    if ($Verbose) {
        $VerbosePreference = 'Continue'
    }
	Write-Verbose "Adding web-server and net-framework Windows features"
	if (Get-Command "Add-WindowsFeature" -ErrorAction SilentlyContinue) {
		Add-WindowsFeature web-server,net-framework | Write-Host
	}
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

function Add-AppPool {
	param
	(
		[Parameter(Position=0, Mandatory=$true)] 
		[string]$appPoolName, 
		[Parameter(Position=1, Mandatory=$true)] 
		[string]$appPoolFrameworkVersion, 
		[Parameter(Position=2, Mandatory=$true)] 
		[string]$appPoolIdentity,
		[Parameter(Position=3, Mandatory=$false)] 
		[string]$appPoolIdentityPassword
	)
	
	write-host "Configuring app pool $appPoolName, with framework v$appPoolFrameworkVersion and user $appPoolIdentity"
	cd IIS:\
	$appPoolPath = ("IIS:\AppPools\" + $appPoolName)
	$pool = Get-Item $appPoolPath -ErrorAction SilentlyContinue
	
	if ($pool) {
		write-host "Deleting existing appPool: $appPoolPath"
		Remove-Item $appPoolPath -Force -Recurse
	}
	
	if (!(Test-Path $appPoolPath)) { 
		Write-Host "App pool $appPoolName does not exist. Creating..." 
		$newAppPool = New-Item $appPoolPath
		$newAppPool.processModel.idleTimeout = [TimeSpan] "0.00:00:00"
		$newAppPool.managedRuntimeVersion = $appPoolFrameworkVersion
	    $newAppPool.recycling.periodicRestart.time = [TimeSpan] "00:00:00"
				
		if ($appPoolIdentityPassword) {
			Write-Host "Setting up App Pool with specific user $appPoolIdentity"
			$newAppPool.processModel.userName = $appPoolIdentity
			$newAppPool.processModel.password = $appPoolIdentityPassword
			$newAppPool.processModel.identityType = "SpecificUser"
		} else {
			$newAppPool.processModel.identityType = $appPoolIdentity
		}
	
		$newAppPool | Set-Item  	
	} else {
		Write-Host "App pool $appPoolName already exists."
	}
	
	cd c:
}

function Add-Website {
	param
	(
		[Parameter(Position=0, Mandatory=$true)] 
		[string]$siteName, 
		[Parameter(Position=1, Mandatory=$true)] 
		[string]$appPoolName, 
		[Parameter(Position=2, Mandatory=$true)] 
		[string]$webRoot,
		[Parameter(Position=3, Mandatory=$true)] 
		[string]$hostHeader
	)
	
	# Delete exiting website
	$sitePath = ("IIS:\Sites\" + $siteName)
	$site = Get-Item $sitePath -ErrorAction SilentlyContinue 
	if ($site) { 
		Remove-WebSite -Name $siteName
	}
	
	Write-Host "Checking site $siteName..."
	$site = Get-Item $sitePath -ErrorAction SilentlyContinue
	
	if (!$site) { 
		Write-Host "Site $siteName does not exist, creating..." 
		$siteBindings = ":80:" + $hostHeader   
		$id = (dir iis:\sites | foreach {$_.id} | sort -Descending | select -first 1) + 1
		New-Item $sitePath -bindings @{protocol="http";bindingInformation=$siteBindings} -id $id -physicalPath $webRoot
		# Write-Host "Set bindings..."
		#Set-ItemProperty $sitePath -name bindings -value @{protocol="http";bindingInformation=$siteBindings}
		# Write-Host "Set app pool..."
		Set-ItemProperty $sitePath -Name applicationPool -Value $appPoolName
	} else {
		throw "Site '$sitePath' exists, but it should not!"
	}
}	

function Add-WebApplication {
	param
	(
		[Parameter(Position=0, Mandatory=$true)]
		[string]$siteName,
		[Parameter(Position=1, Mandatory=$true)]
		[string]$applicationName,
		[Parameter(Position=2, Mandatory=$true)]
		[string]$webRoot,
		[Parameter(Position=3, Mandatory=$true)]
		[string]$appPoolName
	)
	
	Write-Host "Checking application $siteName\$applicationName..."
	$sitePath = ("IIS:\Sites\" + $siteName + "\" + $applicationName)
	$site = Get-Item $sitePath -ErrorAction SilentlyContinue
	if (!$site) {
		Write-Host "Application $siteName\$applicationName does not exist, creating..." 
		New-WebApplication -Site $siteName -Name $applicationName -PhysicalPath $webRoot -ApplicationPool $appPoolName > $null
		Set-ItemProperty $sitePath -name applicationPool -value $appPoolName
	} else {
		Write-Host "Application exists. Complete"
	}
}

function CreateAndAddTestCertificate {
	param
	(
		[string]$certificateName
	)
	
	Invoke-Expression -command 'makecert -r -pe -n $certificateName -b 07/01/2008 -e 07/01/2099 -eku 1.3.6.1.5.5.7.3.1 -ss my -sr localMachine -sky exchange -sp "Microsoft RSA SChannel Cryptographic Provider" -sy 12'
}

# Get-ChildItem -Recurse cert:\ | more
function Add-SslBinding {
	param
	(
		[Parameter(Position=0, Mandatory=$true)]
		[string]$siteName,
		[Parameter(Position=1, Mandatory=$true)]
		[string]$sslThumbPrint,
		[Parameter(Position=2, Mandatory=$true)]
		[string]$hostheader,
		[Parameter(Position=3, Mandatory=$true)]
		[string]$certificateStore
	)
	
	cd IIS:
	$binding = Get-WebBinding -Name $siteName -Port 443
	
	if ($binding) {
		Write-Host "Binding exists - removing existing"
	    $binding | Remove-WebBinding
	}
	
	New-WebBinding -Name $siteName -IP "*" -Port 443 -Protocol https
	$cert = Get-Item "cert:\LocalMachine\$certificateStore\$sslThumbPrint"
	Write-Host "Certificate"
	Write-Host "$cert"
	cd IIS:\SslBindings
	Remove-Item .\0.0.0.0!443 -ErrorAction SilentlyContinue
	$cert | New-Item 0.0.0.0!443
	dir
	cd C:
}

#http://suhinini.blogspot.dk/2010/02/using-xmlpeek-and-xmlpoke-in-powershell.html	
function xmlPeek($filePath, $xpath) { 
    [xml] $fileXml = Get-Content $filePath 
    return $fileXml.SelectSingleNode($xpath).Value 
} 

function xmlPoke($file, $xpath, $value) { 
    [xml] $fileXml = Get-Content $file 
    $node = $fileXml.SelectSingleNode($xpath) 
    if ($node) 	{
		Write-Host "xmlPoke info: Changing '$xpath' to '$value'"
        $node.InnerText = $value 
        $fileXml.Save($file)  
    } else {
        throw "xmlPoke error: Not able to find $xpath and replace with $value"
	}
}

function XmlRemoveNode {
	param
	(
		[string] $XmlFilePath,
		[string] $XPath
	)
	[xml] $xml = Get-Content $XmlFilePath
	$xml.SelectNodes($XPath) | ForEach-Object {
		Write-Host "Removing node with path $XPath"
		$_.ParentNode.RemoveChild($_)
	}
	$xml.Save($XmlFilePath)
}

function Register-AspNetWithIis {
	param
	(
		[switch] $Verbose
	)
    if ($Verbose) {
        $VerbosePreference = 'Continue'
    }
	Write-Verbose "Register ASP.NET 4 with IIS"	
    & "$env:windir\Microsoft.NET\Framework\v4.0.30319\aspnet_regiis.exe" -i | Write-Host
	CheckError "Register ASP.NET 4 with IIS FAILED!"
}


function Register-ServiceModelWithIis {
	param
	(
		[switch] $Verbose
	)
    if ($Verbose) {
        $VerbosePreference = 'Continue'
    }
	Write-Verbose "Register WCF and WF components with IIS"
	& "$env:windir\Microsoft.NET\Framework\v4.0.30319\ServiceModelReg" -ia | Write-Host
	CheckError "Register WCF and WF components with IIS FAILED!"
}

function CheckSetVarDefault {
	param
	(
		[Parameter(Position=0, Mandatory=$true)]
		[string]$variableName,
		[Parameter(Position=1, Mandatory=$false)]
		[string]$defaultValue = ""
	)
	
	$variable = Get-Variable -Scope Global -Name $variableName -ErrorAction SilentlyContinue
	if ($variable -eq $null) {
		Set-Variable -Scope Global -Name $variableName -Value $defaultValue
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

Write-Host 'Imported CsPsLib.Common.PsLib.psm1'
