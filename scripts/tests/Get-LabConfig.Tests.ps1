<#
Pester tests for Get-LabConfig.

This is the only script in scripts/ with logic rather than side effects -- the
other five wrap VBoxManage, diskpart and bcdedit, where a unit test would be a
test of its own mocks. Get-LabConfig reads a file, expands one field and is
called by every stage, so a regression here is a regression everywhere.

Run locally:
    Invoke-Pester -Path scripts/tests
#>

BeforeAll {
    . (Join-Path (Split-Path $PSScriptRoot -Parent) 'Get-LabConfig.ps1')
}

Describe 'Get-LabConfig' {

    Context 'when the config file is missing' {

        It 'throws a message naming the file' {
            # The alternative is returning $null and failing several stages
            # later on a property of nothing, which is far harder to diagnose.
            $missing = Join-Path $TestDrive 'does-not-exist.json'
            { Get-LabConfig -ConfigPath $missing } |
                Should -Throw -ExpectedMessage '*Config file not found*'
        }
    }

    Context 'when reading a config file' {

        It 'expands a literal $HOME in lab_dir' {
            # lab_dir is committed as the literal string "$HOME\server-lab" so
            # the template stays portable. If this expansion is ever dropped,
            # stages create a directory called '$HOME'.
            $path = Join-Path $TestDrive 'expand.json'
            $json = '{"vm_name":"T","lab_dir":"$HOME\\lab","iso_url":"http://x/y.iso","ram_mb":1024,"cpu_cores":1,"disk_size_mb":8192}'
            Set-Content -Path $path -Value $json -Encoding UTF8

            (Get-LabConfig -ConfigPath $path).lab_dir | Should -Be (Join-Path $HOME 'lab')
        }

        It 'leaves a lab_dir with no variable in it alone' {
            $path = Join-Path $TestDrive 'literal.json'
            $json = '{"vm_name":"T","lab_dir":"C:\\lab","iso_url":"http://x/y.iso","ram_mb":1024,"cpu_cores":1,"disk_size_mb":8192}'
            Set-Content -Path $path -Value $json -Encoding UTF8

            (Get-LabConfig -ConfigPath $path).lab_dir | Should -Be 'C:\lab'
        }

        It 'returns the numeric fields as numbers, not strings' {
            # VBoxManage is handed these directly. A quoted "4096" in the JSON
            # would reach it as a string and fail at the hypervisor.
            $path = Join-Path $TestDrive 'types.json'
            $json = '{"vm_name":"T","lab_dir":"C:\\lab","iso_url":"http://x/y.iso","ram_mb":4096,"cpu_cores":2,"disk_size_mb":25600}'
            Set-Content -Path $path -Value $json -Encoding UTF8

            $config = Get-LabConfig -ConfigPath $path
            $config.ram_mb | Should -BeOfType [int]
            $config.cpu_cores | Should -BeOfType [int]
            $config.disk_size_mb | Should -BeOfType [int]
        }
    }

    Context 'against the repository config' {

        It 'reads config/node.json and returns every key the stages use' {
            # The CI lint job asserts these keys exist in the file. This asserts
            # they survive being loaded.
            $repoRoot = Split-Path (Split-Path $PSScriptRoot -Parent) -Parent
            $repoConfig = Join-Path $repoRoot 'config\node.json'
            $config = Get-LabConfig -ConfigPath $repoConfig

            foreach ($key in 'vm_name', 'lab_dir', 'iso_url', 'ram_mb', 'cpu_cores', 'disk_size_mb') {
                $config.PSObject.Properties.Name | Should -Contain $key
            }
        }

        It 'expands lab_dir to a real absolute path' {
            $repoRoot = Split-Path (Split-Path $PSScriptRoot -Parent) -Parent
            $repoConfig = Join-Path $repoRoot 'config\node.json'
            $labDir = (Get-LabConfig -ConfigPath $repoConfig).lab_dir

            $labDir | Should -Not -Match '\$'
            [System.IO.Path]::IsPathRooted($labDir) | Should -BeTrue
        }
    }
}
