# The minimum Makefile required to keep debuild happy

default: build

MYPREFIX := $(DESTDIR)/hcp/sshsvc
FILE_LIST := $(shell ls *.py *.sh)

build:
	@echo "nothing to do for 'build'"

install:
	@$(INSTALL) -d $(MYPREFIX)
	@$(INSTALL) -m 755 $(FILE_LIST) $(MYPREFIX)
	@echo "installed to $(MYPREFIX)"
