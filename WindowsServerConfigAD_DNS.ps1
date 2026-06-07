function CreateOU{
    param(
        [Parameter(Mandatory=$true)]
        [string]$ParentPath
    )
    while($true){
        Write-Host("Emplacement actuel dans l'architecture : $ParentPath ") -ForegroundColor Cyan
        $ouName = (Read-Host("Nom de la nouvelle OU (Laissez vide et faites Entrée pour quitter)")).trim()
        
        # Si l'utilisateur ne tape rien, on casse la boucle pour remonter au niveau précédent
        if ([string]::IsNullOrEmpty($ouName)) { 
            break 
        }
        
        # Calcul du chemin de la nouvelle OU
        $newOUPath = "OU=$ouName,$ParentPath"

        try {
            # On vérifie si l'OU existe déjà à CET emplacement précis (-SearchScope OneLevel)
            if (-not (Get-ADOrganizationalUnit -Filter "Name -eq '$ouName'" -SearchBase $ParentPath -SearchScope OneLevel -ErrorAction SilentlyContinue)) {
                New-ADOrganizationalUnit -Name $ouName -Path $ParentPath -ErrorAction Stop
                Write-Host("---- L'OU '$ouName' a été créée avec succès ----") -ForegroundColor Green
            } else {
                Write-Host("---- L'OU '$ouName' existe déjà à cet emplacement ----") -ForegroundColor Yellow
            }

            # On demande si on veut créer une sous-OU à l'intérieur de celle qu'on vient de faire
            $subOu = Read-Host " Voulez-vous créer une sous-OU dans '$ouName' ? (Y/N)"
            
            if ($subOu -eq "Y") {
                Write-Host "---- Descente dans le dossier $ouName ----" -ForegroundColor Magenta
                
                # La fonction s'appelle elle-même, mais en donnant le nouveau chemin en paramètre !
                New-InteractiveOU -ParentPath $newOuPath
                
                Write-Host "---- Remontée au dossier précédent ----" -ForegroundColor Magenta
            }
            
            # La boucle recommence automatiquement pour te proposer de créer
            # une AUTRE OU au même niveau (ex: RH après avoir créé IT).
            
        } catch {
            Write-Host ("---- Erreur lors de la création de l'OU : $($_.Exception.Message) ----") -ForegroundColor Red
        }
    }

}

