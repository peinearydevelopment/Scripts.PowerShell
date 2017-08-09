<#
    This script is meant to pull down a git repository containing a website and setup that website in IIS with it's own application pool and web application.
    It will pull down the repository in the directory the power shell script is run in, compile the web project and place the published files into an artifacts folder which the website will point to.

    Example Usage:
        Run the following command from a power shell prompt running as Administrator
        .\dev-machine-setup.ps1 -password "Test!234" -reponame "BusinessComponents"

    Requried Parameters:
        -password
            DESCRIPTION: The password that should be used in setting up the Application Pool's identity.
        -reponame
            DESCRIPTION: The name of the git repository containing the website to setup

    Optional Parameters:
        -username
            DESCRIPTION: The username that should be used in setting up the Application Pool's identity
            DEFAULT: COMPUTERNAME\USERNAME
        -branch
            DESCRIPTION: The branch of the git repository to use
            DEFAULT: develop
        -cleanup
            DESCRIPTION: Should powershell remove all of the source files after the compiled artifacts have been created and the website is setup in IIS?
            DEFAULT: true
        -webprojectname
            DESCRIPTION: The name of the web project in the git repository that the created web application should point to
            DEFAULT: Apis
#>
param(
    [Parameter(Mandatory=$True)][string] $password,
    [Parameter(Mandatory=$True)][string] $reponame,

    [Parameter(Mandatory=$False)][string] $branch = "develop",
    [Parameter(Mandatory=$False)][boolean] $cleanup = $True,
    [Parameter(Mandatory=$False)][string] $username = "$($env:computername)\$($env:username)",
    [Parameter(Mandatory=$False)][string] $webprojectname = "Apis"
)

$artifactsdirectory = "artifacts"

## get repo
git clone $($reponame)

cd $($reponame)/
git checkout $branch

## publish project
dotnet restore
dotnet publish $($webprojectname)/$($webprojectname).csproj --configuration Release --output ../$($artifactsdirectory)

## setup app pool
Import-Module WebAdministration

If (Test-Path IIS:\AppPools\$($reponame)) {
    Remove-WebAppPool $reponame
}

New-Item IIS:\AppPools\$($reponame)

# .\dev-machine-setup.ps1 -password (ConvertTo-SecureString -String "Test!234" -Force -AsPlainText)"
# $creds = New-object System.Management.Automation.PSCredential $username, $password
# $creds.GetNetworkCredential().Password

Set-ItemProperty IIS:\AppPools\$($reponame) -name processModel -value @{ userName=$($username); password=$($password); identitytype=3 }
Set-ItemProperty IIS:\AppPools\$($reponame) managedRuntimeVersion "No Managed Code"

# setup web site
If (Test-Path IIS:\Sites\$($reponame)) {
    Remove-Item IIS:\Sites\$($reponame) -Recurse -Force
}

New-Item IIS:\Sites\$($reponame) -bindings @{protocol="http";bindingInformation=":80:$($reponame)"} -physicalPath "$(($pwd).path)\$($artifactsdirectory)"
Set-ItemProperty IIS:\Sites\$($reponame) -name applicationPool -value $reponame

# clean-up repo
Get-ChildItem |
    Foreach-Object {
        If ($_.Name -ne $artifactsdirectory) {
            Remove-Item -Recurse -Force $_.Name
        }
    }

Get-ChildItem -Attributes Hidden |
    Foreach-Object {
        If ($_.Name -ne $artifactsdirectory) {
            Remove-Item -Recurse -Force $_.Name
        }
    }

cd ..