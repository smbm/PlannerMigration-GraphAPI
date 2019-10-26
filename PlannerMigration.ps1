#This definitely needs to use hashed credentials, future mod right here
$sourceclientId = "REDACTED"
$sourcetenant = "sourcetenant.onmicrosoft.com"
$sourceClientSecret = "REDACTED"
$sourceUsername = "migration_service_account@sourcetenant.onmicrosoft.com"
$sourcePassword = "REDACTED"

$targetclientId = "REDACTED"
$targettenant = "targettenant.onmicrosoft.com"
$targetClientSecret = "REDACTED"
$targetUsername = "migration_service_account@targettenant.onmicrosoft.com"
$targetPassword = "REDACTED"

#Global variables
$sourcegroupsandplans = @()
$sourceandtargetgroupsandplans = @()
$planrescanrequired = $false
$BucketCompare = @()
$SourceBuckets = @()
$TargetBuckets = @()
$bucketrescanrequired = $false

filter displayname-filter{
    param ([string]$filterString)
    if ($_.displayname -ceq "$filterString"){$_}
}

filter title-filter{
    param ([string]$filterString)
    if ($_.title -ceq "$filterString"){$_}
}

filter bucketname-filter{
    param ([string]$filterString)
    if ($_.bucketname -ceq "$filterString"){$_}
}

filter sourceuserid-filter{
    param ([string]$filterString)
    if ($_.sourceuserid -ceq "$filterString"){$_}
}

filter targetuserid-filter{
    param ([string]$filterString)
    if ($_.targetuserid -ceq "$filterString"){$_}
}

Function GetPasswordAuthToken ($clientid, $TenantName, $clientsecret, $username, $password){
    $ReqTokenBody = @{
        Grant_Type    = "Password"
        client_Id     = $clientID
        Client_Secret = $clientSecret
        Username      = $Username
        Password      = $Password
        Scope         = "https://graph.microsoft.com/.default"
    } 
    Write-Host "Connecting to " $TenantName -ForegroundColor Yellow
    $TokenResponse = Invoke-RestMethod -Uri "https://login.microsoftonline.com/$TenantName/oauth2/v2.0/token" -Method POST -Body $ReqTokenBody
    if ($null -eq $TokenResponse){
        Write-Warning "Not Connected"
    }
    Else {
        Write-Host "Connected to " $TenantName -ForegroundColor Green
    }
    return $TokenResponse
}

$sourcetoken = GetPasswordAuthToken $sourceclientId $sourcetenant $sourceClientSecret $sourceUsername $sourcePassword
$targettoken = GetPasswordAuthToken $targetclientId $targettenant $targetClientSecret $targetUsername $targetPassword

Function GetBucket ($bucketid, $token){
    return Invoke-RestMethod -Headers @{Authorization = "Bearer $($Token.access_token)"} -Uri $('https://graph.microsoft.com/v1.0/planner/buckets/' + $bucketid ) -Method Get
}

Function GetUnifiedGroups ($token) {
    $content = @()
    $unifiedgroupsout = @()
    $groupsUrl = "https://graph.microsoft.com/v1.0/Groups"
    Write-Host "Getting unified groups from tenant"  -ForegroundColor Yellow
    while (-not [string]::IsNullOrEmpty($groupsUrl)) {
        $Data = Invoke-RestMethod -Headers @{Authorization = "Bearer $($Token.access_token)"} -Uri $groupsUrl -Method Get
        if ($data.'@odata.nextLink'){$groupsUrl = $data.'@odata.nextLink'}
        else {$groupsUrl = $null}
        $content += ($Data | select-object Value).Value
    }
    Foreach ($group in $content){
        if ($group.grouptypes -eq 'Unified'){
        $unifiedgroupsout += $group
        }
    }
    return $unifiedgroupsout
}

function GetPlans($groups, $Token){
    $plans = @()
    foreach ($group in $groups){
        Write-Host "`r`nQuerying plans in $group.displayname ..." -ForegroundColor Yellow
        $checkforplans = Invoke-RestMethod -Headers @{Authorization = "Bearer $($Token.access_token)"} -Uri $('https://graph.microsoft.com/v1.0/groups/' + $group.id + '/planner/plans') -Method Get
        if ($checkforplans.value.count -gt 0){
            ForEach($plan in $checkforplans.value){
                $output = @{
                    DisplayName = $group.displayname
                    GroupID = $group.id
                    Title = $plan.title
                    PlanID = $plan.ID
                }
                $plans += new-object psobject -Property $output
            }
        }
    }
    return $plans
} 

