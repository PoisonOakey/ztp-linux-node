<#
.SYNOPSIS
Loads the single-source-of-truth hardware/lab settings from config/node.json.

.DESCRIPTION
Every pipeline stage that needs the VM name, lab directory, ISO URL, or
hardware sizing dot-sources this file and calls Get-LabConfig instead of
hardcoding its own defaults, so changing a value in config/node.json
(e.g. RAM, CPU cores, disk size, VM name) takes effect everywhere without
hunting through multiple scripts.
#>

function Get-LabConfig {
    param(
        [Parameter(Mandatory)]
        [string]$ConfigPath
    )

    if (-not (Test-Path $ConfigPath)) {
        throw "Config file not found at $ConfigPath. Did you delete or rename config/node.json?"
    }

    $config = Get-Content -Path $ConfigPath -Raw | ConvertFrom-Json

    # lab_dir is stored as a literal "$HOME\server-lab" style string so the
    # committed template stays portable across machines/users; expand it here.
    $config.lab_dir = $ExecutionContext.InvokeCommand.ExpandString($config.lab_dir)

    return $config
}
