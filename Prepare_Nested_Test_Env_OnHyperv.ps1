
<#
Usage example:

$networkTestHosts = "host1,host2"
$vmNamesToBeRemoved = "client-vm,server-vm"

.\Prepare_Nested_Test_Env_OnHyperv.ps1  -serviceHosts $networkTestHosts   `
										-vmNamesToBeRemoved $vmNamesToBeRemoved   `
										-srcPath "\\***\share\TestFile.txt"      `
										-dstPath "d:\\vhd\\TestFile_LOCAL.txt"         `
										-user '*****'  -password '*******'   -enable_Network
#>


param(
	[string]$serviceHosts, 
	[string]$vmNamesToBeRemoved, 
	[string]$srcPath="", 
	[string]$dstPath="", 
	$user, 
	$password, 
	[switch]$enable_Network
)


Function Get-Cred($user, $password)
{
	$secstr = New-Object -TypeName System.Security.SecureString
	$password.ToCharArray() | ForEach-Object {$secstr.AppendChar($_)}
	$cred = new-object -typename System.Management.Automation.PSCredential -argumentlist $user, $secstr
	Set-Item WSMan:\localhost\Client\TrustedHosts * -Force
	return $cred
}


Function RemoveVM ($computerName, $vmName) {
	Write-Output "Delete the $vmName on $computerName if it exits."
	# Get-VM  -ComputerName $computerName | Where-Object {$_.Name -eq $vmName} | Stop-VM -ComputerName  $computerName -Force | Remove-VM -ComputerName $computerName -Force
	$vm = Get-VM  -ComputerName $computerName | Where-Object {$_.Name -eq $vmName}
	if($vm) {
		Stop-VM -ComputerName  $computerName   -Name $vmName   -Force
		Start-Sleep 3
		Remove-VM -ComputerName $computerName  -Name $vmName   -Force 
		Start-Sleep 3
		Write-Output "Delete the $vmName on $computerName done."
	}
}

Function Get-OSvhd ([string]$computerName, [string]$srcPath, [string]$dstPath, $session) {
	Write-Output "Copy $srcPath to $dstPath on $computerName ..."
	Invoke-Command  -session $session -ScriptBlock {
		param($dstPath)
		$target = ( [io.fileinfo] $dstPath ).DirectoryName
		if( -not (Test-Path $target) ) {
			Write-Output "Create the directory: $target"
			New-Item -Path $target -ItemType "directory" -Force
		}
	} -ArgumentList $dstPath
	
	if( $srcPath.Trim().StartsWith("http") ){
		Invoke-Command  -session $session -ScriptBlock {
			param($srcPath, $dstPath)

			Import-Module BitsTransfer
			$displayName = "MyBitsTransfer" + (Get-Date)
			Start-BitsTransfer `
				-Source $srcPath `
				-Destination $dstPath `
				-DisplayName $displayName `
				-Asynchronous
			$btjob = Get-BitsTransfer $displayName
			$lastStatus = $btjob.JobState
			do{
				if($lastStatus -ne $btjob.JobState) {
					$lastStatus = $btjob.JobState
				}

				if($lastStatus -like "*Error*") {
					Remove-BitsTransfer $btjob
					Write-Output "Error connecting $srcPath to download."
					return 1
				}
			} while ($lastStatus -ne "Transferring")

			do{
				Write-Output (Get-Date) $btjob.BytesTransferred $btjob.BytesTotal ($btjob.BytesTransferred/$btjob.BytesTotal*100)
				Start-Sleep -s 10
			} while ($btjob.BytesTransferred -lt $btjob.BytesTotal)

			Write-Output (Get-Date) $btjob.BytesTransferred $btjob.BytesTotal ($btjob.BytesTransferred/$btjob.BytesTotal*100)
			Complete-BitsTransfer $btjob
		}  -ArgumentList $srcPath, $dstPath
	}
	else {
		Copy-Item $srcPath -Destination $dstPath -ToSession $session
	}

	Write-Output "Copy $srcPath to $dstPath on $computerName Done."
}


function Main()
{
	# Delete the exited VMs for network test
	if($enable_Network) {
		foreach ( $serviceHost in $serviceHosts.Split(",").Trim() ) {
			foreach ( $vmName in $vmNamesToBeRemoved.Split(",").Trim() ) {
				RemoveVM -computerName $serviceHost -vmName $vmName
			}
		}
	}

	# Copy/download the vhd from share path or azure blob
	$cred = Get-Cred -user $user -password $password
	if($srcPath -and $dstPath) {
		foreach ( $serviceHost in $serviceHosts.Split(",").Trim() ) {
			$session = New-PsSession  -ComputerName  $serviceHost -Credential $cred
			Get-OSvhd -computerName $serviceHost -srcPath $srcPath -dstPath $dstPath -session $session
		}
	}
}


Main
