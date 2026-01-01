#!/bin/zsh

# Get the XML output from running the java_home command
xml_output=$(/usr/libexec/java_home --xml)

# Extract JVMHomePath values from XML using xmllint
JAVA_PATHS=($(echo "$xml_output" | xmllint --xpath '//array/dict/key[text()="JVMHomePath"]/following-sibling::string[1]/text()' -))

JENV_VERSIONS_DIR="/Users/O60774/.jenv/versions"

for JAVA_PATH in "${JAVA_PATHS[@]}"; do
  echo "Processing JAVA_PATH: $JAVA_PATH"

  # Check if the JAVA_PATH exists
  if [[ ! -d "$JAVA_PATH" ]]; then
    echo "Error: JAVA_PATH ($JAVA_PATH) does not exist or is not a directory."
    continue
  fi

  # Extract the Java version directory name after "JavaVirtualMachines"
  JAVA_VERSION_NAME=$(echo "$JAVA_PATH" | sed -n 's|.*/JavaVirtualMachines/\([^/]*\)/.*|\1|p')

  # Create JENV_VERSIONS_DIR if it does not exist
  if [[ ! -d "$JENV_VERSIONS_DIR" ]]; then
    mkdir -p "$JENV_VERSIONS_DIR"
    echo "Created directory: $JENV_VERSIONS_DIR"
  fi

  # Ensure target directory for jenv exists
  TARGET_DIR="$JENV_VERSIONS_DIR/$JAVA_VERSION_NAME"
  if [[ ! -d "$TARGET_DIR" ]]; then
    mkdir -p "$TARGET_DIR"
    echo "Created directory: $TARGET_DIR"
  fi

  # Add JAVA_PATH to jenv
  jenv add "$JAVA_PATH"

  # Verify if the addition was successful
  if [[ $? -eq 0 ]]; then
    echo "Successfully added JAVA_PATH ($JAVA_PATH) to jenv."
  else
    echo "Failed to add JAVA_PATH ($JAVA_PATH) to jenv."
  fi
done

#Verify jenv installation
printf "\n-> Verifying jenv installation\n"
jenv doctor

# List all Java versions managed by jenv
jenv versions

printf "\nChose the version (from above) to set as Global version: "
read globalVer

jenv global "$globalVer"

printf "\n-> Verifying by running 'java -version'"
java -version

printf "\n-> Verifying by running 'echo ${JAVA_HOME}. If you are running this first time them the JAVA_HOME will be empty"
echo $JAVA_HOME

# Enable the jenv plugins
printf "\n-> Enable the jenv plugin: export. Sets JAVA_HOME automatically (safe to run multiple times)"
jenv enable-plugin export

printf "\n-> Enable the jenv plugin: maven. Sets the JAVA_HOME environment variable for Maven builds to match the Java version selected by jenv (safe to run multiple times)"
jenv enable-plugin maven

printf "\n-> Verifying by running 'echo ${JAVA_HOME} after enabling jenv export plugin"
echo $JAVA_HOME

printf "\n\n👌 Awesome, all set.\n"