param (
    [Parameter(Mandatory=$false)] 
    [String]  $connectionName = 'AzureRunAsConnection',
    [Parameter(Mandatory=$false)] 
    [String] $ResourceGroupName = "xxx",
    [Parameter(Mandatory=$false)] 
    [String] $IsolateVirtualNetworkName = "xxx",
    [Parameter(Mandatory=$false)] 
    [String] $IsolateSubnetName = "xxx",
    [Parameter(Mandatory=$false)] 
    [String] $VMName = "xxxx",
    [Parameter(Mandatory=$false)] 
    [String] $ImageVMName = "xxxx"
)

$CurrentDate = (Get-Date -Format "yyyy/MM/dd") -replace '[\W]'
$SnapshotName = "snapshot-"+$VMName+"-"+$CurrentDate
$DiskName = "disk01-"+$VMName+"-"+$CurrentDate
$NetworkInterfaceCardName = "nic01-"+$VMName+"-"+$CurrentDate

try
{
    # Get the connection "AzureRunAsConnection "

    $servicePrincipalConnection = Get-AutomationConnection -Name $connectionName

    "Logging in to Azure..."
    $connectionResult =  Connect-AzAccount -Tenant $servicePrincipalConnection.TenantID `
    -ApplicationId $servicePrincipalConnection.ApplicationID   `
    -CertificateThumbprint $servicePrincipalConnection.CertificateThumbprint `
    -ServicePrincipal
    "Logged in."
}
catch {
    if (!$servicePrincipalConnection)
    {
        $ErrorMessage = "Connection $connectionName not found."
        throw $ErrorMessage
    } else{
        Write-Error -Message $_.Exception
        throw $_.Exception
    }
}

try {
    $VMInformation = Get-AzVM -ResourceGroupName $ResourceGroupName -Name $VMName -Status

    $status = (($VMInformation.Statuses[1].Code).Split("/"))[1]
    
    if ($status -eq "running") {
        Write-Host "$VMName is running."
    }
    elseif ($status -eq "deallocated"){
        Write-Host "$VMName is deallocated."
    }
    elseif ($status -eq "stopped") {
        Write-Host "$VMName is stopped."
        $SnapshotConfig = New-AzSnapshotConfig `
        -SourceUri $VMInformation.StorageProfile.OsDisk.ManagedDisk.Id `
        -Location "eastasia" `
        -CreateOption copy
    
        $Snapshot = New-AzSnapshot `
        -Snapshot $SnapshotConfig `
        -SnapshotName $SnapshotName `
        -ResourceGroupName $ResourceGroupName
    
        $OSDisk = New-AzDisk `
        -DiskName $DiskName `
        (New-AzDiskConfig  -Location "eastasia" -CreateOption Copy -SourceResourceId $Snapshot.Id -SkuName "StandardSSD_LRS") `
        -ResourceGroupName $ResourceGroupName
    
        $ImageSubnetID = (Get-AzVirtualNetworkSubnetConfig -Name $IsolateSubnetName -VirtualNetwork (Get-AzVirtualNetwork -Name $IsolateVirtualNetworkName -ResourceGroupName $ResourceGroupName)).Id
    
        $NetworkInterfaceCardName = New-AzNetworkInterface -Name $NetworkInterfaceCardName `
        -ResourceGroupName $ResourceGroupName `
        -Location "eastasia" `
        -SubnetId $ImageSubnetID
    
        $ImageVMConfig = New-AzVMConfig -VMName $ImageVMName -VMSize "Standard_D2s_v3"
    
        $ImageVM = Add-AzVMNetworkInterface -VM $ImageVMConfig -Id $NetworkInterfaceCardName.Id
    
        $ImageVM = Set-AzVMOSDisk -VM $ImageVM `
        -ManagedDiskId $OSDisk.Id `
        -CreateOption Attach -Windows
    
        $ImageVM | Set-AzVMBootDiagnostic -Disable
    
        $ImageVMStatus = New-AzVM -ResourceGroupName $ResourceGroupName -Location "eastasia" -VM $ImageVM   
    
        if ($ImageVMStatus.StatusCode -eq "OK") {
            Write-Host "The $ImageVMName has created"
        }
        else {
            Write-Host "The $ImageVMName cannot success to create "
        }
    }
    else {
        Write-Host "$VMName is $status - Please stop the $VMName and run it again"
    } 
}
catch {
    $errMsg = $_.Exception.ErrorMessage
    Write-Error ("This Process was failed. Please also check and clean unuse resources")
    Write-Error $errMsg -ErrorAction Stop
    Break
}


