$ErrorActionPreference='Stop'
Set-Location $PSScriptRoot
foreach($name in @('eagle-fleet-private','eagle-fleet-egress')) {
    $existing=docker network ls --filter "name=^$name`$" --format '{{.Name}}'
    if(!$existing){
        if($name -eq 'eagle-fleet-private'){docker network create --internal --label eagle.fleet=true $name | Out-Null}
        else{docker network create --label eagle.fleet=true $name | Out-Null}
        if($LASTEXITCODE){throw 'Network provisioning failed; reconcile exact name before retry'}
    }
    $network=(docker network inspect $name|ConvertFrom-Json)[0]
    if($network.Labels.'eagle.fleet' -ne 'true'){throw 'Network name collision'}
    if($name -eq 'eagle-fleet-private' -and !$network.Internal){throw 'Private network is not internal'}
}
$existing=docker ps -a --filter 'name=^eagle-fleet-proxy$' --format '{{.Names}}'
if(!$existing){
    docker run -d --name eagle-fleet-proxy --restart unless-stopped --label eagle.fleet=true --network eagle-fleet-private --user 65534:65534 --read-only --cap-drop ALL --security-opt no-new-privileges --pids-limit 128 --memory 512m eagle-fleet-gateway:local
    if($LASTEXITCODE){throw 'Proxy create uncertain; inspect exact name before retry'}
} else {
    $obj=(docker inspect eagle-fleet-proxy|ConvertFrom-Json)[0]
    if($obj.Config.Labels.'eagle.fleet' -ne 'true'){throw 'Proxy name collision'}
    if(!$obj.State.Running){docker start eagle-fleet-proxy|Out-Null}
}
$obj=(docker inspect eagle-fleet-proxy|ConvertFrom-Json)[0]
if(!$obj.NetworkSettings.Networks.'eagle-fleet-egress'){
    docker network connect eagle-fleet-egress eagle-fleet-proxy
    if($LASTEXITCODE){throw 'Proxy egress connection failed'}
}
(docker inspect eagle-fleet-proxy|ConvertFrom-Json)[0].NetworkSettings.Networks.'eagle-fleet-private'.IPAddress
