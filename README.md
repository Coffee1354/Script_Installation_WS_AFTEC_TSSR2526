**Copier/Coller ce bloc dans powershell en tant qu'admin**

```powershell
# Étape A : Téléchargement et extraction des sources
Invoke-WebRequest -Uri "[https://github.com/Coffee1354/Script_Installation_WS_AFTEC_TSSR2526/archive/refs/heads/main.zip](https://github.com/Coffee1354/Script_Installation_WS_AFTEC_TSSR2526/archive/refs/heads/main.zip)" -OutFile "$HOME\Desktop\scripts.zip"
Expand-Archive -Path "$HOME\Desktop\scripts.zip" -DestinationPath "$HOME\Desktop\Provisioning" -Force
# Étape B : Correction automatique de l'encodage pour la console Windows
Get-ChildItem -Path "$HOME\Desktop\Provisioning\Script_Installation_WS_AFTEC_TSSR2526-main\*.ps1" | ForEach-Object {
    $Contenu = Get-Content $_.FullName -Encoding UTF8
    Set-Content $_.FullName -Value $Contenu -Encoding UTF8
}
# Étape C : Déplacement dans le dossier pour exécution
cd "$HOME\Desktop\Provisioning\Script_Installation_WS_AFTEC_TSSR2526-main\"

----------------------------------------------------------------------------------------------------------------------------------------------------------------------
##  ÉTAPE 0 : Préparation de la VM et Transfert (CRUCIAL)

**ATTENTION : Ne lancez AUCUN script tant que la VM est connectée au réseau physique de l'entreprise. Le script installera un serveur DHCP qui pourrait couper l'accès Internet de vos collègues.**

Pour initialiser le serveur en toute sécurité, suivez scrupuleusement cette procédure :

1. **Connexion (Bridge) :** Créez et installez votre machine virtuelle Windows Server en laissant la carte réseau en mode **Bridge** (Pont) pour avoir accès à Internet et au réseau local.
2. **Transfert des fichiers :** Copiez l'intégralité du dossier contenant ces scripts sur le Bureau de la VM.
3. ** ISOLATION DU RÉSEAU (Étape vitale) :** Retournez dans l'interface de votre hyperviseur (Proxmox, VMware, etc.) et **modifiez la carte réseau** de la VM. Basculez-la sur un réseau totalement isolé (ex: `vmbr1` sans port physique associé, ou un réseau privé virtuel).
4. **Go !** Une fois la VM isolée dans sa bulle, vous pouvez lancer le premier script.

---

#  Déploiement Automatisé Windows Server (Zero-Touch Provisioning)

Ce projet contient une suite de scripts PowerShell conçue pour initialiser et configurer de A à Z un serveur Windows vierge (idéalement sur machine virtuelle / Proxmox) afin d'en faire un Contrôleur de Domaine complet avec les services DNS et DHCP.

##  Prérequis Importants
* **Console Administrateur :** Tous les scripts doivent impérativement être lancés dans une console PowerShell ouverte en tant qu'Administrateur.
* **Stratégie d'exécution :** Assurez-vous que l'exécution des scripts est autorisée sur le serveur avec la commande : `Set-ExecutionPolicy RemoteSigned -Force`
* **Environnement :** Le serveur doit posséder une seule carte réseau active et connectée (Status "Up").

---

##  Ordre d'exécution des scripts

L'ordre d'exécution est strictement séquentiel en raison des redémarrages nécessaires et des dépendances entre les services.

### 1️ Étape 1 : Les Fondations
**Script :** `WindowsServerConf.ps1`
* **Action :** Configure l'IP statique, le masque, la passerelle, pointe le DNS primaire sur la boucle locale (`127.0.0.1`), et renomme le serveur.
* **Important :** Le script demandera un **redémarrage obligatoire** à la fin pour valider le nouveau nom d'hôte (Hostname).

### 2️ Étape 2 : Le Cœur de l'Identité (AD DS)
**Script :** `WindowsInstallAD.ps1`
* **Action :** Installe les binaires Active Directory et promeut le serveur en Contrôleur de Domaine. Le service DNS est installé automatiquement lors de cette étape.
* **Important :** Le serveur **redémarrera tout seul** à la fin de l'installation. 
*  **ATTENTION CHANGEMENT DE COMPTE :** Au redémarrage, le compte Administrateur local n'existe plus. Vous devez vous connecter avec le compte du domaine (ex: `NOMDUDOMAINE\Administrateur`).

### 3️ Étape 3 : Le Service Réseau (DHCP)
**Script :** `InstallServiceDHCP.ps1`
* **Action :** Installe le rôle serveur DHCP et lance l'assistant interactif pour créer et configurer un ou plusieurs pools (plages d'adresses, passerelle, DNS).
* **Important :** Le DHCP est maintenant installé, mais il est en attente d'autorisation par l'Active Directory pour commencer à distribuer des IP.

### 4️ Étape 4 : La Configuration et le Peuplement
**Script :** `WindowsServerConfigAD_DNS.ps1`
* **Action :** * Lance l'assistant de création d'arborescence (Unités d'Organisation).
  * Lance l'assistant de création d'utilisateurs standards (format `p.nom`).
  * Permet la création d'alias DNS (CNAME) interactifs (ex: *intranet*).
  * **Autorise officiellement le serveur DHCP** dans l'Active Directory.
* **Résultat :** L'infrastructure est 100% opérationnelle et prête à l'emploi.

---

##  Dépannage courant
* **Erreur de création DHCP (WIN32 87) :** Assurez-vous que l'adresse de fin du pool DHCP n'est pas l'adresse de Broadcast (diffusion) de votre sous-réseau.
* **Erreur d'accès refusé :** Vérifiez que vous êtes bien connecté avec le compte Administrateur du *domaine* après l'Étape 2, et non un compte local résiduel.
