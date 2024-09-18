#!/bin/bash

# Définir le répertoire de travail (où se trouvent le noyau et l'initramfs)
BUILD_DIR=$(pwd)
KERNEL_DIR="$BUILD_DIR/linux-6.10.10"
INITRAMFS_FILE="$BUILD_DIR/initramfs.cpio.gz"

# Vérifier que les fichiers nécessaires existent
if [ ! -f "$KERNEL_DIR/arch/x86/boot/bzImage" ]; then
    echo "Erreur : le fichier bzImage (noyau) est introuvable."
    exit 1
fi

if [ ! -f "$INITRAMFS_FILE" ]; then
    echo "Erreur : le fichier initramfs.cpio.gz est introuvable."
    exit 1
fi

# Lancer QEMU avec le noyau compilé et l'initramfs
echo "Démarrage de QEMU avec le noyau et initramfs..."
qemu-system-x86_64 -kernel "$KERNEL_DIR/arch/x86/boot/bzImage" \
                   -initrd "$INITRAMFS_FILE" \
                   -append "root=/dev/ram0 console=ttyS0" -nographic
