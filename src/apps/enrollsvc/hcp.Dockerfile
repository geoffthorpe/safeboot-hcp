# We have constraints to support older Debian versions whose 'git' packages
# assume "master" as a default branch name and don't honor attempts to override
# that via the "defaultBranch" configuration setting. If more recent distro
# versions change their defaults (e.g. to "main"), we know that such versions
# will also honor this configuration setting to override such defaults. So in
# the interests of maximum interoperability we go with "master", whilst
# acknowledging that this goes against coding guidelines in many environments.
# If you have no such legacy distro constraints and wish to (or must) adhere to
# revised naming conventions, please alter this setting accordingly.
RUN git config --system init.defaultBranch master
