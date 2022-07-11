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

# Define an API for "ext_builder" packages, which let you implement
# "configure", "build", "install" rules for a source tree, and have all the
# Makefile and docker hooks set up for it. ext-{tpmware,heimdal,safeboot,xtra}
# all use this. One restriction is that they must install/run in distinct,
# non-overlapping paths, due to how their assets are installed into mounted
# volumes and the resulting "packages" are basically tarballs of that volume.
include $(HCP_SRC)/ext/Makefile

# Produce a tarball of xtras, like our parameter-expansion tool
include $(HCP_SRC)/xtra/Makefile

# Produce HCP applications (code tarballs and container images)
include $(HCP_SRC)/apps/Makefile

# Produce usable (but test, non-production) credentials
include $(HCP_SRC)/testcreds.Makefile
