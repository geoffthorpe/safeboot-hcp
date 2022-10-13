# Some templates and other routines to reduce duplication
include $(HCP_SRC)/preproc.Makefile

# A "base platform" Docker image is created, and used as a basis for deriving
# two kinds of images;
# - a "builder" container image, containing tool-chains and other extras to
#   facilitate the building of submodules.
# - application container images, providing the different services, side-cars,
#   and utilities that constitue HCP.
include $(HCP_SRC)/base/Makefile

# A "builder" docker image is created that can host building of submodule code
# (rather than building directly in the host environment, which can be
# undesirable, unreliable, or impossible for many reasons).
include $(HCP_SRC)/builder/Makefile

# External code-bases with their own build systems, etc.
include $(HCP_SRC)/ext/tpmware.Makefile
include $(HCP_SRC)/ext/heimdal.Makefile
include $(HCP_SRC)/ext/safeboot.Makefile

# Internal code-bases
include $(HCP_SRC)/common/Makefile
include $(HCP_SRC)/xtra/Makefile
include $(HCP_SRC)/tools/Makefile
include $(HCP_SRC)/enrollsvc/Makefile
include $(HCP_SRC)/attestsvc/Makefile
include $(HCP_SRC)/swtpmsvc/Makefile
include $(HCP_SRC)/policysvc/Makefile
include $(HCP_SRC)/kdcsvc/Makefile
include $(HCP_SRC)/sshsvc/Makefile
include $(HCP_SRC)/caboodle/Makefile

# Build the desired container images
include $(HCP_SRC)/apps/Makefile

# Produce usable (but test, non-production) credentials
include $(HCP_SRC)/testcreds.Makefile
