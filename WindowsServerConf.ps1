# 1. SÉCURITÉ : Vérification des privilèges Administrateur
    if (-not ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
        Write-Host "ERREUR : Ce script doit impérativement être exécuté en tant qu'Administrateur !" -ForegroundColor Red
        return
    }

Write-Host("==========================================") -ForegroundColor Cyan
Write-Host("  PHASE 1 : CONFIGURATION DU SERVEUR") -ForegroundColor Cyan
Write-Host("==========================================") -ForegroundColor Cyan

# 2. DÉTECTION DE LA CARTE RÉSEAU
# Le programme a pour but d'être utiliser sur un projet VM, dans ce cas, le Windows Server n'aura qu'une carte réseau. Si vous 
# souhaitez l'utiliser sur un machine physique, modifier cette partie afin de choisir la bonne interface.

$NetCard = (Get-NetAdapter | Where-Object { $_.Status -eq "Up" }).Name
Write-Host("Carte détectée : $NetCard ")

# 3. COLLECTE DES INFORMATIONS
while($True){
    $Hostname = (Read-Host("1. Veuillez définir un Nom pour ce Serveur")).Trim()
    $IpStatique = (Read-Host("2. Veuillez choisir un IP statique pour ce Serveur")).Trim()
    $IpMask = (Read-Host "3. Quel est le masque de sous réseau de l'adresse statique (ex: 24 ou 27)").Trim().Replace("/", "")
    $IpGateway = (Read-Host("Quelle est l'IP de la passerelle ?")).Trim()
    $DNSPrim = (Read-Host("Veuillez choisir le DNS primaire de ce Serveur (Recommandée : 127.0.0.1 en cas de service AD DS ou DNS)")).Trim()

    Write-Host("IP Statique : Masque : Gateway : Carte Réseau : DNS")
    Write-Host("$IpStatique : $IpMask : $IpGateway : $NetCard : $DNSPrim")

    $VerifConf = Read-Host("Confirmez vous votre choix ? Y/N")
        if($VerifConf -eq "Y"){
            break
        }else{
            Write-Host("---- Erreur de saisie | Echec de la configuration ----")
            continue
        }
}
# 4. APPLICATION DE LA CONFIGURATION
Write-Host "`n---- Application des paramètres (Coupure réseau possible) ----" -ForegroundColor Yellow

    try {
        # Configuration de l'IP statique 
        Write-Host("---- Configuration de l'IP statique ----") -ForegroundColor Cyan
        # On désactive le DHCP de la carte pour le mettre en statique
        Set-NetIPInterface -InterfaceAlias $NetCard -Dhcp Disabled -ErrorAction Stop
        # On supprime les anciennes IP pour éviter les conflits
        Remove-NetIPAddress -InterfaceAlias $NetCard -Confirm:$false -ErrorAction SilentlyContinue
        # On applique la nouvelle configuration
        New-NetIPAddress -InterfaceAlias $NetCard -IPAddress $IpStatique -PrefixLength $IpMask -DefaultGateway $IpGateway -ErrorAction Stop | Out-Null

        Write-Host("--- Configuration du DNS primaire (127.0.0.1 - Futur AD DS)") -ForegroundColor Cyan
        Set-DnsClientServerAddress -InterfaceAlias $NetCard -ServerAddresses $DNSPrim -ErrorAction Stop

        Write-Host("---- Changement du nom du serveur en '$Hostname' ----") -ForegroundColor Cyan
        if ($env:COMPUTERNAME -ne $Hostname){
            Rename-Computer -NewName $Hostname -Force -ErrorAction Stop
            Write-Host(" Nom modifié ave succès. ") -ForegroundColor Green
        }else{
            Write-Host("Le serveur s'appelle déjà $Hostname. ") -ForegroundColor Green
        }

        Write-Host "`n==========================================" -ForegroundColor Green
        Write-Host "✅ SUCCÈS : Configuration de base terminée !" -ForegroundColor Green
        Write-Host "Le serveur doit redémarrer pour valider le nouveau nom." -ForegroundColor Yellow
        Write-Host "==========================================" -ForegroundColor Green

        $Reboot = Read-Host("Voulez-vous redémarrer le serveur maintenant ? (Y/N)")
        if($Reboot -eq "Y"){
            Restart-Computer -Force
        }
    }
    catch {
        Write-Host "`n ÉCHEC : Une erreur s'est produite lors de la configuration." -ForegroundColor Red
        Write-Host "Détail : $($_.Exception.Message)" -ForegroundColor Gray
    }