function New-InteractiveUser {
    param(
        [Parameter(Mandatory=$true)]
        [string]$DomainName,

        [Parameter(Mandatory=$true)]
        [string]$RootDSE
    )

    Write-Host "`n ---- Assistant de création d'utilisateurs ----" -ForegroundColor Cyan

    while($true){
        $Prenom = (Read-Host "Prénom de l'utilisateur (Laissez vide pour quitter)").Trim()
        if([string]::IsNullOrEmpty($Prenom)){
            break
        }

        $Nom = (Read-Host "Nom de famille de l'utilisateur").Trim()

        # Génération automatique des identifiants standards
        $InitialePrenom = $Prenom.Substring(0,1)
        $SamAccount = "$InitialePrenom.$Nom".ToLower()
        $DisplayName = "$Prenom $Nom"
        $UPN = "$SamAccount@$DomainName"

        Write-Host "L'identifiant généré sera : $UPN" -ForegroundColor DarkGray

        # Recherche dynamique de l'OU cible
        $TargetOU = (Read-Host "Dans quelle OU souhaitez-vous le placer ?").Trim()

        # CORRECTION 1 : Ajout du guillemet simple à la fin du filtre
        $OuObject = Get-ADOrganizationalUnit -Filter "Name -eq '$TargetOU'" -ErrorAction SilentlyContinue

        # CORRECTION 2 : Gestion propre de l'erreur si l'OU n'existe pas
        if($OuObject -eq $null){
            Write-Host "Erreur : L'OU '$TargetOU' est introuvable." -ForegroundColor Red
            continue # On recommence la boucle depuis le début
        }
        elseif($OuObject.Count -gt 1){
            Write-Host "Plusieurs OU portent le nom '$TargetOU'. Utilisation de la première trouvée : $($OuObject[0].DistinguishedName)" -ForegroundColor Yellow
            $OuPath = $OuObject[0].DistinguishedName
        }else{
            # CORRECTION 3 : Appel de la bonne variable ($OuObject)
            $OuPath = $OuObject.DistinguishedName
        }

        [string]$PWD = "P@ssw0rd"
        $Password = ConvertTo-SecureString $PWD -AsPlainText -Force
        Write-Host "Le mot de passe par défaut sera : $PWD. Il sera changé à la première connexion." -ForegroundColor DarkGray

        try {
            # Verification de l'existence de l'utilisateur
            if(-not(Get-AdUser -Filter "SamAccountName -eq '$SamAccount'" -ErrorAction SilentlyContinue)){
                New-ADUser -Name $DisplayName `
                    -GivenName $Prenom `
                    -Surname $Nom `
                    -SamAccountName $SamAccount `
                    -UserPrincipalName $UPN `
                    -Path $OuPath `
                    -AccountPassword $Password `
                    -Enabled $true `
                    -ChangePasswordAtLogon $true `
                    -ErrorAction Stop

                Write-Host "---- L'utilisateur $DisplayName a été créé avec succès dans $TargetOU !" -ForegroundColor Green
            }else{
                Write-Host "L'utilisateur $SamAccount existe déjà." -ForegroundColor Yellow
            }
        }catch{
            Write-Host "Erreur lors de la création de l'utilisateur : $($_.Exception.Message)" -ForegroundColor Red
        }

        Write-Host "------------------------------------------------" -ForegroundColor Cyan
    }
}

function New-InteractiveCNAME {
    param(
        [parameter(Mandatory=$true)]
        [string]$ZoneName,  #Correspond au nom de ton domaine (ex: my.domain)

        [Parameter(Mandatory=$true)]
        [string]$TargetFQDN #Correspond au nom complet du serveur cible (ex WIN-SRV.my.domain)
    )

    Write-Host("`n---- Assistant de configuration DNS (Alias CNAME) ----") -ForegroundColor Cyan

    while($true){
        $AliasName = (Read-Host("Quel Alias (CNAME) voulez-vous créer ? (Laissez vide pour quitter)")).trim()
    
        if([string]::IsNullOrEmpty($AliasName)){
            break
        }

        try {
            if(-not(Get-DnsServerResourceRecord -ZoneName $ZoneName -Name $AliasName -ErrorAction SilentlyContinue)){
                Write-Host("---- Création de l'alias '$AliasName' pointant vers $TargetFQDN ----") -ForegroundColor Cyan
                Add-DnsServerResourceRecordCName -Name $AliasName -HostNameAlias $TargetFQDN -ZoneName $ZoneName -ErrorAction Stop
                Write-Host("---- Alias DNS $AliasName.$ZoneName créé avec succès ----") -ForegroundColor Green
            }else{
                Write-Host("Un enregistrement DNS nommé '$AliasName' existe déjà dans la zone $ZoneName.") -ForegroundColor Yellow
            }
        }catch{
            Write-Host("---- Erreur lors de la création de l'alias : $($_.Exception.Message)") -ForegroundColor Red
        }

        Write-Host("------------------------------------------------") -ForegroundColor Cyan
    }
}



# 1. SÉCURITÉ : Vérification des privilèges Administrateur du Domaine
if (-not ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
    Write-Host "ERREUR : Ce script doit être exécuté en tant qu'Administrateur !" -ForegroundColor Red
    return
}

Write-Host("==========================================") -ForegroundColor Cyan
Write-Host("  PHASE 4 : CONFIGURATION AD, DNS ET DHCP") -ForegroundColor Cyan
Write-Host("==========================================") -ForegroundColor Cyan

Import-Module ActiveDirectory
Import-Module DnsServer
Import-Module dhcpserver

# Récupération automatique des infos du domaine actuel
$Domain = Get-ADDomain
$RootDSE = $Domain.DistinguishedName
$ServerName = $env:COMPUTERNAME
$ServerFQDN = "$ServerName.$($Domain.Name)"
$ServerIP = (Get-NetIPAddress -AddressFamily IPv4 -InterfaceAlias (Get-NetAdapter | Where-Object Status -eq "Up").Name).IPAddress

try {
    Write-Host("---- Création de l'arborescence (Ous) ----") -ForegroundColor Cyan
    # Ton ajout : On demande le nom de l'entreprise
    $BaseOU = (Read-Host "Veuillez insérer le nom de l'OU principale (ex: Nom de l'entreprise)").Trim()
    # On calcule le chemin complet de cette nouvelle OU racine
    $BaseOUPath = "OU=$BaseOU,$RootDSE"

    try {
        # 1. On vérifie et on crée l'OU racine en premier
        if (-not (Get-ADOrganizationalUnit -Filter "Name -eq '$BaseOU'" -SearchBase $RootDSE -SearchScope OneLevel -ErrorAction SilentlyContinue)) {
            Write-Host("Création de l'OU racine : $BaseOU...") -ForegroundColor Cyan
            New-ADOrganizationalUnit -Name $BaseOU -Path $RootDSE -ErrorAction Stop
            Write-Host ("---- L'OU racine a été créée ----") -ForegroundColor Green
        } else {
            Write-Host ("---- L'OU racine '$BaseOU' existe déjà ----") -ForegroundColor Green
        }

        Write-Host "`n---- Lancement de l'assistant de création pour les sous-dossiers ----" -ForegroundColor Magenta
    
        # 2. On appelle ta fonction récursive en lui donnant le CHEMIN de l'OU qu'on vient de créer !
        CreateOU -ParentPath $BaseOUPath
    
        Write-Host ("---- Arborescence terminée ----") -ForegroundColor Green

    } catch {
        Write-Host ("---- Erreur lors de l'initialisation de l'arborescence : $($_.Exception.Message) ----") -ForegroundColor Red
    }

    Write-Host("---- Création des utilisateurs ----") -ForegroundColor Cyan
    # On appelle la fonction en lui passant le nom de domaine et la racine
    New-InteractiveUser -DomainName $Domain.Name -RootDSE $RootDSE
    Write-Host("---- Gestion des utilisateurs terminée ----") -ForegroundColor Green

    Write-Host("`n---- Configuration DNS (Enregistrement CNAME) ----") -ForegroundColor Cyan
    # Récupération automatique des informations si tu ne les as pas déjà en variables globales
    New-InteractiveCNAME -ZoneName $Domain.Name -TargetFQDN $ServerFQDN
    Write-Host("---- Gestion des alias DNS terminée ----") -ForegroundColor Green

    # Optionnel mais recommandé : On autorise le DHCP créé à la Phase 1 dans l'Active Directory
    Write-Host("`n---- Autorisation DHCP dans l'AD ----") -ForegroundColor Cyan
    $DhcpAuth = Get-DhcpServerInDC -ErrorAction SilentlyContinue
    if ($DhcpAuth.DnsName -notcontains $ServerFQDN){
        Add-DhcpServerInDC -DnsName $ServerFQDN -IPAddress $ServerIP -ErrorAction Stop
        Write-Host("---- Serveur DHCP $ServerFQDN autorisé ----") -ForegroundColor Green
    }else{
        Write-Host("---- Le serveur DHCP est déjà autorisé ----") -ForegroundColor Yellow
    }

    Write-Host("`n===========================================================")-ForegroundColor Cyan
    Write-Host(" PROVISIONING DU SERVEUR TERMINÉ AVEC SUCCÈS ! 🎉")-ForegroundColor Cyan
    Write-Host("`n===========================================================")-ForegroundColor Cyan
   
}
catch{
    Write-Host ("`n---- ÉCHEC : Une erreur s'est produite lors de la configuration ----") -ForegroundColor Red
    Write-Host ("Détail : $($_.Exception.Message)") -ForegroundColor Gray
}