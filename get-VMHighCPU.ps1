Get-VM | Where-Object { $_.PowerState -eq "PoweredOn" } | Get-Stat -Stat "cpu.usage.average" | Where-Object { $_.ValueUnit -gt 80}