Function GetAllUsers($token) {
    Write-Host "Getting all Users from tenant" -ForegroundColor Yellow
    $content = @()
    $usersUrl = "https://graph.microsoft.com/v1.0/Users"
    while (-not [string]::IsNullOrEmpty($usersUrl)) {
        $Data = Invoke-RestMethod -Headers @{Authorization = "Bearer $($Token.access_token)"} -Uri $UsersUrl -Method Get
        if ($data.'@odata.nextLink'){$usersUrl = $data.'@odata.nextLink'}
        else {$usersUrl = $null}
        $content += ($Data | select-object Value).Value
    }
    return $content
}

$SourceUsers = GetAllUsers $sourcetoken
$TargetUsers = GetAllUsers $targettoken

$sourceandtargetuserids = @()

foreach($sourceuser in $SourceUsers){
    $Targetuser = $TargetUsers | displayname-filter -filterString $sourceuser.displayname
    $output = @{
        displayname = $sourceuser.displayname
        sourceuserid = $sourceuser.id
        targetuserid = $Targetuser.id
    }
    $sourceandtargetuserids += New-Object psobject -Property $output
}

$sourceunifiedgroups = GetUnifiedGroups $sourcetoken
$targetunifiedgroups = GetUnifiedGroups $targettoken

$sourceplans = GetPlans $sourceunifiedgroups $sourcetoken
$targetplans = GetPlans $targetunifiedgroups $targettoken

$sourcegroupswithplans = $sourceplans | Sort-Object groupid -Unique | Sort-Object displayname | Select-Object displayname, groupid

Write-Host "`r`nComparing groups that contain plans on Source tenant are present on Target tenant`r`n" -ForegroundColor Yellow

$groupcompare = Compare-Object -ReferenceObject $sourcegroupswithplans -DifferenceObject $targetunifiedgroups -CaseSensitive -Property DisplayName -PassThru -IncludeEqual
foreach ($diff in $groupcompare){
    if ($diff.sideIndicator -eq "=="){
        Write-Host $diff.DisplayName " present in both Source and Target." -ForegroundColor Green
    }
    if ($diff.sideIndicator -eq "<="){
        Write-Host $diff.DisplayName " present in Source but not Target. Ignoring." -ForegroundColor Red
        Write-Host "Creating new groups is currently outside of the scope of this script. Mike has a script that should do this though."
    }
}

Write-Host "`r`nComparing plans on Source tenant to see if they are present on Target tenant`r`n"

$plancompare = Compare-Object -ReferenceObject $sourceplans -DifferenceObject $targetplans -CaseSensitive -Property DisplayName, Title -PassThru -IncludeEqual
foreach ($plan in $plancompare){
    if ($plan.SideIndicator -eq "<="){
        Write-Host $plan.Title "in Group" $plan.DisplayName "is present in Source but not Target. Attempting to create." -ForegroundColor Red
        $targetgroupforplan = $targetunifiedgroups | displayname-filter -filterString $plan.displayname
        $payload = @{ owner = $targetgroupforplan.id; title = $plan.title }
        $jsonpayload = $payload | ConvertTo-Json
        $success =  Invoke-RestMethod -Method POST -Uri 'https://graph.microsoft.com/v1.0/planner/plans' -Headers @{Authorization = "Bearer $($TargetToken.access_token)"} -Body $jsonpayload -ContentType 'application/json'
        if ($null -eq $success){
            Write-Host "Failed to add plan " $plan.title " to group " $targetgroupforplan.displayname " in the Tenant " $targettenant -ForegroundColor Red
        }
        if ($success){
            Write-Host "That seemed to work, the plan: " $plan.title " has been added to the group: " $targetgroupforplan.displayname " in the Tenant " $targettenant -ForegroundColor Green
        }
        $planrescanrequired = $true
    }
    if ($plan.SideIndicator -eq "=="){
        Write-Host $plan.Title "in Group" $plan.DisplayName "is present in Source and Target" -ForegroundColor Green
    }       
}

