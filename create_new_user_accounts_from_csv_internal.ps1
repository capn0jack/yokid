#REWRITE THIS TO USE Get-RandPass FROM FUNCTIONS.
function GET-RandPass() {
    Param(
        [int]$length=10
    )
    $sourcedata=$NULL;For ($a=33;$a �le 126;$a++) {$sourcedata+=,[char][byte]$a }
    For ($loop=1; $loop �le $length; $loop++) {
        $RandPass+=($sourcedata | GET-RANDOM)
    }
    return $RandPass
}

function Get-UsersFile($filedefault) {
    write-host "CSV file must have column names as the first row, with these names:"
    write-host "Firstname,Lastname,SAM,Email,Password"
    write-host "The password doesn't have to be in the file; I can create it for you."
    $file = Read-host "What's the complete path of the CSV file? (Defaults to $filedefault.) "
    if ( $file -eq "" ) {
        $file = "$filedefault"
    }
    if (-not (Test-Path "$file" -PathType Leaf) ) {
        write-host "File doesn't exist.  Try again."
        Get-UsersFile($filedefault)
    }
    return $file
}

function Get-OU($client) {
    $ou = "ou=$client,ou=clients,dc=infomc,dc=biz"
    $customou = read-host "Do you want to create the users in $ou ? (Yes/No) "
    if ($customou -ne "Yes") {
        $ou= read-host "OK, enter your own OU: "
    }
    return $ou
}


#Pull in the shared functions.
. c:\_admin\scripts\functions.ps1

Set-StrictMode -Version 2
$filedefault = "c:\temp\users.csv"
$grouparray = @()
$loop = ""
$sourcedata = ""
$randpass = ""
$length = ""
$a = ""
$i = ""
$ticket = ""
$genpass = ""
$group = ""
$addgroup= ""
$curruser = ""
$currdate = ""
$domain = ""
$user = ""
$users = ""
$descstamp = ""
$displayname = ""
$userfirstname = ""
$UserLastname = ""
$file = ""
$SAM = ""
$UPN = ""
$password = ""
$client = ""
$ou = ""
$customou = ""
$email = ""
$usernum = 0

$ticket = read-host "What is the TFS ticket number for which these accounts are being created? "

$ou = "ou=users,ou=infomc organization,dc=ad,dc=infomc,dc=com"

$modeluser = getsinglevalue -posttext "To get hints for all new users from an existing account, enter that account's username now, otherwise, leave this blank: "

$templist = "InfoMC","VPN Users"
$tempgroups = pickmultiplefromlist -listin $templist -pretext "Here are some groups these users are likely to need:" -posttext "Pick the groups appropriate for these users."
$grouparray += $tempgroups

if ($modeluser) {
    $modelgroups = Get-ADPrincipalGroupMembership $modeluser | select -ExpandProperty Name
    $tempgroups = pickmultiplefromlist -listin $modelgroups -pretext "Here are $modeluser's group memberships:" -posttext "Pick the groups appropriate for these users."
    $grouparray += $tempgroups
}

$tempgroups = getlist -posttext "Give me a list of other groups to which these users should be added, one at a time:  (The first time you leave this blank, I'll stop asking.)"
$grouparray += $tempgroups

$file = Get-UsersFile($filedefault)

$genpass = read-host "Are the passwords in the CSV? (Yes/No) (If not, I'll generate them.) "

$curruser = [System.Security.Principal.WindowsIdentity]::GetCurrent().Name
$currdate = get-date -format s
$descstamp = "$curruser $currdate TFS $ticket"
$domain = "ad.infomc.com"
$Users = Import-Csv $file
foreach ($User in $Users) {
    $usernum += 1
    $Displayname = $User.Firstname + " " + $User.Lastname
    $UserFirstname = $User.Firstname
    $UserLastname = $User.Lastname
    $userlastinitial = $UserLastname.Substring(0,1)
    $SAM = $User.SAM
    $UPN = "$SAM@$domain"
    $ticket = $User.ticket
    $email = $User.Email
    if ( $genpass -eq "Yes") {
        $Password = $User.Password
    }
    else {
        $Password = GET-RandPass -length 8
        write-host "$usernum $Password"
    }            
    try {
        New-ADUser `
        -Name "$Displayname" `
        -DisplayName "$Displayname" `
        -SamAccountName "$SAM" `
        -UserPrincipalName "$UPN" `
        -GivenName "$UserFirstname" `
        -Surname "$UserLastname" `
        -Description "$descstamp" `
        -EmailAddress "$email" `
        -AccountPassword (ConvertTo-SecureString $Password -AsPlainText -Force) `
        -Enabled $true `
        -Path "$OU" `
        -ChangePasswordAtLogon $true `
        �PasswordNeverExpires $false `
        -CannotChangePassword $False `
    } catch {
        write-warning "Failed to create user $SAM with error: $_."
    }
    
    $primaryemail = ("$userfirstname.$userlastname@infomc.com").ToLower()
    $secondaryemail = ("$userfirstname$userlastinitial@infomc.com").ToLower()
    $addemails = [System.Collections.ArrayList]@()
    $addemails.add("SMTP:$primaryemail")
    $addemails.add("smtp:$($secondaryemail)")
    #add logic to check new user proxy addresses against existing addresses in o365, this will avoid trying to create duplicate mailboxes and creating sync errors.
    foreach ($address in $addemails) {set-aduser $SAM -add @{proxyaddresses="$address"}}

    $modeluser = $null
    $modelmanager = $null
    $modeltitle = $null
    $modelcompany = $null
    $modeldepartment = $null

    $modeluser = getsinglevalue -posttext "To get hints for just $userfirstname $userlastname from an existing account, enter that account's username now, otherwise, leave this blank: "

    if ($modeluser) {$modelmanager = (get-aduser $modeluser -Properties manager).manager} 
    if ($modeluser) {$modeltitle = (get-aduser $modeluser -Properties title).title}
    if ($modeluser) {$modelcompany = (get-aduser $modeluser -Properties company).company}
    if ($modeluser) {$modeldepartment = (get-aduser $modeluser -Properties department).department}

    $modelmanager = getsinglevalue -posttext "Enter the manager's username (FirstL format):" -default "$modelmanager"
    if (-not $modelmanager -like 'CN=*') {$modelmanager = (get-aduser "$modelmanager").distinguishedname}
    set-aduser $SAM -manager "$modelmanager"

    $modeltitle = getsinglevalue -posttext "Enter the job title for $userfirstname $userlastname :" -default "$modeltitle"
    set-aduser $SAM -title "$modeltitle"

    if (-not $modelcompany) {$modelcompany = "InfoMC"}
    $modelcompany = getsinglevalue -posttext "Enter the company for $userfirstname $userlastname :" -default "$modelcompany"
    set-aduser $SAM -company "$modelcompany"
    
    $modeldepartment = getsinglevalue -posttext "Enter the department for $userfirstname $userlastname :" -default "$modeldepartment"
    set-aduser $SAM -department "$modeldepartment"
    
    foreach ($group in $grouparray) {
        try {
            Add-ADGroupMember -Identity "$group" -Members "$SAM"
        }
        catch {
            write-warning "Failed to add user $SAM to group $group with error: $_."
        }
    }
}
write-host "That's all, folks!"