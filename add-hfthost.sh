#!/bin/bash

main(){
  gather_info 
}

# Global Variables
reset=`tput sgr0`
me=`basename "${0%.sh}"`

# Generic output functions
print_head(){
  local white=`tput setaf 7`
  echo ""
  echo "==========================================================================="
  echo "${white}$1${reset}"
  echo "==========================================================================="
  echo ""
}
print_info(){
  local white=`tput setaf 7`
  echo "${white}INFO: $1${reset}"
  echo "INFO: $1" >> ${me}.log
}
print_success(){
  local green=`tput setaf 2`
  echo "${green}SUCCESS: $1${reset}"
  echo "SUCCESS: $1" >> ${me}.log
}
print_error(){
  local red=`tput setaf 1`
  echo "${red}ERROR: $1${reset}"
  echo "ERROR: $1" >> ${me}.log
}
print_warning(){
  local yellow=`tput setaf 3`
  echo "${yellow}WARNING: $1${reset}"
  echo "WARNING: $1" >> ${me}.log
}
function menu(){
  PS3='Please select option 1 or option 2: '
  options=("CI Secrets" "CD Secrets")
  select opt in "${options[@]}"
  do
    case $opt in
      "CI Secrets")
        id=ci
        break
        ;;
      "CD Secrets")
        id=cd
        break
        ;;
    esac
  done
  echo $id
}
# Begin main functions
gather_info(){
print_head "Step 1: Gathering system information"
  touch ${me}.log
  # Determine which secrets system needs access to
  print_info "Which secrets does you system need access to?: "
  local id=$(menu)
  print_info "End system will have access to $id secrets"
  #print_success "Required information gathered"
  print_info "Verifying required directories are present..."
  local hfdir="./hostfactoryTokens"
  local iddir="./identity"
  if [[ -d "$hfdir" ]]; then
    print_info "$hfdir exists, moving on"
  else
    print_warning "$hfdir does not exist, creating now"
    mkdir $hfdir
    if [[ -d "$hfdir" ]]; then
      print_success "$hfdir created, moving on..."
    else
      print_error "$hfdir could not be created, exiting..."
      exit 1
    fi
  fi
  if [[ -d "$iddir" ]]; then
    print_info "$iddir exists, moving on"
  else
    print_warning "$iddir does not exist, creating now"
    mkdir $iddir
    if [[ -d "$iddir" ]]; then
      print_success "$iddir created, moving on..."
    else
      print_error "$iddir could not be created, exiting..."
      exit 1
    fi
  fi
  # Proceed to next function, pass on ci or cd
  print_success "Directory structure verified and system info gathered"
  generate_hft $id
}
generate_hft(){
  print_head "Step 2: Generating Host Factory Token for apps/$1"
  local append=$(date +%Y%m%d%H%M%S)
  local hostname=$(cat ~/.netrc | awk '/machine/ {print $2}')
  local hostname=${hostname%/authn}
  local conjurCert=$(cat ~/.conjurrc | awk '/cert_file:/ {print $2}')
  local conjurCert=$(sed -e 's/^"//' -e 's/"$//' <<<"$conjurCert")
  local api=$(cat ~/.netrc | grep password | awk '{print $2}')
  local account=$(cat ~/.conjurrc | grep account | awk '{print $2}')
  local login=$(cat ~/.netrc | grep login | awk '{print $2}')
  print_info "Generating host factory token for apps/${1}"
  print_info "Using login = $login"
  print_info "Using API Key = $api"
  local auth=$(curl -s --cacert $conjurCert -H "Content-Type: text/plain" -X POST -d "$api" $hostname/authn/$account/$login/authenticate)
  local auth_token=$(echo -n $auth | base64 | tr -d '\r\n')
  local hostfactory=$(curl --cacert $conjurCert -s -X POST --data-urlencode "host_factory=$account:host_factory:apps/$1" --data-urlencode "expiration=2065-08-04T22:27:20+00:00" -H "Authorization: Token token=\"$auth_token\"" $hostname/host_factory_tokens)
  print_info "This is the hostfactory token:"
  echo $hostfactory | jq .
  local hftpath=${id}_hostfactory_${append}
  print_info "Saving HF token for use in file /hostfactoryTokens/$hftpath"
  echo $hostfactory > hostfactoryTokens/$hftpath
  local id=$1 
  generate_identity $1 $hftpath
}
generate_identity(){
  print_head "Step 3: Generating identity for $systemvar"
  local hftoken=$1
  local hostname=$(cat ~/.netrc | awk '/machine/ {print $2}')
  local hostname=${hostname%/authn}
  local conjurCert=$(cat ~/.conjurrc | awk '/cert_file:/ {print $2}')
  local conjurCert=$(sed -e 's/^"//' -e 's/"$//' <<<"$conjurCert")
  local id="$hftoken-$(openssl rand -hex 2)"
  local token=$(cat hostfactoryTokens/"$2" | jq '.[0] | {token}' | awk '{print $2}' | tr -d '"\n\r')
  local newidentity=$(curl -X POST -s --cacert $conjurCert -H "Authorization: Token token=\"$token\"" --data-urlencode id=$id $hostname/host_factories/hosts)
  print_info "Hostfactory token: $token"
  print_info "New host name in Conjur: $id"
  print_info "New Identity:"
  echo $newidentity | jq .
  print_info "Outputing file to identity/${id}_identity"
  echo $newidentity > identity/"$id"_identity
  pull_secret $hftoken $id
}
pull_secret(){
  print_head "Step 4: Testing secret access based CI/CD choices"
  local conjurCert=$(cat ~/.conjurrc | awk '/cert_file:/ {print $2}')
  local conjurCert=$(sed -e 's/^"//' -e 's/"$//' <<<"$conjurCert")
  local account=$(cat ~/.conjurrc | awk '/account:/ {print $2}')
  local hostname=$(cat ~/.netrc | awk '/machine/ {print $2}')
  local hostname=${hostname%/authn}
  local systemname=$(cat identity/${2}_identity | jq -r '.id' | awk -F: '{print $NF}')
  local api_key=$(cat identity/${2}_identity | jq -r '.api_key')
  local api_key=$(sed -e 's/^"//' -e 's/"$//' <<<"$api_key")
  # Test access to CI Secret
  if [[ $1 == ci ]]; then
    print_info "Attempting to access CI Secret"
    local secret_name="apps/secrets/ci-variables/chef_secret"
    print_info "Pulling secret: $secret_name"
    print_info "Using Conjur system name: $2"
    print_info "Using API key: $api_key"
    local auth=$(curl -s --cacert $conjurCert -H "Content-Type: text/plain" -X POST -d "${api_key}" $hostname/authn/$account/host%2F$systemname/authenticate)
    local auth_token=$(echo -n $auth | base64 | tr -d '\r\n')
    local secret_retrieve=$(curl --cacert $conjurCert -s -X GET -H "Authorization: Token token=\"$auth_token\"" $hostname/secrets/$account/variable/$secret_name)
    echo ""
    print_success "Secret is: $secret_retrieve"
    echo ""
  fi
  # Test access to CD secrets 
  if [[ $1 == cd ]]; then
    print_info "Attempting to access CD Secret"
    local secret_name="apps/secrets/cd-variables/kubernetes_secret"
    print_info "Pulling secret: $secret_name"
    print_info "Using Conjur system name: $2"
    print_info "Using API key: $api_key"
    local auth=$(curl -s --cacert $conjurCert -H "Content-Type: text/plain" -X POST -d "${api_key}" $hostname/authn/$account/host%2F$systemname/authenticate)
    local auth_token=$(echo -n $auth | base64 | tr -d '\r\n')
    local secret_retrieve=$(curl --cacert $conjurCert -s -X GET -H "Authorization: Token token=\"$auth_token\"" $hostname/secrets/$account/variable/$secret_name)
    echo ""
    print_success "Secret is: $secret_retrieve"
    echo ""
  fi
}
main
