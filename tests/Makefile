HCP_TESTS_SRC := $(TOP)/tests

CREATED_CABOODLE := $(HCP_caboodle_TFILE)
CREATED_TOOLS := $(HCP_tools_TFILE)
CREATED_SERVICES := $(foreach i,enroll attest swtpm policy,$(HCP_$isvc_TFILE))
CREATED_TESTCREDS := $(HCP_TESTCREDS_DONE)

define test_case
$(eval name := $(strip $1))
$(eval prog := $(name)$(strip $2))
$(eval bashcmd := export HCP_TEST_PATH="$(HCP_TESTS_SRC)/$(prog)" && \
	"$(HCP_TESTS_SRC)/wrapper.sh")
test_$(name): $(ALL)
test_$(name):
	$Qecho "Starting '$$@'"
	$Qbash -c '$(bashcmd)'
	$Qecho "Successful completion of '$$@'"
$(eval TESTS += test_$(name))
endef

$(eval $(call test_case,caboodle_alone_basic,.sh))
$(eval $(call test_case,services_basic,.py))
$(eval $(call test_case,unit.sh))

tests: $(TESTS)
