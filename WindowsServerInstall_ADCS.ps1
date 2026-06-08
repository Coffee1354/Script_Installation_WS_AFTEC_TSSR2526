# 1. SÉCURITÉ : Vérification des privilèges Administrateur du Domaine
if (-not ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
    Write-Host "ERREUR : Ce script doit être exécuté en tant qu'Administrateur !" -ForegroundColor Red
    return
}

Write-Host "==========================================" -ForegroundColor Cyan
Write-Host "  PHASE OPTIONNELLE : AD CS & LDAPS (GLPI)" -ForegroundColor Cyan
Write-Host "==========================================" -ForegroundColor Cyan

try {
    # Récupération du nom court du domaine pour nommer l'autorité de certification
    $Domain = Get-ADDomain
    $CAName = "$($Domain.NetBIOSName)-CA"

    Write-Host("`n---- Installation des binaires AD CS ----") -ForegroundColor Cyan
    Install-WindowsFeature Adcs-Cert-Authority -IncludeManagementTools -ErrorAction Stop | Out-Null
    Write-Host ("---- Binaires installés ----") -ForegroundColor Green

    Write-Host("`n---- Configuration de l'Autorité de Certification (Entreprise) ----") -ForegroundColor Cyan
    Write-Host("Création de l'autorité racine '$CAName' en cours...") -ForegroundColor Yellow

    # L'installation en "EnterpriseRootCa" génère automatiquement le certificat LDAPS du serveur
    Install-AdcsCertificationAuthority `
        -CAType EnterpriseRootCa `
        -CACommonName $CAName `
        -KeyLength 2048 `
        -HashAlgorithmName SHA256 `
        -ValidityPeriod Years `
        -ValidityPeriodUnits 5 `
        -Force -ErrorAction Stop | Out-Null

    Write-Host("---- Autorité de Certification installée et LDAPS activé ----") -ForegroundColor Green

    Write-Host("`n---- Export du Certificat Public pour GLPI ----") -ForegroundColor Cyan
    $ExportPath = "$HOME\Deskpop\Certificat_LDAPS_$CAName.cer"
    Write-Host("Attente de l'initialisation complète du service de certification...") -ForegroundColor Cyan
    Start-Sleep -Seconds 5

    Start-Service CertSvc -ErrorAction SilentlyContinue
    $VraiCertificat = Get-ChildItem Cert:\LocalMachine\My | Where-Objet { $_.Subject -like "*CN=$CAName*" } | Select-Object -First 1
    
   if($VraiCertificat){
        Export-Certificate -Cert $VraiCertificat -FilePath $ExportPath | Out-Null

        Write-Host("---- Certificat public exporté avec succès ----") -ForegroundColor Green
        Write-Host("Vous trouverez le fichier ici : $ExportPath") -ForegroundColor Yellow
        Write-Host("Il suffira d'importer ce fichier (.cer) dans la configuration de votre serveur GLPI.") -ForegroundColor Yellow
   }else{
        Write-Host("ERREUR : Impossible de trouver le certificat de l'autorité '$CAName' dans le magasin local.") -ForegroundColor Red
   }

    Write-Host ("`n===========================================================") -ForegroundColor Green
    Write-Host (" DÉPLOIEMENT AD CS TERMINÉ ! ") -ForegroundColor Green
    Write-Host ("Le port TCP 636 (LDAPS) est désormais ouvert et sécurisé.") -ForegroundColor Green
    Write-Host ("===========================================================") -ForegroundColor Green
}catch{
    Write-Host("`n ECHEC : Une erreur s'est produite lors de l'installation AD CS.") -ForegroundColor Red
    Write-Host("Détail : $($_.Exception.Message)") -ForegroundColor Gray
}
