    # 1. SÉCURITÉ : Vérification des privilèges Administrateur
    if (-not ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
        Write-Host "ERREUR : Ce script doit impérativement être exécuté en tant qu'Administrateur !" -ForegroundColor Red
        return
    }

    Write-Host("==========================================") -ForegroundColor Cyan
    Write-Host("  PHASE 3 : INSTALLATION ET CONFIGURATION ROLE DHCP   ") -ForegroundColor Cyan
    Write-Host("==========================================") -ForegroundColor Cyan

    # 2. INSTALLATION DU RÔLE
    Write-Host "---- Verification du rôle DHCP ----" -ForegroundColor Cyan
    $Feature = Get-WindowsFeature -Name DHCP
    if($Feature.Installed){
        Write-Host "---- Le service DHCP Serveur est déjà installé ----" -ForegroundColor Green
        #$DHCPpool = Read-Host "Souhaitez vous installé des pools DHCP ? Y/N"
    }
    else {
        Write-Host "---- Installation du service DHCP Server ----" -ForegroundColor Cyan
        # Ajout de -IncludeManagementTools pour s'assurer d'avoir les commandes PowerShell DHCP
        Install-WindowsFeature -Name DHCP -IncludeManagementTools | Out-Null

        Write-Host "---- Verification du service ----" -ForegroundColor Cyan
        if((Get-WindowsFeature -Name DHCP).Installed){
            Write-Host "---- Le service DHCP Serveur s'est bien installé ----" -ForegroundColor Cyan
            
            Write-Host "---- Configuration initiale du service DHCP ----" -ForegroundColor Cyan
            # Création des groupes de sécurité requis par Windows
            Add-DhcpServerSecurityGroup | Out-Null
            # Configuration du démarrage automatique et lancement du service
            Set-Service -Name dhcpserver -StartupType Automatic
            Restart-Service -Name dhcpserver    
        }
        else{
            Write-Host "---- Une erreur s'est déroulé lors de l'installation ----" -ForegroundColor Red
            return
        }
        #DHCPpool = Read-Host "Souhaitez vous installé des pools DHCP ? "
    }

    # 3. AUTORISATION ACTIVE DIRECTORY (Si applicable)
    $IsDomainMember = (Get-CimInstance Win32_ComputerSystem).PartOfDomain
    if ($IsDomainMember) {
        Write-Host "---- Détection d'un domaine Active Directory ----" -ForegroundColor Cyan
        Write-Host "Autorisation du serveur DHCP dans le domaine..." -ForegroundColor Cyan
        # Cette commande nécessite que l'utilisateur qui lance le script soit Admin du domaine
        Add-DhcpServerInDC | Out-Null
        Write-Host "Le serveur a été autorisé dans l'Active Directory." -ForegroundColor Green
    }

    # 4. CONFIGURATION DE L'ÉTENDUE (POOL)
    while($DHCPpool -eq $True){
    $DHCPpool = Read-Host "Souhaitez vous installé des pools DHCP ? Y/N"

    switch ($DHCPpool) {
        "Y" {
            Write-Host "---- Creation de pool DHCP ----" -ForegroundColor Cyan
            # Ajout de .Trim() pour nettoyer les espaces accidentels de la saisie
            $name = (Read-Host "Quel nom souhaitez-vous donner à votre pool ?").Trim()
            $IpNet = (Read-Host "Quelle IP réseau (ScopeId) souhaitez-vous donner à votre pool ?").Trim()
            $IpMask = (Read-Host "Quel Masque de sous-réseau souhaitez-vous donner à votre pool ?").Trim()
            $IpStart = (Read-Host "Quelle est la première IP distribuable du pool ?").Trim()
            $IpEnd = (Read-Host "Quelle est la dernière IP distribuable de votre pool ?").Trim()
            $IpGateway = (Read-Host "Quelle est l'IP de la passerelle (routeur) ?").Trim()
            $IpDns = (Read-Host "Quelle est l'IP du serveur DNS ?").Trim()

            Write-Host("-- ScopeID : SubnetMask : Name : StartRange : EndRange : Passerelle : DNS --") -ForegroundColor Cyan
            Write-Host("-- $IpNet : $IpMask : $name : $IpStart : $IpEnd : $IpGateway : $IpDns --") -ForegroundColor Cyan

            $VerifPool = Read-Host("Confirmez vous votre choix ? Y/N")

            if($VerifPool -eq "Y"){
                Write-Host "---- Verification avant Creation ----" -ForegroundColor Cyan

                # Le -ErrorAction SilentlyContinue évite du texte rouge si aucun pool n'existe encore
                $existingScopes = Get-DhcpServerv4Scope -ErrorAction SilentlyContinue
                
                if($existingScopes | Where-Object {$_.Name -eq $name}){
                    Write-Host "Un pool avec le nom $name existe déjà" -ForegroundColor Yellow

                }elseif(Get-DHCPServerv4Scope | Where-Object {$_.ScopeID -eq $IpNet}){
                    Write-Host "Un pool avec le réseau $IpNet existe deja !" -ForegroundColor Yellow

                }else{
                    try {
                        Write-Host "---- Creation du pool en cours... ----" -ForegroundColor Cyan
            
                        # On ajoute -ErrorAction Stop pour capturer l'erreur proprement
                        Add-DhcpServerv4Scope -Name $name -StartRange $IpStart -EndRange $IpEnd -SubnetMask $IpMask -State Active -ErrorAction Stop
            
                        Write-Host "---- Configuration de la passerelle... ----" -ForegroundColor Cyan
                        Set-DhcpServerv4OptionValue -ScopeId $IpNet -OptionId 3 -Value $IpGateway -ErrorAction Stop
            
                        Write-Host "---- Forçage de l'IP DNS (sans validation réseau)... ----" -ForegroundColor Cyan
                        # Pour netsh, on redirige les erreurs vers le succès pour éviter le rouge, et on gère nous-mêmes
                        $netshResult = netsh dhcp server scope $IpNet set optionvalue 6 IPADDRESS $IpDns 2>&1
                        if ($LASTEXITCODE -ne 0) {
                            throw "Erreur Netsh DNS" # Cela force le passage au bloc Catch
                        }
            
                        Write-Host "`n===============================================" -ForegroundColor Green
                        Write-Host "✅ SUCCÈS : Le pool a été créé et configuré !" -ForegroundColor Green
                        Write-Host "===============================================" -ForegroundColor Green
                    }
                    catch {
                        # C'est ici qu'on arrive si N'IMPORTE QUELLE commande du 'try' échoue
                        Write-Host "`n===============================================" -ForegroundColor Red
                        Write-Host "❌ ÉCHEC : Impossible de créer ou configurer le pool." -ForegroundColor Red
                        Write-Host "Vérifiez que :" -ForegroundColor Yellow
                        Write-Host "- L'IP de fin n'est pas une adresse de Broadcast" -ForegroundColor Yellow
                        Write-Host "- Les IPs font bien partie du sous-réseau calculé avec le masque" -ForegroundColor Yellow
                        Write-Host "===============================================" -ForegroundColor Red
            
                        # Optionnel : Affiche l'erreur technique d'origine mais en gris clair, discret
                        Write-Host "Détail technique : $($_.Exception.Message)" -ForegroundColor Gray
                    }
                }
            }elseif($VerifPool -eq "N"){
                Write-Host"---- Annulation de la création ----" -ForegroundColor Yellow
            }
        }
        "N" {
            Write-Host "---- Fin de la configuration ----" -ForegroundColor Green
            break
        }

        Default {
            Write-Host"---- Erreur de saisie ----" -ForegroundColor Red
            Write-Host"Veuillez choisir Y/N seulement"
        }
    }
    }