<#
.SYNOPSIS
  Write the DAWO appliance live ISO to a USB stick with a DAWO_LOGS exFAT
  partition after the image, or read the logs back from it (#97).

.DESCRIPTION
  Experimental and unofficial. The Linux equivalent is
  scripts/write-live-stick.sh; both produce the same layout
  (docs/live-usb.md, "Writing the stick"):

    - the ISO (isohybrid) raw at offset 0;
    - MBR partition entry 3: type 0x07, starting 1 MiB after the image end
      rounded up to 1 MiB, up to the end of the disk, exFAT, label DAWO_LOGS.

  Actions:
    plan    (default) show the disk, its MBR entries, whether DAWO_LOGS is
            present and what write/create would do. Writes nothing.
    read    read-only: copy DAWO_LOGS\dawo-appliance\ (logs, screenshots) to
            -OutDir. Windows cannot read this partition itself.
    write   write the ISO, keep partition entry 3 and the DAWO_LOGS files.
            Needs an existing exFAT DAWO_LOGS entry 3 after the image end.
    create  write the ISO and create a new, empty DAWO_LOGS partition from
            -ExfatHead (made in WSL by scripts/make-dawo-logs-head.sh).
            Erases the whole stick.

  write and create need -ConfirmDestroy (AGENTS.md rule 7). Give exactly one
  of -DiskNumber (a USB disk, see Get-Disk; needs an Administrator window) or
  -ImagePath (a disk image file). Never use Disk Management or New-Partition
  on this stick: Windows ignores the image's partition entry and may create a
  partition over the image.

  Windows quirks handled here: Windows drops raw writes into regions it
  treats as volumes, so on a disk all MBR entry types are first set to 0x00
  (Windows then sees no partitions), the body is written, and the first
  4 MiB (with entry 3) are written last.

.EXAMPLE
  .\scripts\windows\dawo-stick.ps1 -DiskNumber 2
.EXAMPLE
  .\scripts\windows\dawo-stick.ps1 -Action write -DiskNumber 2 -ConfirmDestroy
#>
# SPDX-License-Identifier: EUPL-1.2
[CmdletBinding()]
param(
  [ValidateSet('plan', 'read', 'write', 'create')][string]$Action = 'plan',
  [int]$DiskNumber = -1,
  [string]$ImagePath = '',
  [string]$Iso = '',
  [string]$ExfatHead = '',
  [string]$OutDir = '',
  [switch]$ConfirmDestroy
)
$ErrorActionPreference = 'Stop'

$chunk = 4194304          # I/O block, and the head written last (4 MiB)
$MiB = [long]1048576
$GiB = [long]1073741824
$E3 = 446 + 32            # MBR partition entry 3
$EndOfChain = 4294967287L # exFAT: cluster numbers at or above this end a chain

function Log([string]$m) { Write-Host ("{0:HH:mm:ss} {1}" -f (Get-Date), $m) }
function Full([string]$p) { $ExecutionContext.SessionState.Path.GetUnresolvedProviderPathFromPSPath($p) }

# --- raw I/O (512-byte aligned, so it works on \\.\PhysicalDriveN too) -----------
function Open-Target([bool]$write) {
  $acc = if ($write) { [IO.FileAccess]::ReadWrite } else { [IO.FileAccess]::Read }
  $opt = if ($write) { [IO.FileOptions]::WriteThrough } else { [IO.FileOptions]::None }
  New-Object IO.FileStream($script:TargetPath, [IO.FileMode]::Open, $acc, [IO.FileShare]::ReadWrite, $chunk, $opt)
}
# Read $n bytes at byte offset $off.
function Read-At($fs, [long]$off, [long]$n) {
  [long]$start = $off - ($off % 512)
  [long]$end = $off + $n; if ($end % 512) { $end += 512 - ($end % 512) }
  $buf = New-Object byte[] ($end - $start)
  [void]$fs.Seek($start, 'Begin')
  [long]$got = 0
  while ($got -lt $buf.Length) {
    $r = $fs.Read($buf, $got, [math]::Min($buf.Length - $got, $chunk)); if ($r -le 0) { break }; $got += $r
  }
  if ($got -lt ($off - $start + $n)) { throw "short read at byte $off" }
  $res = New-Object byte[] $n
  [Array]::Copy($buf, $off - $start, $res, 0, $n)
  return , $res
}
# Write $n bytes of $buf at byte offset $off (both multiples of 512 after padding).
function Write-At($fs, [long]$off, [byte[]]$buf, [int]$n) {
  if ($n % 512) { $pad = New-Object byte[] ($n + 512 - ($n % 512)); [Array]::Copy($buf, $pad, $n); $buf = $pad; $n = $pad.Length }
  [void]$fs.Seek($off, 'Begin'); $fs.Write($buf, 0, $n); $fs.Flush()
}
# Copy $len bytes of file $src (from byte $srcOff) to the target at byte $dstOff.
function Copy-FileTo($fs, [string]$src, [long]$srcOff, [long]$dstOff, [long]$len) {
  $in = [IO.File]::OpenRead($src)
  try {
    [void]$in.Seek($srcOff, 'Begin'); [void]$fs.Seek($dstOff, 'Begin')
    $buf = New-Object byte[] $chunk; [long]$left = $len; $last = [DateTime]::Now
    while ($left -gt 0) {
      $r = $in.Read($buf, 0, [int][math]::Min([long]$chunk, $left)); if ($r -le 0) { throw "short read from $src" }
      $left -= $r
      if ($r % 512) { $r2 = $r + 512 - ($r % 512); [Array]::Clear($buf, $r, $r2 - $r); $r = $r2 }
      $fs.Write($buf, 0, $r)
      if (([DateTime]::Now - $last).TotalSeconds -ge 30) { Log ("  {0} MiB left" -f [math]::Floor($left / $MiB)); $last = [DateTime]::Now }
    }
    $fs.Flush()
  } finally { $in.Close() }
}
# sha256 (hex) of the first $len bytes of a stream, with MBR entry 3 zeroed.
function Get-ImageHash($s, [long]$len) {
  $h = [Security.Cryptography.SHA256]::Create(); $buf = New-Object byte[] $chunk
  [void]$s.Seek(0, 'Begin'); [long]$done = 0
  while ($done -lt $len) {
    $r = $s.Read($buf, 0, $chunk); if ($r -le 0) { throw "short read while verifying" }
    if ($done -eq 0) { if ($r -lt $E3 + 16) { throw "short first read while verifying" }; [Array]::Clear($buf, $E3, 16) }
    $use = [int][math]::Min([long]$r, $len - $done)
    [void]$h.TransformBlock($buf, 0, $use, $null, 0); $done += $use
  }
  [void]$h.TransformFinalBlock($buf, 0, 0)
  return [BitConverter]::ToString($h.Hash).Replace('-', '').ToLower()
}
function Get-BytesHash([byte[]]$b) {
  $h = [Security.Cryptography.SHA256]::Create()
  return [BitConverter]::ToString($h.ComputeHash($b)).Replace('-', '').ToLower()
}

# --- MBR and exFAT --------------------------------------------------------------
function Get-Entries([byte[]]$mbr) {
  $list = @()
  foreach ($k in 0..3) {
    $o = 446 + 16 * $k
    $list += [pscustomobject]@{
      Index = $k + 1; Type = [int]$mbr[$o + 4]
      Start = [long][BitConverter]::ToUInt32($mbr, $o + 8); Count = [long][BitConverter]::ToUInt32($mbr, $o + 12)
    }
  }
  return , $list
}
function New-Entry3([long]$start, [long]$count) {
  $e = [byte[]](0x00, 0xFE, 0xFF, 0xFF, 0x07, 0xFE, 0xFF, 0xFF, 0, 0, 0, 0, 0, 0, 0, 0)
  [Array]::Copy([BitConverter]::GetBytes([uint32]$start), 0, $e, 8, 4)
  [Array]::Copy([BitConverter]::GetBytes([uint32]$count), 0, $e, 12, 4)
  return , $e
}
# The exFAT filesystem at byte $off of stream $fs (of $size bytes), or $null.
function Get-Exfat($fs, [long]$off, [long]$size) {
  if ($off + 512 -gt $size) { return $null }
  $bs = Read-At $fs $off 512
  if ([Text.Encoding]::ASCII.GetString($bs, 3, 8) -ne 'EXFAT   ') { return $null }
  $bps = [long]1 -shl $bs[108]; $cs = $bps -shl $bs[109]
  $x = [pscustomobject]@{
    Off = $off; Bps = $bps; Cs = $cs
    VolumeLength = [long][BitConverter]::ToUInt64($bs, 72)
    FatOff = [long][BitConverter]::ToUInt32($bs, 80); Heap = [long][BitConverter]::ToUInt32($bs, 88)
    Root = [long][BitConverter]::ToUInt32($bs, 96); Label = ''
  }
  $rootOff = $off + $x.Heap * $bps + ($x.Root - 2) * $cs
  $n = [math]::Min($cs, $MiB)
  if ($rootOff + $n -gt $size) { return $x }
  $raw = Read-At $fs $rootOff $n
  for ($i = 0; $i + 32 -le $raw.Length; $i += 32) {
    if ($raw[$i] -eq 0) { break }
    if ($raw[$i] -eq 0x83) { $x.Label = [Text.Encoding]::Unicode.GetString($raw, $i + 2, 2 * [math]::Min(11, [int]$raw[$i + 1])); break }
  }
  return $x
}

# --- target ---------------------------------------------------------------------
function Test-Admin {
  ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
}
function Select-Target {
  $hasDisk = $script:DiskGiven
  $hasImage = [bool]$script:ImagePath
  if ($hasDisk -eq $hasImage) { throw "give exactly one of -DiskNumber <n> or -ImagePath <file>" }
  if ($hasImage) {
    $p = Full $script:ImagePath
    if (-not (Test-Path -LiteralPath $p -PathType Leaf)) { throw "image file not found: $p" }
    $script:IsDisk = $false; $script:TargetPath = $p; $script:TargetSize = (Get-Item -LiteralPath $p).Length
    Log "target: image file $p, $($script:TargetSize) bytes"
    return
  }
  if (-not (Test-Admin)) { throw "-DiskNumber needs raw disk access: run this in an Administrator PowerShell window" }
  $d = Get-Disk -Number $script:DiskNumber
  $script:IsDisk = $true; $script:Disk = $d; $script:TargetPath = "\\.\PhysicalDrive$($d.Number)"; $script:TargetSize = [long]$d.Size
  Log ("target: disk {0} '{1}', bus {2}, {3:N1} GB ({4} bytes), boot {5}, system {6}, read-only {7}, {8} partition(s) visible to Windows" -f `
      $d.Number, $d.FriendlyName, $d.BusType, ($d.Size / 1e9), $d.Size, $d.IsBoot, $d.IsSystem, $d.IsReadOnly, $d.NumberOfPartitions)
}
# Reasons this disk must not be written (empty for an image file).
function Get-DiskRefusals([long]$isoLen) {
  $why = @()
  if (-not $script:IsDisk) { return , $why }
  $d = $script:Disk
  if ($d.IsBoot) { $why += 'it is the boot disk' }
  if ($d.IsSystem) { $why += 'it is the system disk' }
  if ("$($d.BusType)" -ne 'USB') { $why += "its bus type is $($d.BusType), not USB" }
  if ($d.IsReadOnly) { $why += 'it is read-only' }
  if ($isoLen -gt 0 -and $d.Size -lt $isoLen + $GiB) { $why += "it is smaller than the ISO + 1 GiB" }
  return , $why
}
function Assert-Writable([long]$isoLen) {
  $why = Get-DiskRefusals $isoLen
  if ($why.Count) { throw ("refusing to write this disk: " + ($why -join '; ')) }
}
# Hide all MBR entries (type 0x00), so Windows sees no partitions and lets raw
# writes through; the head written last brings them back.
function Hide-Entries {
  if (-not $script:IsDisk) { return }
  $fs = Open-Target $true
  try {
    $mbr = Read-At $fs 0 512
    foreach ($k in 0..3) { $mbr[446 + 16 * $k + 4] = 0 }
    Write-At $fs 0 $mbr 512
  } finally { $fs.Close() }
  Update-Disk -Number $script:Disk.Number; Start-Sleep -Seconds 4
  $n = (Get-Partition -DiskNumber $script:Disk.Number -ErrorAction SilentlyContinue | Measure-Object).Count
  Log "hid the MBR entries; partitions Windows sees now: $n"
}

# --- ISO ------------------------------------------------------------------------
function Get-IsoInfo {
  $p = if ($script:Iso) { Full $script:Iso } else { Join-Path $env:USERPROFILE 'Downloads\dawo-appliance-live.iso' }
  if (-not (Test-Path -LiteralPath $p -PathType Leaf)) { return $null }
  $len = (Get-Item -LiteralPath $p).Length
  $sectors = [long][math]::Ceiling($len / 512)
  $start = [long]([math]::Ceiling($sectors / 2048) * 2048 + 2048)
  return [pscustomobject]@{ Path = $p; Length = $len; NewStart = $start; NewCount = [long]([math]::Floor($script:TargetSize / 512) - $start) }
}
function Assert-Iso($info) {
  if (-not $info) { throw "ISO not found; pass -Iso <path> (default: Downloads\dawo-appliance-live.iso)" }
  if ($info.Length -lt $chunk) { throw "the ISO is smaller than 4 MiB; is it the live ISO?" }
  $sum = "$($info.Path).sha256"
  if (Test-Path -LiteralPath $sum) {
    Log "checking the ISO against $sum"
    $want = (Get-Content -LiteralPath $sum -Raw).Trim().Split(' ')[0].ToLower()
    $have = (Get-FileHash -LiteralPath $info.Path -Algorithm SHA256).Hash.ToLower()
    if ($have -ne $want) { throw "the ISO does not match its .sha256; nothing written" }
  }
  $in = [IO.File]::OpenRead($info.Path)
  try { $mbr = Read-At $in 0 512 } finally { $in.Close() }
  for ($i = 0; $i -lt 16; $i++) { if ($mbr[$E3 + $i] -ne 0) { throw "MBR entry 3 in the ISO is not empty; this tool needs it for DAWO_LOGS" } }
}
# The ISO's first 4 MiB with MBR entry 3 replaced by $entry.
function Get-Head($info, [byte[]]$entry) {
  $head = New-Object byte[] $chunk
  $in = [IO.File]::OpenRead($info.Path)
  try { $n = $in.Read($head, 0, $chunk) } finally { $in.Close() }
  if ($n -ne $chunk) { throw "short read from the ISO" }
  [Array]::Copy($entry, 0, $head, $E3, 16)
  return , $head
}
function Write-Iso($info, [byte[]]$head, [long]$exOff, [string]$exFile) {
  Hide-Entries
  $w = Open-Target $true
  try {
    Log ("writing the image from 4 MiB on ({0} bytes)" -f ($info.Length - $chunk))
    Copy-FileTo $w $info.Path $chunk $chunk ($info.Length - $chunk)
    if ($exFile) {
      $exLen = (Get-Item -LiteralPath $exFile).Length
      Log "writing the exFAT metadata ($exLen bytes) at byte $exOff"
      Copy-FileTo $w $exFile 0 $exOff $exLen
    }
    Log "writing the first 4 MiB (MBR with entry 3) last"
    Write-At $w 0 $head $chunk
  } finally { $w.Close() }
  if ($script:IsDisk) { Update-Disk -Number $script:Disk.Number }
}
function Assert-Image($info) {
  Log "verifying the image area (sha256 over $($info.Length) bytes, entry 3 excluded)"
  $a = [IO.File]::OpenRead($info.Path); $b = Open-Target $false
  try { $ha = Get-ImageHash $a $info.Length; $hb = Get-ImageHash $b $info.Length } finally { $a.Close(); $b.Close() }
  if ($ha -ne $hb) { throw "VERIFY FAILED: the target differs from the ISO" }
}

# --- actions --------------------------------------------------------------------
function Show-State {
  $fs = Open-Target $false
  try {
    $mbr = Read-At $fs 0 512
    $script:Entries = Get-Entries $mbr
    $script:Mbr = $mbr
    Log ("MBR of the target (signature {0}):" -f $(if ($mbr[510] -eq 0x55 -and $mbr[511] -eq 0xAA) { '55AA' } else { 'missing' }))
    foreach ($e in $script:Entries) { Log ("  entry {0}: type 0x{1:x2}, start sector {2}, {3} sectors" -f $e.Index, $e.Type, $e.Start, $e.Count) }
    $p3 = $script:Entries[2]; $script:Logs = $null
    if ($p3.Type -eq 7 -and $p3.Start -gt 0 -and ($p3.Start * 512 + 512) -le $script:TargetSize) {
      $x = Get-Exfat $fs ($p3.Start * 512) $script:TargetSize
      if ($x -and $x.Label -eq 'DAWO_LOGS') { $script:Logs = $x }
    }
  } finally { $fs.Close() }
  if ($script:Logs) { Log ("DAWO_LOGS: exFAT in entry 3 at byte {0}, {1} bytes" -f ($p3.Start * 512), ($p3.Count * 512)) }
  else { Log "DAWO_LOGS: none (entry 3 has no exFAT filesystem labelled DAWO_LOGS)" }
}

function Do-Plan {
  Show-State
  $info = Get-IsoInfo
  if (-not $info) { Log "plan: ISO not found; pass -Iso <path> to see what write/create would do"; Log "plan: nothing written"; return }
  Log "ISO: $($info.Path), $($info.Length) bytes"
  $why = Get-DiskRefusals $info.Length
  if ($why.Count) { Log ("plan: write and create would REFUSE this disk: " + ($why -join '; ')) }
  $p3 = $script:Entries[2]
  if ($script:Logs -and $p3.Start * 512 -ge $info.Length) {
    Log ("plan: write would overwrite bytes 0..{0} with the ISO and keep DAWO_LOGS (entry 3) and its files" -f ($info.Length - 1))
  } elseif ($script:Logs) {
    Log ("plan: write is not possible: the ISO would overlap DAWO_LOGS at byte {0}; use create (erases it)" -f ($p3.Start * 512))
  } else { Log "plan: write is not possible: no DAWO_LOGS; use create" }
  Log ("plan: create would ERASE the whole target: ISO at 0, DAWO_LOGS (entry 3) at sector {0}, {1} sectors ({2} MiB), from -ExfatHead" -f `
      $info.NewStart, $info.NewCount, [math]::Floor($info.NewCount * 512 / $MiB))
  Log ("plan: make the -ExfatHead in WSL with: bash scripts/make-dawo-logs-head.sh {0} dawo-logs-head.bin" -f ($info.NewCount * 512))
  Log "plan: nothing written"
}

function Do-Read {
  Show-State
  $p3 = $script:Entries[2]
  if (-not $script:Logs) { throw "no exFAT DAWO_LOGS in MBR entry 3" }
  $x = $script:Logs
  $fs = Open-Target $false
  try {
    $p = $x.Off; $bps = $x.Bps; $cs = $x.Cs; $heapOff = $x.Heap
    $fatBase = $p + $x.FatOff * $bps
    $script:fatPages = @{}
    $nextOf = {
      param([long]$c)
      $page = [long][math]::Floor($c * 4 / $MiB)
      if (-not $script:fatPages.ContainsKey($page)) { $script:fatPages[$page] = Read-At $fs ($fatBase + $page * $MiB) $MiB }
      [long][BitConverter]::ToUInt32($script:fatPages[$page], ($c * 4) % $MiB)
    }
    $clOff = { param([long]$c) $p + $heapOff * $bps + ($c - 2) * $cs }
    $readChain = {
      param([long]$first, [long]$len, [bool]$contig)
      if ($first -eq 0 -or $len -eq 0) { return , (New-Object byte[] 0) }
      if ($contig) { return , (Read-At $fs (& $clOff $first) $len) }
      $ms = New-Object IO.MemoryStream; [long]$c = $first; [long]$left = $len
      while ($left -gt 0 -and $c -ge 2 -and $c -lt $EndOfChain) {
        $take = [math]::Min($cs, $left); $b = Read-At $fs (& $clOff $c) $take; $ms.Write($b, 0, $b.Length)
        $left -= $take; $c = & $nextOf $c
      }
      if ($left -gt 0) { throw "broken FAT chain at cluster $c" }
      return , $ms.ToArray()
    }
    $readDir = {
      param([long]$first, [long]$len, [bool]$contig, [bool]$isRoot)
      if ($isRoot) {
        $ms = New-Object IO.MemoryStream; [long]$c = $first
        while ($c -ge 2 -and $c -lt $EndOfChain) { $b = Read-At $fs (& $clOff $c) $cs; $ms.Write($b, 0, $b.Length); $c = & $nextOf $c }
        $raw = $ms.ToArray()
      } else { $raw = & $readChain $first $len $contig }
      $list = @(); $i = 0
      while ($i + 32 -le $raw.Length) {
        $t = $raw[$i]
        if ($t -eq 0) { break }
        if ($t -eq 0x85) {
          $sec = $raw[$i + 1]; $attrs = [BitConverter]::ToUInt16($raw, $i + 4)
          $st = $i + 32; $flags = $raw[$st + 1]; $nlen = $raw[$st + 3]
          $valid = [BitConverter]::ToInt64($raw, $st + 8)
          $fc = [BitConverter]::ToUInt32($raw, $st + 20); $dlen = [BitConverter]::ToInt64($raw, $st + 24)
          $nb = New-Object IO.MemoryStream
          for ($k = 2; $k -le $sec; $k++) { $nb.Write($raw, $i + 32 * $k + 2, 30) }
          $name = [Text.Encoding]::Unicode.GetString($nb.ToArray()).Substring(0, $nlen)
          $list += [pscustomobject]@{ Name = $name; Dir = [bool]($attrs -band 0x10); First = [long]$fc; Len = [long]$dlen; Valid = [long]$valid; Contig = [bool]($flags -band 2) }
          $i += 32 * ($sec + 1); continue
        }
        $i += 32
      }
      return , $list
    }
    $rootEntries = & $readDir $x.Root 0 $false $true
    Log ("DAWO_LOGS root: " + (($rootEntries | ForEach-Object { $_.Name }) -join ', '))
    $top = $rootEntries | Where-Object { $_.Name -eq 'dawo-appliance' -and $_.Dir } | Select-Object -First 1
    if (-not $top) { throw "no dawo-appliance folder on DAWO_LOGS" }
    $dst = if ($script:OutDir) { Full $script:OutDir } else { Join-Path $env:USERPROFILE 'Downloads\dawo-stick-logs' }
    $script:nFiles = 0; $script:bytes = [long]0
    $walk = {
      param($e, [string]$path)
      if ($e.Name -eq 'dawo-data.ext4' -or $e.Name -eq 'dawo-images') { return }
      if ($e.Dir) {
        New-Item -ItemType Directory -Force -Path $path | Out-Null
        $children = & $readDir $e.First $e.Len $e.Contig $false
        foreach ($ch in $children) { & $walk $ch (Join-Path $path $ch.Name) }
      } else {
        $data = & $readChain $e.First $e.Len $e.Contig
        if ($e.Valid -lt $data.Length) { [Array]::Clear($data, [int]$e.Valid, $data.Length - [int]$e.Valid) }
        [IO.File]::WriteAllBytes($path, $data); $script:nFiles++; $script:bytes += $data.Length
      }
    }
    & $walk $top $dst
    Log "read: $($script:nFiles) files ($($script:bytes) bytes) to $dst"
  } finally { $fs.Close() }
}

function Do-Write {
  $info = Get-IsoInfo
  Assert-Iso $info
  Show-State
  Assert-Writable $info.Length
  $p3 = $script:Entries[2]
  if (-not $script:Logs) { throw "no exFAT DAWO_LOGS in MBR entry 3 of the target; use -Action create; nothing written" }
  if ($info.Length -gt $p3.Start * 512) { throw "the ISO ($($info.Length) bytes) would overlap DAWO_LOGS at byte $($p3.Start * 512); use -Action create; nothing written" }
  $fs = Open-Target $false
  try { $before = Get-BytesHash (Read-At $fs ($p3.Start * 512) $MiB) } finally { $fs.Close() }
  Log ("WILL OVERWRITE bytes 0..{0} of the target (the current image); DAWO_LOGS at byte {1} is kept" -f ($info.Length - 1), ($p3.Start * 512))
  $entry = New-Object byte[] 16; [Array]::Copy($script:Mbr, $E3, $entry, 0, 16)
  Write-Iso $info (Get-Head $info $entry) 0 ''
  Assert-Image $info
  $fs = Open-Target $false
  try { $after = Get-BytesHash (Read-At $fs ($p3.Start * 512) $MiB) } finally { $fs.Close() }
  if ($after -ne $before) { throw "VERIFY FAILED: the start of DAWO_LOGS changed" }
  Log "VERIFY OK: image written, DAWO_LOGS kept"
}

function Do-Create {
  $info = Get-IsoInfo
  Assert-Iso $info
  if (-not $script:ExfatHead) { throw "create needs -ExfatHead <file> (see -Action plan for the command that makes it)" }
  $exFile = Full $script:ExfatHead
  if (-not (Test-Path -LiteralPath $exFile -PathType Leaf)) { throw "exFAT head file not found: $exFile" }
  Show-State
  Assert-Writable $info.Length
  $start = $info.NewStart; $count = $info.NewCount
  if ($count * 512 -lt 64 * $MiB) { throw "no room for a DAWO_LOGS partition of at least 64 MiB after the image" }
  if ($count -gt 4294967295L) { throw "the target is too large for an MBR partition entry (over 2 TiB)" }
  $exLen = (Get-Item -LiteralPath $exFile).Length
  $hf = [IO.File]::OpenRead($exFile)
  try { $x = Get-Exfat $hf 0 $exLen } finally { $hf.Close() }
  if (-not $x) { throw "$exFile is not exFAT metadata (no 'EXFAT   ' signature)" }
  if ($x.Label -ne 'DAWO_LOGS') { throw "$exFile has label '$($x.Label)', not DAWO_LOGS" }
  if ($x.VolumeLength -ne $count -or $exLen % 512 -or $exLen -gt $count * 512) {
    throw ("{0} is for a partition of {1} sectors, this target needs {2}; make it in WSL with: bash scripts/make-dawo-logs-head.sh {3} dawo-logs-head.bin" -f `
        $exFile, $x.VolumeLength, $count, ($count * 512))
  }
  $what = if ($script:Logs) { ", including the existing DAWO_LOGS and its files" } else { '' }
  Log ("WILL ERASE all of the target ({0} bytes){1}" -f $script:TargetSize, $what)
  $entry = New-Entry3 $start $count
  $partOff = $start * 512
  Write-Iso $info (Get-Head $info $entry) $partOff $exFile
  Assert-Image $info
  $fs = Open-Target $false
  try {
    $mbr = Read-At $fs 0 512
    for ($i = 0; $i -lt 16; $i++) { if ($mbr[$E3 + $i] -ne $entry[$i]) { throw "VERIFY FAILED: MBR entry 3" } }
    $got = Read-At $fs $partOff $exLen
    if ([Text.Encoding]::ASCII.GetString($got, 3, 8) -ne 'EXFAT   ') { throw "VERIFY FAILED: no exFAT signature at the partition" }
    if ((Get-BytesHash $got) -ne (Get-BytesHash ([IO.File]::ReadAllBytes($exFile)))) { throw "VERIFY FAILED: exFAT metadata" }
  } finally { $fs.Close() }
  Log "VERIFY OK: image written, DAWO_LOGS created (entry 3, sector $start, $count sectors)"
}

try {
  Log "dawo-stick: action $Action"
  $script:DiskGiven = $PSBoundParameters.ContainsKey('DiskNumber')
  if (($Action -eq 'write' -or $Action -eq 'create') -and -not $ConfirmDestroy) {
    throw "'$Action' overwrites the target; refusing without -ConfirmDestroy (run -Action plan first to see what it would do)"
  }
  Select-Target
  switch ($Action) {
    'plan' { Do-Plan }
    'read' { Do-Read }
    'write' { Do-Write }
    'create' { Do-Create }
  }
  Log "done"
  exit 0
} catch {
  [Console]::Error.WriteLine(("{0:HH:mm:ss} ERROR: {1}" -f (Get-Date), $_.Exception.Message))
  exit 1
}
