#!/bin/bash

set -e

# Vérifier si les commandes nécessaires sont installées
command_exists() {
  command -v "$1" >/dev/null 2>&1
}

REQUIRED_COMMANDS="truncate parted losetup mkfs.ext4 mount docker grub-install qemu-system-x86_64"
for cmd in $REQUIRED_COMMANDS; do
  if ! command_exists $cmd; then
    echo "Erreur : La commande '$cmd' est requise mais n'est pas installée."
    exit 1
  fi
done

# Créer une image disque de 450MB
truncate -s 450M disk.img

# Créer une table de partition amorçable en mode BIOS
parted -s ./disk.img mktable msdos

# Ajouter une partition primaire ext4 utilisant tout l'espace disponible
parted -s ./disk.img mkpart primary ext4 1 "100%"

# Marquer la partition comme amorçable
parted -s ./disk.img set 1 boot on

# Configurer un périphérique loop avec détection de partition et récupérer son nom
LOOP_DEVICE=$(sudo losetup -P --show -f disk.img)
echo "Périphérique loop utilisé : $LOOP_DEVICE"

# Attendre que les partitions soient prêtes
sleep 1

# Déterminer le nom de la partition
PARTITION="${LOOP_DEVICE}p1"
if [ ! -b "$PARTITION" ]; then
  # Essayer sans 'p'
  PARTITION="${LOOP_DEVICE}1"
fi
echo "Partition utilisée : $PARTITION"

# Formater la première partition en ext4
sudo mkfs.ext4 "$PARTITION"

# Créer un répertoire de travail
mkdir -p /tmp/my-rootfs

# Monter la partition
sudo mount "$PARTITION" /tmp/my-rootfs

# Créer un script pour exécuter les commandes dans le conteneur Docker
cat << 'EOF' > /tmp/docker-install.sh
#!/bin/sh

# Mettre à jour les dépôts et installer les paquets nécessaires
apk update
apk add openrc
apk add util-linux
apk add build-base

# Configurer l'accès au terminal série via QEMU
ln -s agetty /etc/init.d/agetty.ttyS0
echo ttyS0 > /etc/securetty
rc-update add agetty.ttyS0 default
rc-update add root default

# Définir le mot de passe root (changez 'root' par le mot de passe désiré)
echo "root:root" | chpasswd

# Monter les systèmes de fichiers pseudo
rc-update add devfs boot
rc-update add procfs boot
rc-update add sysfs boot

# Copier les fichiers vers /my-rootfs
for d in bin etc lib root sbin usr; do tar c "/$d" | tar x -C /my-rootfs; done

# Créer des répertoires spéciaux
for dir in dev proc run sys var; do mkdir /my-rootfs/${dir}; done
EOF

chmod +x /tmp/docker-install.sh

# Exécuter le conteneur Docker et le script
docker run --rm -v /tmp/my-rootfs:/my-rootfs -v /tmp/docker-install.sh:/docker-install.sh alpine /docker-install.sh

# De retour sur le système hôte
# Copier le noyau compilé dans le répertoire boot
if [ ! -f linux-6.10.10/arch/x86/boot/bzImage ]; then
  echo "Erreur : Le noyau bzImage n'a pas été trouvé à 'linux-6.10.10/arch/x86/boot/bzImage'."
  exit 1
fi

sudo mkdir -p /tmp/my-rootfs/boot/grub
sudo cp linux-6.10.10/arch/x86/boot/bzImage /tmp/my-rootfs/boot/vmlinuz

# Créer le fichier grub.cfg
cat << 'EOF' | sudo tee /tmp/my-rootfs/boot/grub/grub.cfg
serial
terminal_input serial
terminal_output serial
set root=(hd0,1)
menuentry "Linux2600" {
 linux /boot/vmlinuz root=/dev/sda1 console=ttyS0
}
EOF

# Installer Grub pour le démarrage BIOS
sudo grub-install --target=i386-pc --boot-directory=/tmp/my-rootfs/boot --force $LOOP_DEVICE

# Démonter la partition
sudo umount /tmp/my-rootfs

# Détacher le périphérique loop
sudo losetup -d $LOOP_DEVICE

# Exécuter QEMU sur l'image disque
qemu-system-x86_64 -hda disk.img -nographic
