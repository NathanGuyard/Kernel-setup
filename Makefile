obj-m += rootkit_module.o

all:
	# Utiliser les headers dans /usr/src/linux
	make -C /usr/src/linux M=$(PWD) modules

clean:
	make -C /usr/src/linux M=$(PWD) clean
