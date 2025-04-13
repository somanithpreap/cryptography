#!/usr/bin/env bash

pubKey=""

programName=$0
error="  >>> \e[1;31mERROR:\e[0m"

getPubKey() {
    id="$1"
    if [[ -z $id ]]; then
        echo -e "$error recipient's ID is NOT specified."
        exit 1
    elif [[ -z "$(gpg --list-keys | grep $id)" ]]; then  # Check if recipient's key is in local list
        failed_msg="gpg: keyserver receive failed: No data"
        openpgp=$(gpg --keyserver hkps://keys.openpgp.org --recv-keys $id)
        ubuntu_ks=$(gpg --keyserver hkps://keyserver.ubuntu.com --recv-keys $id)

        if [[ $openpgp == $failed_msg && $ubuntu_ks == $failed_msg ]]; then
            echo -e "$error no key found for specified ID"
            exit 1
        fi

        #Display the output for the key retrieval
        if [[ $openpgp == $failed_msg ]]; then
            echo $ubuntu_ks
        else
            echo $openpgp
        fi
    fi

    IFS='' read -r -d '' pubKey < <(gpg --export --armor $1)
    if [[ -z $pubKey ]]; then
        echo -e "\n$error recipient's public key NOT found."
        exit 1
    else
        echo -e "\n  \e[0;32mRecipient's public key found!\e[0m"
    fi
}

displayUsage() {
    echo -e "\n  \e[1;35mFile Encryptor Program Usage\e[0m\n"
    echo -e "  \e[1mShow Usage:\e[0m"
    echo -e "      \e[2m$programName\e[0m -h"
    echo -e "      \e[2m$programName\e[0m --help\n"
    echo -e "  \e[1mEncryption:\e[0m"
    echo -e "      \e[2m$programName\e[0m -e [\e[3mfilename\e[0m] -id [\e[3mrecipient_GPG_ID\e[0m]"
    echo -e "      \e[2m$programName\e[0m --encrypt [\e[3mfilename\e[0m] -id [\e[3mrecipient_GPG_ID\e[0m]\n"
    echo -e "  \e[1mDecryption:\e[0m"
    echo -e "      \e[2m$programName\e[0m -d [\e[3mfilename\e[0m]"
    echo -e "      \e[2m$programName\e[0m --decrypt [\e[3mfilename\e[0m]\n"
}

operation="$1"
filename="$2"
idOption="$3"
id="$4"

if [[ -z $operation ]]; then
    echo -e "$error no operation specified"
    displayUsage
elif [[ $operation == "-h" || $operation == "--help" ]]; then
    displayUsage
elif [[ $operation == "-e" || $operation == "--encrypt" ]]; then
    if [[ -z $filename ]]; then
        echo -e "$error no file specified."
        displayUsage
        exit 1
    elif [[ -e $filename ]]; then  # Check if file exists
        # Check for -k option
        if [[ -z $idOption ]]; then
            echo -e "$error expected option \"-id\"."
            displayUsage
            exit 1
        elif [[ $idOption == "-id" ]]; then
            getPubKey $id
        else
            echo -e "$error invalid option \"$idOption\""
            displayUsage
            exit 1
        fi
    else
        echo -e "$error file \"$filename\" not found."
        displayUsage
        exit 1
    fi

    secret=$(openssl rand -hex 16)
    iv=$(openssl rand -hex 16)

    openssl enc -aes-128-ctr -in "$filename" -out ".$filename.enc" -K "$secret" -iv "$iv"  # Encrypt the file
    echo "$secret" | gpg --encrypt --recipient "$id" --armor > ".secret.gpg" # Encrypt the AES key
    echo "$iv" | gpg --encrypt --recipient "$id" --armor > ".iv.gpg" # Encrypt the IV
    cat ".secret.gpg" ".iv.gpg" ".$filename.enc" > ".$filename-enc"   # Combine encrypted key, IV, and file
    gpg --yes --sign --armor --output "$filename.enc" ".$filename-enc"  # Generate an attched digital signature file
    rm .*".gpg" ".$filename"*    # Delete temporary files

    echo -e "  \e[0;32mEncrypted file:\e[0m \e[1m$filename.enc\e[0m\n"
elif [[ $operation == "-d" || $operation == "--decrypt" ]]; then
    if [[ -z $filename ]]; then
        echo -e "$error no file specified."
        displayUsage
        exit 1
    elif [[ !(-e $filename) ]]; then
        echo -e "$error file \"$filename\" not found."
        displayUsage
        exit 1
    fi

    gpg --yes --output ".$filename" --decrypt "$filename"   # Verify the attached signature file and extract the encrypted data
    awk '/^-----BEGIN PGP MESSAGE-----$/{i++}{print > ".part_" i ".pgp"}' ".$filename"  # Split the encrypted data into separate parts
    awk '/^-----END PGP MESSAGE-----$/ {found=1; next} found' ".part_2.pgp" > ".$filename-raw"  # Extract the encrypted file data
    sed '/^-----END PGP MESSAGE-----$/q' ".part_2.pgp" > ".part_2_clean.pgp"    # Remove the encrypted file data from the encrypted IV

    original=$(basename "$filename" .enc)
    gpg --yes --output ".$original-secret" --decrypt ".part_1.pgp" # Decrypt the encrypted AES key
    gpg --yes --output ".$original-iv" --decrypt ".part_2_clean.pgp"   # Decrypt the encrypted IV
    openssl enc -d -aes-128-ctr -in ".$filename-raw" -out "$original" -K $(cat ".$original-secret") -iv $(cat ".$original-iv")   # Decrypt the encrypted file
    rm .*".pgp" ".$original"*   # Delete temporary files
    
    truncate -s -2 "$original"  # Remove garbage data produced by the encryption process
    echo -ne '\x0A' >> "$original"    # Replace last NULL byte with LF

    echo -e "  \e[0;32mDecrypted file:\e[0m \e[1m$original\e[0m\n"
else
    echo -e "$error operation \"$operation\" not supported."
    displayUsage
    exit 1
fi
