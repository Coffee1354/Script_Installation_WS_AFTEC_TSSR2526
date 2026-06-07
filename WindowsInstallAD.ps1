# 1. SÉCURITÉ : Vérification des privilèges Administrateur
if (-not ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
    Write-Host("ERREUR : Ce script doit être exécuté en tant qu'Administrateur !") -ForegroundColor Red
    return
}

Write-Host "==========================================" -ForegroundColor Cyan
Write-Host "  PHASE 2 : PROMOTION ACTIVE DIRECTORY & DNS" -ForegroundColor Cyan
Write-Host "==========================================" -ForegroundColor Cyan

# 2. COLLECTE DES INFORMATIONS
    while($True){
        $DomainName = (Read-Host("1. Quel est le nom de domaine complet (ex : my.domain) ?")).trim()

        # Le nom NetBIOS est souvent la première partie du domaine en majuscule. On propose de l'automatiser.
        $NetbiosName = (Read-Host("2. Quel est le nom NetBIOS (ex : MY en majuscule de my.domain)"))
        if([string]::IsNullOrEmpty($NetbiosName)){
            $NetbiosName = $DomainName.Split('.')[0].ToUpper()
        }

        Write-Host("`n--- Récapitulatif ---") -ForegroundColor Cyan
        Write-Host("Nom de Domaine : $DomainName")
        Write-Host("Nom NetBIOS    : $NetbiosName")

        $VerifConf = Read-Host("`nConfirmez vous votre choix ? Y/N")
        if($VerifConf -eq "Y"){
            break
        } else {
            Write-Host("---- Erreur de saisie | Echec de la configuration ----") -ForegroundColor Cyan
        }
    }

# Le mot de passe DSRM (Directory Services Restore Mode) est obligatoire.
# Il est saisi à l'aveugle et converti directement en chaîne sécurisée.
Write-Host("`n3. Configuration du mot de passe DSRM (Administrateur de restauration)") -ForegroundColor Cyan
$DSRMPwd = Read-Host ("Veuillez taper le mot de passe DSRM") -AsSecureString

# 3. APPLICATION DE LA CONFIGURATION
try {
    Write-Host("`n---- Installation du rôle AD DS (Binaires) ----") -ForegroundColor Cyan 
    Install-WindowsFeature -Name AD-Domain-Services -IncludeManagementTools -ErrorAction Stop | Out-Null
    Write-Host("---- Binaires installés ----") -ForegroundColor Green

    Write-Host("`n---- Promotion en Contrôleur de Domaine ----") -ForegroundColor Cyan
    Write-Host (" ATTENTION : La création de la forêt prend quelques minutes.") -ForegroundColor Yellow
    Write-Host (" ATTENTION : Le serveur redémarrera automatiquement à la fin du processus !") -ForegroundColor Red
        
    # Lancement de la création de la forêt AD
    Install-ADDSForest `
        -DomainName $DomainName `
        -DomainNetbiosName $NetbiosName `
        -InstallDns:$true `
        -CreateDnsDelegation:$false `
        -DatabasePath "C:\Windows\NTDS" `
        -LogPath "C:\Windows\NTDS" `
        -SysvolPath "C:\Windows\SYSVOL" `
        -Force:$true `
        -SafeModeAdministratorPassword $DSRMPwd `
        -ErrorAction Stop

        # Note : Le code en dessous de cette ligne ne s'exécutera quasiment jamais
        # car le paramètre -Force déclenche un redémarrage immédiat par le système.
    } 
catch {
    Write-Host("`n---- ÉCHEC : Une erreur s'est produite lors de la promotion AD ----") -ForegroundColor Red
    Write-Host("Détail : $($_.Exception.Message)") -ForegroundColor Gray
}