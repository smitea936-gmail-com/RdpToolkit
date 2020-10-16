<#
	Part of module 'RdpToolkit'

	RdpToolkit is free software: you can redistribute it and/or modify
	it under the terms of the GNU Affero General Public License as published
	by the Free Software Foundation, either version 3 of the License, or
	(at your option) any later version.

	RdpToolkit is distributed in the hope that it will be useful,
	but WITHOUT ANY WARRANTY; without even the implied warranty of
	MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
	GNU Affero General Public License for more details.

	You should have received a copy of the GNU Affero General Public License
	along with RdpToolkit.  If not, see <https://www.gnu.org/licenses/>.
#>

Function New-RdcFile {
	[CmdletBinding(SupportsShouldProcess, ConfirmImpact='Medium')]
	[Alias('New-RdpFile')]
	Param(
		[Parameter(Mandatory, Position=0)]
		[Alias('File', 'RdcFile', 'RdpFile')]
		[ValidateNotNullOrEmpty()]
		[ValidatePattern('\.rdp$')]
		[IO.FileInfo] $Path,

		[Parameter(Mandatory, Position=1, ValueFromPipelineByPropertyName)]
		[Alias('DnsHostName', 'HostName', 'IPAddress', 'Name', 'RdSessionHostName', 'ServerName')]
		[ValidateNotNullOrEmpty()]
		[String] $ComputerName,

		[Alias('User')]
		[String] $UserName,

		[Alias('Domain')]
		[String] $DomainName,

		[Uri] $GatewayServerName,

		[Switch] $UseLoggedOnUserCredentials,

		[ValidateSet('AudioCapture', 'Cameras', 'Drives', 'PnPDevices', 'Printers', 'SerialPorts', 'SmartCards', 'UsbDevices')]
		[String[]] $Redirect = @('AudioCapture', 'Cameras', 'Drives', 'PnPDevices', 'Printers', 'SerialPorts', 'UsbDevices'),

		[Alias('Drives')]
		[ValidatePattern('(DynamicDrives|[A-Za-z]:?)')]
		[String[]] $DrivesToRedirect,

		[Switch] $SingleScreen,

		[Switch] $Force,

		[Switch] $Sign,

		[Switch] $PassThru
	)

	$RdpFileContents = [String[]]@(
		"full address:s:$ComputerName",
		'singlemoninwindowedmode:i:1'
	)
	Write-Debug -Message "Computer name = $ComputerName"
	Write-Debug -Message 'Single monitor in windowed mode = yes'
	
	If ($null -ne $UserName) {
		Write-Debug -Message "User name = $UserName"
		$RdpFileContents += "username:s:$UserName"
	}
	If ($null -ne $DomainName) {
		Write-Debug -Message "Domain name = $DomainName"
		$RdpFileContents += "domain:s:$DomainName"
	}
	If ($null -ne $GatewayServerName) {
		Write-Debug -Message "Gateway server name = $GatewayServerName"
		$RdpFileContents += "gatewayhostname:s:$GatewayServerName"

		Write-Debug -Message 'Gateway usage method = 1'
		$RdpFileContents += 'gatewayusagemethod:i:1'

		Write-Debug -Message 'Use same credentials for gateway and PC = yes'
		$RdpFileContents += 'promptcredentialonce:i:1'

		If ($UseLoggedOnUserCredentials) {
			Write-Debug -Message 'Gateway credentials = logged on user'
			$RdpFileContents += 'gatewaycredentialssource:i:2'
		} Else {
			Write-Debug -Message 'Gateway credentials = specify'
		}
	}

	Switch ($Redirect) {
		'AudioCapture' {
			Write-Debug -Message 'Redirected devices += microphones'
			$RdpFileContents += 'audiocapturemode:i:1'
		}
		'Cameras' {
			Write-Debug -Message 'Redirected devices += cameras (all)'
			$RdpFileContents += 'camerastoredirect:s:*'
		}
		'Drives' {
			If ($null -eq $DrivesToRedirect) {
				Write-Debug -Message 'Redirected devices += drives (all)'
				$RdpFileContents += 'drivestoredirect:s:*'
			} Else {
				Write-Debug -Message "Redirected devices += drives $($DrivesToRedirect -Join ', ')"
				$drives = [String[]]@()
				$DrivesToRedirect | ForEach-Object {
					If ($_.Length -eq 1) {
						$drives += "$($_.ToUpper()):"
					} Else {
						$drives += $_
					}
				}
				$RdpFileContents += "drivestoredirect:s:$($drives -Join ';')"
			}
		}
		'PnPDevices' {
			Write-Debug -Message 'Redirected devices += devices (all)'
			$RdpFileContents += 'devicestoredirect:s:*'
		}
		'Printers' {
			Write-Debug -Message 'Redirected devices += printers'
			$RdpFileContents += 'redirectprinters:i:1'
		}
		'SerialPorts' {
			Write-Debug -Message 'Redirected devices += COM: ports'
			$RdpFileContents += 'redirectcomports:i:1'
		}
		'SmartCards' {
			Write-Debug -Message 'Redirected devices += smart cards and Windows Hello for Business'
			$RdpFileContents += 'redirectsmartcards:i:1'
		}
		'UsbDevices' {
			Write-Debug -Message 'Redirected devices += USB devices (all)'
			$RdpFileContents += 'usbdevicestoredirect:s:*'
		}
		default {
			Write-Warning -Message "The redirection item $_ was not recognized and will be ignored."
		}
	}
	If ($RdpFileContents -NotContains 'redirectsmartcards:i:1') {
		$RdpFileContents += 'redirectsmartcards:i:0'
	}

	If ($SingleScreen) {
		Write-Debug -Message 'Multi-monitor support = off'
		$RdpFileContents += 'use multimon:i:0'
	} Else {
		Write-Debug -Message 'Multi-monitor support = on'
		$RdpFileContents += 'use multimon:i:1'
	}

	Write-Debug -Message 'Saving the .rdp file'
	$SetContentParameters = @{
		'Confirm' = $false
		'Encoding' = 'UTF8'
		'Path' = $Path
		'WhatIf' = $false
	}

	$FileExists = Test-Path -Path $Path -PathType Leaf
	If ($FileExists) {
		If ($Force -or $PSCmdlet.ShouldProcess($Path, 'Overwrite')) {
			$RdpFileContents | Sort-Object | Set-Content @SetContentParameters -Force
		}
	}
	Else {
		$RdpFileContents | Sort-Object | Set-Content @SetContentParameters
	}

	If ($Sign) {
		Write-Debug -Message 'Applying a digital signature to the .rdp file'
		Try {
			# Only pass through -WhatIf if the file already existed and the user
			# specified -WhatIf.  In all other cases, this is either a new file,
			# or the user did not specify -WhatIf.
			Add-RdcFileSignature -Files $Path -Confirm:$false -WhatIf:($WhatIfPreference -and $FileExists)
		}
		Catch {
			Write-Warning -Message 'The .rdp file could not be signed due to an error.'
		}
	}

	If ($PassThru) {
		Return (Get-File -Path $Path)
	}
}