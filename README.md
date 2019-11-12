## Mise en place d'une infrastructure vmWare de type 'Nested Virtualization'
Les valeurs entre crochets sont les valeurs utilisées lors de mon installation.
La machine servant à l'installation sera appelé poste d'installation.
Il est conseillé de connecter en ethernet le poste d'installation sur le switch du cluster NUC.
Mon poste d'installation est un ubuntu-18.04.3-desktop-amd64.

### Images ISO nécessaires
* Hyperviseur ESXi [VMware-VMvisor-Installer-6.5.0.update02-8294253.x86_64.iso]
* vCenter / vSphere [VMware-VCSA-all-6.7.0-10244745.iso]

### Configuration du switch Cisco
* Modèle : RV134W, doc : RV132W_RV134W.pdf
* Le poste d'installation est relié en ethernet sur le switch.
* La connexion Internet est configurée sur l'entrée WAN du switch.
* Adresses IP statiques pour les NUC
  * IP statiques : 192.168.1.[10-99]
  * Pinst 192.168.1.10 ac:87:a3:23:01:b2 (Poste d'installation)
  * Nuc1  192.168.1.11 b8:ae:ed:7c:3a:87
  * Nuc2  192.168.1.12 f4:4d:30:6a:8c:68
  * Nuc3  192.168.1.13 b8:ae:ed:7d:9e:80
  * Nuc4  192.168.1.14 f4:4d:30:69:68:2c
'''
================
= Nuc3 == Nuc4 =
================
= Nuc1 == Nuc2 =
================
=    Switch    =
================
= Alimentation =
================
'''

### Installation des ESXi
* Créer une clé USB d'installation avec Rufus (sous Windows) à partir d'une image ISO VMvisor [VMware-VMvisor-Installer-6.5.0.update02-8294253.x86_64.iso]
* Installer les ESXi sur tous les NUCs disponibles
  * mot de passe root : (voir configuration.json)
  * NOTE : Ne pas retirer la prise de l'écran lors de l'installation car on doit redémarrer le NUC pour retrouver l'affichage (même après installation de l'ESXi)
* ATTENTION : Pour la création d'une VM via l'interface Web de l'ESXi, désactiver les effets graphiques peut corriger les problèmes d'affichage des propriétés de la VM :
  * Menu "root@192.x.x.x" > Settings > Décocher "Enable visual effects"

### Installation du vCenter
* Choisir l'ESXi qui hébergera le vCenter et noter son adresse IP
* Télécharger l'ISO du vCenter Service Appliance [VMware-VCSA-all-6.7.0-10244745.iso]
* Monter l'image sur le poste d'installation (Windows, Linux ou Mac) [Ubuntu 64 bits] et lancer l'installeur
   * mkdir /tmp/vcsa
   * sudo mount -o loop VMware-VCSA-all-6.7.0-10244745.iso /tmp/vcsa
   * cd /tmp/vcsa/vcsa-cli-installer/lin64/
* ATTENTION: Dans le fichier *embedded_vCSA_on_ESXi.json* tous les  mots de passe sont en clair !
  * Modifier les mots de passe du le fichier *embedded_vCSA_on_ESXi.json* et les reporter dans le fichier *configuration.json*
  * ./vcsa-deploy install --accept-eula --no-ssl-certificate-verification ./Files/embedded_vCSA_on_ESXi.json

### Installation de PowerCLI sur le poste d'installation
* PowerShell
'''
curl https://packages.microsoft.com/keys/microsoft.asc | sudo apt-key add -
curl https://packages.microsoft.com/config/ubuntu/16.04/prod.list | sudo tee /etc/apt/sources.list.d/microsoft.list
sudo apt-get update
sudo apt-get install -y powershell
'''
* PowerCLI
'''
Install-Module -Name VMware.PowerCLI -Scope CurrentUser
Update-Module -Name VMware.PowerCLI
'''

### Configuration 