if ($planrescanrequired -eq $true){
    $planrescanrequired = $false
    Write-Host "New plans were created during this script run, attempting to rescan for plans and check for differences. This will only happen once." -ForegroundColor Yellow
    $sourceplans = GetPlans $sourceunifiedgroups $sourcetoken
    $targetplans = GetPlans $targetunifiedgroups $targettoken
    $sourcegroupswithplans = $sourceplans | Sort-Object groupid -Unique | Sort-Object displayname | Select-Object displayname, groupid
    $groupcompare = Compare-Object -ReferenceObject $sourcegroupswithplans -DifferenceObject $targetunifiedgroups -CaseSensitive -Property DisplayName -PassThru -IncludeEqual
    foreach ($diff in $groupcompare){
        if ($diff.sideIndicator -eq "=="){
            Write-Host $diff.DisplayName " present in both Source and Target." -ForegroundColor Green
            $sourcevalidatedgroupswithplans += $sourceplans | displayname-filter -filterString $diff.displayname
        }
        if ($diff.sideIndicator -eq "<="){
            Write-Host $diff.DisplayName " present in Source but not Target. Ignoring." -ForegroundColor Red
            Write-Host "Creating new groups is currently outside of the scope of this script. Mike has a script that should do this though."
        }
    }
    $plancompare = Compare-Object -ReferenceObject $sourceplans -DifferenceObject $targetplans -CaseSensitive -Property DisplayName, Title -PassThru -IncludeEqual
    $sourcegroupsandplans = Compare-Object -ReferenceObject $sourceplans -DifferenceObject $targetplans -CaseSensitive -Property DisplayName, Title -PassThru -IncludeEqual -ExcludeDifferent
    foreach ($plan in $plancompare){
        if ($plan.SideIndicator -eq "<="){
            Write-Host $plan.Title "in Group" $plan.DisplayName "is present in Source but not Target. You will need to investigate what has gone wrong and try running this script again." -ForegroundColor Red
        }
        if ($plan.SideIndicator -eq "=="){
            Write-Host $plan.Title "in Group " $plan.DisplayName "is present in Source and Target" -ForegroundColor Green
        }       
    }
}

$sourcegroupsandplans = Compare-Object -ReferenceObject $sourceplans -DifferenceObject $targetplans -CaseSensitive -Property DisplayName, Title -PassThru -IncludeEqual -ExcludeDifferent

foreach ($group in $sourcegroupsandplans){
    $targetgroup = $targetunifiedgroups | displayname-filter -filterString $group.displayname
    $targetplan = $targetplans | title-filter -filterString $group.title
    if($targetplan.planid.count -gt 1){$targetplanfirstvalue = $targetplan.planid[0]}
    else{$targetplanfirstvalue = $targetplan.planid}
    if($group.planid.count -gt 1){$sourceplanfirstvalue = $group.planid[0]}
    else{$sourceplanfirstvalue = $group.planid}
    $output = @{
        DisplayName = $group.displayname
        SourceGroupID = $group.groupid
        Title = $group.title
        SourcePlanID = $sourceplanfirstvalue
        TargetGroupID = $targetgroup.id
        TargetPlanID = $targetplanfirstvalue
    }
    $sourceandtargetgroupsandplans += new-object psobject -Property $output    
}

Write-Host "Attempting to check for buckets in Source tenant to be written to plans in Target tenant" -ForegroundColor Yellow

function GetSourceBuckets($plan, $Token){
    $buckets = @()
    Write-Host "`r`nQuerying Buckets in $plan.title ..." -ForegroundColor Yellow
    $checkforbuckets = Invoke-RestMethod -Headers @{Authorization = "Bearer $($Token.access_token)"} -Uri $('https://graph.microsoft.com/v1.0/planner/plans/' + $plan.SourcePlanID + '/buckets') -Method Get
    if ($checkforbuckets.value.count -gt 0){
        ForEach($bucket in $checkforbuckets.value){
            $output = @{
                Title = $plan.title
                PlanID = $bucket.planid
                BucketID = $bucket.id
                BucketName = $bucket.name
                BucketOrederHint = $bucket.orderhint
            }
            $buckets += new-object psobject -Property $output
        }
    }
    return $buckets
} 

function GetTargetBuckets($plan, $Token){
    $buckets = @()
    Write-Host "`r`nQuerying Buckets in $plan.title ..." -ForegroundColor Yellow
    $checkforbuckets = Invoke-RestMethod -Headers @{Authorization = "Bearer $($Token.access_token)"} -Uri $('https://graph.microsoft.com/v1.0/planner/plans/' + $plan.TargetPlanID + '/buckets') -Method Get
    if ($checkforbuckets.value.count -gt 0){
        ForEach($bucket in $checkforbuckets.value){
            $output = @{
                Title = $plan.title
                PlanID = $bucket.planid
                BucketID = $bucket.id
                BucketName = $bucket.name
                BucketOrederHint = $bucket.orderhint
            }
            $buckets += new-object psobject -Property $output
        }
    }
    return $buckets
} 

