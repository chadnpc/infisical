
@{
  ModuleName    = 'infisical'
  ModuleVersion = '0.1.0'
  ReleaseNotes  = '# Release Notes

- Version_<ModuleVersion>
- Functions ...
- Optimizations
'
  HelpMessage   = @"
      Infisical CLI Engine
      ====================

    Infisical is the open-source secret management platform. This PowerShell 
    module provides a CLI engine and a programmatic SDK to manage secrets, 
    certificates, and KMS keys.

    Quick Start (CLI):
    infisical login --method universal-auth
    infisical init
    infisical secrets list

    Quick Start (SDK):
    $client = [Infisical]::GetClient($url, $token)
    $secrets = $client.Secrets().ListAsync($opts).GetAwaiter().GetResult()

    Available CLI Commands:
    - login    : Authenticate with Infisical (supports universal-auth)
    - init     : Initialize Infisical project in the current directory
    - secrets  : Manage secrets (subcommands: list, get, set, delete)
    - run      : Execute a command with secrets injected as environment variables
    - export   : Export secrets to various formats (dotenv, json, yaml, csv)
    - user     : View user information (e.g., 'user get token')
    - events   : Retrieve project audit events
    - reset    : Clear local Infisical configuration (.infisical.json)
    - version  : Show current module version
    - upgrade  : Update the Infisical module
    - help     : Display this help message

    Available Class Methods ([Infisical]):
    - Run($args)             : Main entry point for CLI execution
    - GetClient($url, $token): Initialize a programmatic SDK client
    - GetHelp()              : Retrieve this help text
    - WriteBanner()          : Display the ASCII banner
    - GetProjectConfig()     : Read local .infisical.json
    - SetProjectConfig($cfg) : Update local .infisical.json

    SDK Entry Points:
    - [Infisical]::Auth()
    - [Infisical]::Secrets()
    - [Infisical]::Pki()
    - [Infisical]::Identities()
    - [Infisical]::Kms()

    For more information, visit: https://infisical.com/docs/cli
"@
  BannerAscii   = @"
⠀⠀⠀⠀⠀⠀⠀⣠⣴⣶⣶⣦⣤⡀⠀⠀⢀⣤⣶⣶⣶⣦⣄⠀⠀⠀⠀⠀⠀⠀
⠀⠀⠀⠀⠀⢀⣾⣿⠟⠋⠉⠛⢿⣿⣦⣴⣿⡿⠛⠉⠙⠻⣿⣷⡀⠀⠀⠀⠀⠀
⠀⠀⠀⠀⠀⢸⣿⣏⠀⠀⠀⠀⠀⣹⣿⣿⣏⠀⠀⠀⠀⠀⣽⣿⡇⠀⠀⠀⠀⠀
⠀⠀⠀⠀⠀⠈⢿⣿⣦⣄⣠⣤⣾⣿⠟⢻⣿⣷⣤⣀⣠⣴⣿⡿⠁⠀⠀⠀⠀⠀
⠀⠀⠀⠀⠀⠀⠀⠙⠻⠿⠿⠟⠛⠁⠀⠀⠈⠛⠻⠿⠿⠛⠋⠀⠀⠀⠀⠀⠀⠀
"@
}
