# Some templates and other routines to reduce duplication
include $(HCP_SRC)/preproc.Makefile

# A "base platform" Docker image is created, and used as a basis for deriving
# two kinds of images;
# - a "builder" container image, containing tool-chains and other extras to
#   facilitate the building of submodules.
# - application container images, providing the different services, side-cars,
#   and utilities that constitue HCP.
include $(HCP_SRC)/base/Makefile

# A "debbuilder" docker image specifically for building debian packages from
# source.
include $(HCP_SRC)/debbuilder/Makefile

# A "builder" docker image for building a low-brow, "tarball"-style package.
include $(HCP_SRC)/builder/Makefile

# Build user-mode-linux support
include $(HCP_SRC)/uml/Makefile

# HCP app code
include $(HCP_SRC)/hcp/Makefile

# External code-bases
include $(HCP_SRC)/ext/tpmware-deb.Makefile
include $(HCP_SRC)/ext/tpmware.Makefile
include $(HCP_SRC)/ext/heimdal.Makefile
include $(HCP_SRC)/ext/safeboot.Makefile
include $(HCP_SRC)/ext/vde2.Makefile

# Build the desired container images
include $(HCP_SRC)/apps/Makefile

# Produce usable (but test, non-production) credentials
include $(HCP_SRC)/testcreds.Makefile