foreach ($plan in $sourceandtargetgroupsandplans){
    Write-Host "Getting buckets from source and target tenants for plan" $plan.title -ForegroundColor Yellow
    $SourceBuckets += GetSourceBuckets $plan $sourcetoken
    $TargetBuckets += GetTargetBuckets $plan $targettoken
}

$BucketCompare = Compare-Object -ReferenceObject $SourceBuckets -DifferenceObject $TargetBuckets -CaseSensitive -Property Title, BucketName -PassThru -IncludeEqual
foreach ($diff in $BucketCompare){
    if ($diff.sideIndicator -eq "=="){
        Write-Host "Bucket " $diff.BucketName " present in both Source and Target." -ForegroundColor Green
    }
    if ($diff.sideIndicator -eq "<="){
        Write-Host $diff.BucketName " present in Source but not Target. Attempting to resolve." -ForegroundColor Red
        $targetplan = $targetplans | title-filter -filterString $diff.title
        $payload = @{ name = $diff.bucketname; planId = $targetplan.planid; orderHint = " !" }
        $jsonpayload = $payload | ConvertTo-Json
        $success =  Invoke-RestMethod -Method POST -Uri 'https://graph.microsoft.com/v1.0/planner/buckets' -Headers @{Authorization = "Bearer $($TargetToken.access_token)"} -Body $jsonpayload -ContentType 'application/json'
        if ($null -eq $success){
            Write-Host "Failed to add bucket " $diff.bucketname " to plan " $diff.title " in the Tenant " $targettenant -ForegroundColor Red
        }
        if ($success){
            Write-Host "That seemed to work, the bucket: " $diff.bucketname " has been added to the plan: " $diff.title " in the Tenant " $targettenant -ForegroundColor Green
        }
        $bucketrescanrequired = $true
    }
}
if($bucketrescanrequired -eq $true){
    $bucketrescanrequired = $false
    Write-Host "Changes to the target buckets too place so a rescan is being performed. This will only happen once." -ForegroundColor Yellow
    foreach ($plan in $sourceandtargetgroupsandplans){
        Write-Host "Getting buckets from source and target tenants for plan" $plan.title -ForegroundColor Yellow
        $SourceBuckets += GetSourceBuckets $plan $sourcetoken
        $TargetBuckets += GetTargetBuckets $plan $targettoken
    }
}

$BucketCompare = Compare-Object -ReferenceObject $SourceBuckets -DifferenceObject $TargetBuckets -CaseSensitive -Property Title, BucketName -PassThru -IncludeEqual -ExcludeDifferent

function GetTasksByPlan($token, $planid){
    $content = @()
    $tasksUrl = $('https://graph.microsoft.com/v1.0/planner/plans/' + $planid + '/tasks')
    while (-not [string]::IsNullOrEmpty($tasksUrl)) {
        Write-Host "`r`nQuerying $tasksUrl..." -ForegroundColor Yellow
        $Data = Invoke-RestMethod -Headers @{Authorization = "Bearer $($Token.access_token)"} -Uri $tasksUrl -Method Get
        if ($data.'@odata.nextLink'){$tasksUrl = $data.'@odata.nextLink'}
        else {$tasksUrl = $null}
        $content += ($Data | select-object Value).Value
    }
    return $content
}

$sourcetasks = @()
$targettasks = @()
$taskcompare = @()
$data = @()

