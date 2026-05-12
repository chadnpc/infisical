<h2>
<img align="right" width="120" height="120" alt="Icon" src=".github/logo.png" />
</h2>
<div align="Left">
  <a href="https://www.powershellgallery.com/packages/infisical"><b>infisical</b></a>
  <p>
    🔥 Blazingly fast PowerShell module to work with infisical.
    </br></br></br>
    <a href="https://github.com/chadnpc/infisical/actions/workflows/Build_on_windows.yaml">
    <img src="https://github.com/chadnpc/infisical/actions/workflows/Build_on_windows.yaml/badge.svg" alt="Build on Windows"/>
    </a>
    <a href="https://github.com/chadnpc/infisical/actions/workflows/Build_on_Mac.yaml">
    <img src="https://github.com/chadnpc/infisical/actions/workflows/Build_on_Mac.yaml/badge.svg" alt="Build on MacOS"/>
    </a>
    <a href="https://github.com/chadnpc/infisical/actions/workflows/Build_on_Linux.yaml">
    <img src="https://github.com/chadnpc/infisical/actions/workflows/Build_on_Linux.yaml/badge.svg" alt="Build on Linux"/>
    </a>
    <a href="https://www.powershellgallery.com/packages/infisical">
    <img src="https://img.shields.io/powershellgallery/dt/infisical.svg?style=flat&logo=powershell&color=blue" alt="PowerShell Gallery" title="PowerShell Gallery" />
    </a>
  </p>
</div>

**📦 Installation**

```PowerShell
# Install from PSGallery
Install-Module infisical -Scope CurrentUser
```

**🚀 Features**

- **Access Control**
   Fine-grained, identity-aware permissions for users and machines
- **Secret Delivery**
   Access and manage secrets (Create, Read, Update, Delete)
- **Public Key Infrastructure (PKI)**

## quick usage (*wip)

```powershell
# ... main class usage demo
# [InfisicalClient]::dosomething(...)
```

Full docs: [`./docs/README.md`.](./docs/README.md)

## 🛠️ dev setup (contributors)

```powershell
git clone https://github.com/chadnpc/infisical.git
cd infisical
```

Load environment variables first:

```PowerShell
#Requires -Modules clihelper.env
cp .env.example .env
# Edit .env with your credentials. You can get them from your [Twilio Console](https://console.twilio.com/).
Read-Env .env | Set-Env

# Import local module and run tests
Import-Module ./infisical.psm1 -Force; ./Test-Module.ps1 -SkipBuildOutput
```

## Try it in your terminal

One-liner install and launch:

```PowerShell
# todo: add a one liner install and lai=unch script
```

- cmdlet: `Invoke-infisicalCli` (aliases: `infisical`, `infisicalCli`).
 ex:

  ```powershell
  infisical GetApiUsageLimits
  ```

## License

This project is licensed under the [MIT License](LICENSE).
