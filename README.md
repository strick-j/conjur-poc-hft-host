# conjur-poc-hft-host
Script written to add hosts using Hostfactory Tokens to the Conjur POC Environment

# Execution
Intended to be ran after deploying a Conjur POC Environment using the script located at https://github.com/strick-j/conjur-poc
1. Clone the repository
2. Copy the script to your conjur-cli docker container and place withing the /policy folder (e.g. docker cp add-hfthost.sh conjur-cli:/policy/add-hfthost.sh)
3. Execute the script (e.g. ./add-hfthost.sh)

# Notes
Script will prompt user to decide if the new host needs access to CI or CD secrets within the Conjur POC Environment. Based on user input a new Hostfactory Token and Identity will be generated. Lastly, the script will verify the new Identity is able to access secrets as chosen in the initial prompt.
