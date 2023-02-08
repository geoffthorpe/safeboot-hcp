# The minimum Makefile required to keep debuild happy

default: build

MYPREFIX := $(DESTDIR)/hcp/enrollsvc
FILE_LIST := $(shell ls *.py *.sh)
FILE_LIST2 := $(shell ls genprogs/*)

build:
	@echo "nothing to do for 'build'"

install:
	@$(INSTALL) -d $(MYPREFIX) $(MYPREFIX)/genprogs
	@$(INSTALL) -m 755 $(FILE_LIST) $(MYPREFIX)
	@$(INSTALL) -m 755 $(FILE_LIST2) $(MYPREFIX)/genprogs
	@echo "installed to $(MYPREFIX)"
