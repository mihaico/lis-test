param([String] $vmName, [String] $hvServer, [String] $testParams)

Add-Type -AssemblyName System.IO.Compression.FileSystem

if (-not $testParams)
{
    "Error: No test parameters specified"
    return $False
}

$params = $testParams.Split(";")
foreach ($p in $params)
{
    $fields = $p.Split("=")
    switch ($fields[0].Trim())
    {
    "GcovGroupFile" { $GcovGroupFile = $fields[1].Trim() }
    "TestLogDir" { $TestLogDir = $fields[1].Trim() }
    "rootDir"      { $rootDir   = $fields[1].Trim() }
    default  {}       
    }
}

$TestLogDir = $rootDir + '\' + $TestLogDir

pushd "$TestLogDir"
$zipFiles = ls *.zip | Select-Object Name
$zipNumber = $zipFiles.Count

for($i=0;$i -le ($zipNumber - 1); $i++){
    $zipFiles[$i] = $zipFiles[$i].Name
}

foreach ($zipFile in $zipFiles){
    [System.IO.Compression.ZipFile]::ExtractToDirectory("$TestLogDir\$zipfile", "$TestLogDir\temp_gcov")
	$pyPath="$rootDir\tools"
    pushd .\temp_gcov
    python "$pyPath\gcovr" -g --html-details --html -o temp.html 
    python "$pyPath\gcovr-group.py" -h temp.html -O "$rootDir\$GcovGroupFile" -o .\out.html
    popd
    mv .\temp_gcov\out.html ".\$($zipFile.Split('.')[0]).html"
    rm -Recurse -Force .\temp_gcov
}

popd
