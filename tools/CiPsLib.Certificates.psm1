$MyDir = Split-Path $MyInvocation.MyCommand.Definition
Import-Module $MyDir"\CiPsLib.Common.psm1" -Force

# http://poshcode.org/1937
# Examples:
#  Import-Certificate -CertFile “VeriSign_Expires-2028.08.01.cer” -StoreNames AuthRoot, Root -LocalMachine
#  Import-Certificate -CertFile “VeriSign_Expires-2018.05.18.p12” -StoreNames AuthRoot -LocalMachine -CurrentUser -CertPassword Password -Verbose
#  dir -Path C:\Certs -Filter *.cer | Import-Certificate -CertFile $_ -StoreNames AuthRoot, Root -LocalMachine -Verbose
# Store paths:
#  AddressBook: The X.509 certificate store for other users.
#  AuthRoot: The X.509 certificate store for third-party certificate authorities (CAs).
#  CertificateAuthority: The X.509 certificate store for intermediate certificate authorities (CAs).
#  Disallowed: The X.509 certificate store for revoked certificates.
#  My: The X.509 certificate store for personal certificates.
#  Root: The X.509 certificate store for trusted root certificate authorities (CAs).
#  TrustedPeople: The X.509 certificate store for directly trusted people and resources.
#  TrustedPublisher: The X.509 certificate store for directly trusted publishers.
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


Export-ModuleMember -function * -alias *

Write-Host 'Imported CsPsLib.Certificates.psm1'