foreach ($plan in $sourceandtargetgroupsandplans){
    Write-Host "Getting tasks from source and target tenants for plan" $plan.title -ForegroundColor Yellow
    $sourcetasks = GetTasksByPlan $sourcetoken $plan.SourcePlanID
    $targettasks = GetTasksByPlan $targettoken $plan.TargetPlanID
    $success = $null
    If(!$null -eq $targettasks){
        $taskcompare = Compare-Object -ReferenceObject $sourcetasks -DifferenceObject $targettasks -CaseSensitive -Property title, assignments -PassThru -IncludeEqual
        foreach($diff in $taskcompare){
            if ($diff.sideIndicator -eq "=="){
                Write-Host "Task" $diff.title "present and correctly assigned in both Source and Target. Checking bucket name..." -ForegroundColor Green
                $sourceplanbucketname = (GetBucket $diff.bucketid $sourcetoken).name
                if($sourceplanbucketname -ceq $(GetTargetBuckets $plan $targettoken | bucketname-filter -filterString $sourceplanbucketname).bucketname){
                    Write-Host "Bucket names match. Moving on" -ForegroundColor Green
                }
                Else {Write-Host "Bucket names do not match, unsure what to do here at this point" -ForegroundColor Red}
            }
            if ($diff.sideIndicator -eq "<="){
                $taskassignees = @()
                $taskassignments = @{}
                $taskpayload = @{}
                Write-Host "Task" $diff.title "present on source but not in target tenant" -ForegroundColor Red
                $sourceplanbucketname = $(GetBucket $diff.bucketid $sourcetoken).name
                $targetbucketfortask = GetTargetBuckets $plan $targettoken | bucketname-filter -filterString $sourceplanbucketname
                if(-not [string]::IsNullOrEmpty($diff.assignments)){
                    Write-Host "Checking for task asignees and building JSON payload" -ForegroundColor Yellow
                    $sourcetaskassignees = $($diff.assignments | Get-Member -MemberType NoteProperty).name
                    foreach($assignee in $sourcetaskassignees){
                        $taskassignees += $sourceandtargetuserids | sourceuserid-filter -filterString $assignee
                    }
                    foreach($assignee in $taskassignees){
                        $payload = @{$assignee.targetuserid = @{ '@odata.type' = "#microsoft.graph.plannerAssignment"; orderHint = " !" }}
                        $taskassignments += $payload
                    }
                }
                $taskpayload = @{ planId = $plan.TargetPlanID ; bucketId = $targetbucketfortask.BucketID ; title = $diff.title }
                if($taskassignments.keys.count -gt 0){
                    $taskpayload.Add("assignments", $taskassignments)
                }
                $jsontaskpayload = $taskpayload | ConvertTo-Json
                Write-Host "Attempting to create task" -ForegroundColor Yellow
                $success = Invoke-RestMethod -Method POST -Uri 'https://graph.microsoft.com/v1.0/planner/tasks' -Headers @{Authorization = "Bearer $($targetToken.access_token)"} -Body $jsontaskpayload -ContentType 'application/json'
                if($success){Write-Host "That seemed to work fine yeah?" -ForegroundColor Green}
                else{Write-Host "That did not wotk for some reason" -ForegroundColor Red}
            }
        }
    } 
    Else {
        if($sourcetasks){
        Write-Host "There do not seem to be any tasks in the target tenant for this plan, lets fix that" -ForegroundColor Yellow
            foreach($task in $sourcetasks){
                $taskassignees = @()
                $taskassignments = @{}
                $taskpayload = @{}
                $sourceplanbucketname = $(GetBucket $task.bucketid $sourcetoken).name
                $targetbucketfortask = GetTargetBuckets $plan $targettoken | bucketname-filter -filterString $sourceplanbucketname
                if(-not [string]::IsNullOrEmpty($task.assignments)){
                    Write-Host "Checking for task asignees and building JSON payload" -ForegroundColor Yellow
                    $sourcetaskassignees = $($task.assignments | Get-Member -MemberType NoteProperty).name
                    foreach($assignee in $sourcetaskassignees){
                        $taskassignees += $sourceandtargetuserids | sourceuserid-filter -filterString $assignee
                    }
                    foreach($assignee in $taskassignees){
                        $payload = @{$assignee.targetuserid = @{ '@odata.type' = "#microsoft.graph.plannerAssignment"; orderHint = " !" }}
                        $taskassignments += $payload
                    }
                }
                $taskpayload = @{ planId = $plan.TargetPlanID ; bucketId = $targetbucketfortask.BucketID ; title = $task.title }
                if($taskassignments.keys.count -gt 0){
                    $taskpayload.Add("assignments", $taskassignments)
                }
                $jsontaskpayload = $taskpayload | ConvertTo-Json
                Write-Host "Attempting to create task" -ForegroundColor Yellow
                
                $success = Invoke-RestMethod -Method POST -Uri 'https://graph.microsoft.com/v1.0/planner/tasks' -Headers @{Authorization = "Bearer $($targetToken.access_token)"} -Body $jsontaskpayload -ContentType 'application/json'
                if($success){Write-Host "That seemed to work fine yeah?" -ForegroundColor Green}
                else{Write-Host "That did not wotk for some reason" -ForegroundColor Red}
            }
        }
        else{
            Write-Host "No tasks associated with this plan in the source tenant, moving on..." -ForegroundColor Yellow
        }
    }
}
