if (Get-Command "ServerManager" -ErrorAction SilentlyContinue) {
	Import-Module ServerManager
}

if (Get-Command "WebAdministration" -ErrorAction SilentlyContinue) {
	# http://technet.microsoft.com/en-us/library/ee790599.aspx
	Import-Module WebAdministration
}

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

function Add-Iis6MetaDataCompatibilityFeature {
	param
	(
		[switch] $Verbose
	)
    if ($Verbose) {
        $VerbosePreference = 'Continue'
    }
	Write-Verbose "Adding IIS 6 Meta Data Compatability feature"
	if (Get-Command "Add-WindowsFeature" -ErrorAction SilentlyContinue) {
		Add-WindowsFeature Web-Metabase
	}
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
    & "$env:windir\Microsoft.NET\Framework\v4.0.30319\aspnet_regiis.exe" -i | Write-Verbose
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
	Write-Verbose "Register-ServiceModelWithIis: Register WCF and WF components with IIS"
	& "$env:windir\Microsoft.NET\Framework\v4.0.30319\ServiceModelReg" -ia | Write-Verbose
	CheckError "Register WCF and WF components with IIS FAILED!"
}

function Add-WebApplication {
	param
	(
		[string] $SiteName,
		[string] $ApplicationName,
		[string] $WebRoot,
		[string] $AppPoolName,
		[switch] $Verbose
	)
    if ($Verbose) {
        $VerbosePreference = 'Continue'
    }
	Write-Verbose "Add-WebApplication: Checking application $SiteName\$ApplicationName"
	$sitePath = ("IIS:\Sites\" + $SiteName + "\" + $ApplicationName)
	$site = Get-Item $sitePath -ErrorAction SilentlyContinue
	if (!$site) {
		Write-Verbose "Add-WebApplication: Application $SiteName\$ApplicationName does not exist, creating" 
		New-WebApplication -Site $SiteName -Name $ApplicationName -PhysicalPath $WebRoot -ApplicationPool $AppPoolName > $null
		Set-ItemProperty $sitePath -name applicationPool -value $appPoolName
	} else {
		# TODO, delete first then recreate instead
		Write-Warning "Add-WebApplication: Application exists, nothing to do"
	}
}

function Add-AppPool {
	param
	(
		[string] $Name, 
		[string] $FrameworkVersion, 
		[string] $Identity,
		[string] $IdentityPassword = "",
		[switch] $Verbose
	)
    if ($Verbose) {
        $VerbosePreference = 'Continue'
    }
	
	Write-Verbose "Add-AppPool: Configuring app pool $Name, with framework v$FrameworkVersion and user $Identity"
	cd IIS:\
	$appPoolPath = ("IIS:\AppPools\" + $Name)
	$pool = Get-Item $appPoolPath -ErrorAction SilentlyContinue
	
	if ($pool) {
		Write-Verbose "Add-AppPool: Deleting existing appPool: $appPoolPath"
		Remove-Item $appPoolPath -Force -Recurse
	}
	
	if (!(Test-Path $appPoolPath)) { 
		Write-Verbose "App pool $Name does not exist. Creating..." 
		$newAppPool = New-Item $appPoolPath
		$newAppPool.processModel.idleTimeout = [TimeSpan] "0.00:00:00"
		$newAppPool.managedRuntimeVersion = $FrameworkVersion
	    $newAppPool.recycling.periodicRestart.time = [TimeSpan] "00:00:00"
				
		if ($IdentityPassword -ne "") {
			Write-Verbose "Add-AppPool: Setting up App Pool with specific user $Identity"
			$newAppPool.processModel.userName = $Identity
			$newAppPool.processModel.password = $IdentityPassword
			$newAppPool.processModel.identityType = "SpecificUser"
		} else {
			$newAppPool.processModel.identityType = $Identity
		}
	
		$newAppPool | Set-Item  	
	} else {
		throw "Add-AppPool: App pool '$appPoolPath' still exist, but it should not!"
	}
	
	cd c:
}

function Add-Website {
	param
	(
		[string] $SiteName, 
		[string] $AppPoolName, 
		[string] $WebRoot,
		[string] $HostHeader,
		[switch] $Verbose
	)
    if ($Verbose) {
        $VerbosePreference = 'Continue'
    }
	
	# Delete exiting website
	$sitePath = ("IIS:\Sites\" + $SiteName)
	$site = Get-Item $sitePath -ErrorAction SilentlyContinue 
	if ($site) {
		Write-Verbose "Add-Website: Site with name '$SiteName' already exist, REMOVING it!"
		Remove-WebSite -Name $SiteName
	}
	
	Write-Verbose "Add-Website: Checking site $SiteName again"
	$site = Get-Item $SiteName -ErrorAction SilentlyContinue
	
	if (!$site) { 
		Write-Verbose "Add-Website: Site $SiteName does not exist, creating..." 
		$siteBindings = ":80:" + $HostHeader   
		$id = (dir iis:\sites | foreach {$_.id} | sort -Descending | select -first 1) + 1
		New-Item $sitePath -Bindings @{protocol="http";bindingInformation=$siteBindings} -id $id -PhysicalPath $WebRoot
		# Write-Host "Set bindings..."
		#Set-ItemProperty $sitePath -name bindings -value @{protocol="http";bindingInformation=$siteBindings}
		# Write-Host "Set app pool..."
		Set-ItemProperty $sitePath -Name applicationPool -Value $AppPoolName
	} else {
		throw "Add-Website: Site '$sitePath' still exists, but it should not!"
	}
}	

# Get-ChildItem -Recurse cert:\ | more
function Add-SslBinding {
	param
	(
		[string] $SiteName,
		[string] $SslThumbPrint,
		[string] $Hostheader,
		[string] $CertificateStore,
		[switch] $Verbose
	)
    if ($Verbose) {
        $VerbosePreference = 'Continue'
    }
	
	cd IIS:
	$binding = Get-WebBinding -Name $SiteName -Port 443
	
	if ($binding) {
		Write-Verbose "Add-SslBinding: Binding exists - removing existing"
	    $binding | Remove-WebBinding
	}
	
	New-WebBinding -Name $siteName -IP "*" -Port 443 -Protocol https
	$cert = Get-Item "cert:\LocalMachine\$CertificateStore\$SslThumbPrint"
	Write-Verbose "Certificate"
	Write-Verbose "$cert"
	cd IIS:\SslBindings
	$sslBinding = Get-Item .\0.0.0.0!443 -ErrorAction SilentlyContinue
	if ($sslBinding) {
		Write-Verbose "Add-SslBinding: Removing esisting SSL binding"
		Remove-Item .\0.0.0.0!443
	}
	$cert | New-Item 0.0.0.0!443
	dir
	cd C:
}

Export-ModuleMember -function * -alias *

Write-Host 'Imported CsPsLib.IIS.psm1'
