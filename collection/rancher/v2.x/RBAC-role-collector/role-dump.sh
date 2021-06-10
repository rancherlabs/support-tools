#! /bin/bash

# Troubleshooting Bash settings in case of unexpected failure
# set -o errexit  # Set to exit on error.  Do not enable this unless running against upstream Rancher cluster
# set -o xtrace   # Set to output every line Bash runs as it runs the script

# Unset variables used in the script to be safe
unset crd cluster wd dir file role i

_declare_variables () {
  # Role types to collect
  crd=(\
    clusterroletemplatebindings \
    globalrolebindings \
    globalroles \
    projectroletemplatebindings \
    roletemplates.management.cattle.io \
    roletemplatebindings \
    clusterrolebindings \
    clusterroles \
    roletemplates.rancher.cattle.io \
    rolebindings \
    roles
  )

  # Store filename friendly cluster name
  cluster=$(_slugify "$(kubectl config current-context)") # 
  
  # Working directory 
  wd="$cluster"_role-bindings_$(date -I)
}


# Slugify strings (replace any special characters with `-`)
_slugify () {
  echo "$1" |
  iconv -t ascii//TRANSLIT |
  sed -r s/[^a-zA-Z0-9]+/-/g |
  sed -r s/^-+\|-+$//g |
  tr A-Z a-z
}

# Generate a list (`rolebindings.list`) of all the role bindings and template bindings in the cluster
_list_rolebindings () {
  for i in ${crd[*]} ; do
    printf "\n\n# $i\n" >> "$wd"/rolebindings.list 
    kubectl get $i -A >> "$wd"/rolebindings.list
  done
}

# Generate a JSON per role type containing all the rolebindings
_get_rolebindings () {
  for i in ${crd[*]} ; do
    file=$(_slugify "$i")
    kubectl get "$i" -A -o json > "$wd"/"$file".json
  done
}

# Archive and compress the report
_tarball_wd () {
tar -czvf "$wd".tar.gz "$wd"
}


# Runs all the things
main () {
  _declare_variables
  # Create working directory
  if [[ ! -e "$wd" ]]; then
    mkdir "$wd"
  fi
  _list_rolebindings
  _get_rolebindings
  _tarball_wd
}

# ACTUALLY run all the things
main

