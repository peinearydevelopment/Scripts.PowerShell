[CmdletBinding()]
Param(
    [string]$SolutionDirectory = "..",
    [string]$SolutionName,
    [ValidateSet("Release", "Debug")]
    [string]$Configuration = "Release",
    #Nuget Verbosities: quiet, normal, detailed
    #MSBuild Verbosities: q[uiet], m[inimal], n[ormal], d[etailed], diag[nostic]
    [ValidateSet("Quiet", "Minimal", "Normal", "Detailed", "Diagnostic")]
    [string]$Verbosity = "Minimal"
    # [Alias("DryRun","Noop")]
    # [switch]$WhatIf,
)

# $INDENT = 0
$MSBUILD_RootDirectory = ${env:ProgramFiles(x86)} + "\MSBuild\14.0\Bin"
$MSBUILD_DLL = "$MSBUILD_RootDirectory\Microsoft.Build.dll"
$MSBUILD_EXE = "$MSBUILD_RootDirectory\MSBuild.exe"
$MSBUILD_Verbosity = $Verbosity

$NUGET_EXE = ${env:ProgramData} + "\chocolatey\bin\NuGet.exe"
$NUGET_LocalSource = "{SOURCE_NAME}"
$NUGET_LocalSourcePath = "{SOURCE_PATH}"
$NUGET_LocalSymbolsSource = "{SYMBOLS_SOURCE_NAME}"
$NUGET_LocalSymbolsSourcePath = "{SOURCE_PATH}"
$NUGET_Verbosity = $Verbosity
Switch ($Verbosity)
{
    "Minimal" { $NUGET_Verbosity = "Normal"; break }
    "Diagnostic" { $NUGET_Verbosity = "Detailed"; break }
}

$BuildRootDirectory = Resolve-Path -Path "..\bin"
$BuildDirectory = "$BuildRootDirectory\$Configuration"

$SolutionDirectory = Resolve-Path -Path ".."
Add-Type -Path ($MSBUILD_DLL)
$SolutionObject = [Microsoft.Build.Construction.SolutionFile] "$SolutionDirectory\$SolutionName.sln"
#http://stackoverflow.com/questions/3802027/how-do-i-programmatically-list-all-projects-in-a-solution#answer-41009889
$Projects = ($SolutionObject.ProjectsInOrder | Where-Object {$_.ProjectType -eq 'KnownToBeMSBuildFormat'})

Function Clean([string]$Directory) {
    Write-Host "CLEANING" -ForegroundColor "Green"
    # $INDENT = $INDENT + 1

    If(Test-Path $Directory) {
        Write-Host "    $Directory"
        Remove-Item "$Directory\*" -Recurse 
    } Else {
        Write-Host "    Nothing to clean at: $Directory"
    }

    # $INDENT = $INDENT - 1
}

Function NuGetRestore() {
    Write-Host "NUGET RESTORE" -ForegroundColor "Green"

    Clean -Directory "$SolutionDirectory\packages"

    $Command = "&`"$NUGET_EXE`" restore `"$SolutionDirectory\$SolutionName.sln`" -Verbosity $NUGET_Verbosity"
    Write-Host "    $Command"
    Invoke-Expression $Command
    # $Output = Invoke-Expression $Command
    # $Output.Split("\n") | ForEach-Object { Write-Host "    $_" }
    # Write-Host "$Output"
}

Function BuildSolution() {
    Write-Host "MSBUILD" -ForegroundColor "Green"

    Clean -Directory "$SolutionDirectory\bin"
    Clean -Directory "$SolutionDirectory\obj"

    $Command = "&`"$MSBUILD_EXE`" `"$SolutionDirectory\$SolutionName.sln`" /maxcpucount /verbosity:$MSBUILD_Verbosity /property:Configuration=$Configuration"
    Write-Host "    $Command"
    Invoke-Expression $Command
}

Function GetNextPackageVersion([string]$ProjectName)
{
    Write-Host "GETTING NEXT NUGET PACKAGE VERSION" -ForegroundColor "Green"
    $Command = "&`"$NUGET_EXE`" list `"$ProjectName`" -Verbosity $NUGET_Verbosity -Source `"$NUGET_LocalSource`""
    Write-Host "    $Command"
    $NuGetSearchMatches = Invoke-Expression $Command
    ForEach($Match In $NuGetSearchMatches) {
        $MatchParts = $Match.Split(" ")
        If ($MatchParts[0].Equals($ProjectName)) {
            $PackageLatestVersionParts = $MatchParts[1].Split(".")
            $NextPatchNumber = 1 + [convert]::ToInt32($PackageLatestVersionParts[2], 10)
            Return "$($PackageLatestVersionParts[0]).$($PackageLatestVersionParts[1]).$NextPatchNumber"
        }
    }

    Return "1.0.0"
}

Function NuGetPackage() {
    Write-Host "NUGET PACKAGE" -ForegroundColor "Green"

    Clean -Directory "$SolutionDirectory\nuget"

    ForEach ($Project In $Projects) {
        $Version = GetNextPackageVersion -ProjectName $Project.ProjectName
        $ProjectPath = $Project.AbsolutePath
        $Command = "&`"$NUGET_EXE`" pack `"$ProjectPath`" -Verbosity $NUGET_Verbosity -IncludeReferencedProjects -OutputDirectory `"$SolutionDirectory\nuget`" -Symbols -Version $Version -Properties Configuration=$Configuration"
        Write-Host "    $Command"
        Invoke-Expression $Command
    }
}

Function NuGetPublish() {
    Write-Host "NUGET PUBLISH" -ForegroundColor "Green"

    $NuGetPackages = Get-ChildItem "$SolutionDirectory\nuget"
    ForEach ($NuGetPackage In $NuGetPackages) {
        $NuGetPackageName = $NuGetPackage.Name

        If ($NuGetPackage.Name.EndsWith(".symbols.nupkg")) {
            $Command = "&`"$NUGET_EXE`" add $SolutionDirectory\nuget\$NuGetPackageName -Source `"$NUGET_LocalSymbolsSourcePath`""
        } Else {
            $Command = "&`"$NUGET_EXE`" add $SolutionDirectory\nuget\$NuGetPackageName -Source `"$NUGET_LocalSourcePath`""
        }

        Write-Host "    $Command"
        Invoke-Expression $Command
    }
}

Clean -Directory $BuildDirectory
NuGetRestore
BuildSolution
NuGetPackage
NuGetPublish