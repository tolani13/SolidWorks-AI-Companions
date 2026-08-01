[CmdletBinding()]
param(
    [ValidateSet(
        "status",
        "inspect-active",
        "rebuild",
        "force-rebuild",
        "save",
        "export-step",
        "export-pdf",
        "set-custom-property"
    )]
    [string]$Action = "status",

    [string]$ArgumentsJson = "{}"
)

$ErrorActionPreference = "Stop"

function Write-BridgeResult {
    param(
        [bool]$Ok,
        [string]$RequestedAction,
        [object]$Data = $null,
        [string]$ErrorMessage = $null,
        [object[]]$Warnings = @()
    )

    [ordered]@{
        ok       = $Ok
        action   = $RequestedAction
        data     = $Data
        error    = $ErrorMessage
        warnings = @($Warnings)
    } | ConvertTo-Json -Depth 14 -Compress
}

function Get-SolidWorksApplication {
    try {
        return [System.Runtime.InteropServices.Marshal]::GetActiveObject("SldWorks.Application")
    }
    catch {
        throw "SOLIDWORKS is not running or its automation interface is unavailable. Start SOLIDWORKS and open a document, then try again."
    }
}

function Get-ActiveDocument {
    param([object]$Application)

    $document = $Application.ActiveDoc
    if ($null -eq $document) {
        throw "SOLIDWORKS is running, but no document is active."
    }
    return $document
}

function Get-DocumentTypeName {
    param([int]$DocumentType)

    switch ($DocumentType) {
        1 { return "part" }
        2 { return "assembly" }
        3 { return "drawing" }
        default { return "unknown" }
    }
}

function Get-ArgumentValue {
    param(
        [object]$Arguments,
        [string]$Name,
        [object]$DefaultValue = $null
    )

    if ($null -ne $Arguments -and $Arguments.PSObject.Properties.Name -contains $Name) {
        return $Arguments.$Name
    }
    return $DefaultValue
}

function Get-DocumentSummary {
    param([object]$Document)

    $documentType = [int]$Document.GetType()
    $configuration = $null
    try {
        $configuration = [string]$Document.ConfigurationManager.ActiveConfiguration.Name
    }
    catch {
        $configuration = $null
    }

    return [ordered]@{
        title         = [string]$Document.GetTitle()
        path          = [string]$Document.GetPathName()
        type          = Get-DocumentTypeName -DocumentType $documentType
        type_code     = $documentType
        configuration = $configuration
    }
}

function Get-CustomProperties {
    param([object]$Document)

    $properties = @()
    $manager = $Document.Extension.CustomPropertyManager("")
    $names = $manager.GetNames()

    foreach ($name in @($names)) {
        if ([string]::IsNullOrWhiteSpace([string]$name)) {
            continue
        }

        $rawValue = ""
        $resolvedValue = ""
        $wasResolved = $false
        $isLinked = $false
        $resultCode = $null

        try {
            $resultCode = $manager.Get6(
                [string]$name,
                $false,
                [ref]$rawValue,
                [ref]$resolvedValue,
                [ref]$wasResolved,
                [ref]$isLinked
            )
        }
        catch {
            $resultCode = $manager.Get5(
                [string]$name,
                $false,
                [ref]$rawValue,
                [ref]$resolvedValue,
                [ref]$wasResolved
            )
        }

        $properties += [ordered]@{
            name           = [string]$name
            value          = [string]$rawValue
            resolved_value = [string]$resolvedValue
            was_resolved   = [bool]$wasResolved
            is_linked      = [bool]$isLinked
            result_code    = $resultCode
        }
    }

    return @($properties)
}

function Get-FeatureSummary {
    param([object]$Document)

    $features = @()
    $feature = $Document.FirstFeature()
    $count = 0

    while ($null -ne $feature -and $count -lt 500) {
        $isWarning = $false
        $errorCode = 0
        $suppressed = $null

        try {
            $errorCode = [int]$feature.GetErrorCode2([ref]$isWarning)
        }
        catch {
            $errorCode = 0
            $isWarning = $false
        }

        try {
            $suppressed = [bool]$feature.IsSuppressed()
        }
        catch {
            $suppressed = $null
        }

        $features += [ordered]@{
            name       = [string]$feature.Name
            type       = [string]$feature.GetTypeName2()
            suppressed = $suppressed
            error_code = $errorCode
            is_warning = [bool]$isWarning
        }

        $feature = $feature.GetNextFeature()
        $count++
    }

    return [ordered]@{
        items     = @($features)
        truncated = ($null -ne $feature)
    }
}

function Get-AssemblyComponents {
    param([object]$Document)

    $components = @()
    foreach ($component in @($Document.GetComponents($false))) {
        if ($null -eq $component) {
            continue
        }

        $suppressed = $null
        $hidden = $null
        try { $suppressed = [int]$component.GetSuppression() } catch { $suppressed = $null }
        try { $hidden = [bool]$component.IsHidden($true) } catch { $hidden = $null }

        $components += [ordered]@{
            name                    = [string]$component.Name2
            path                    = [string]$component.GetPathName()
            referenced_configuration = [string]$component.ReferencedConfiguration
            suppression_state       = $suppressed
            hidden                  = $hidden
        }

        if ($components.Count -ge 1000) {
            break
        }
    }

    return @($components)
}

function Assert-ExportPath {
    param(
        [string]$Path,
        [string[]]$AllowedExtensions,
        [bool]$Overwrite
    )

    if ([string]::IsNullOrWhiteSpace($Path)) {
        throw "An absolute export path is required."
    }
    if (-not [System.IO.Path]::IsPathRooted($Path)) {
        throw "Export path must be absolute."
    }

    $fullPath = [System.IO.Path]::GetFullPath($Path)
    $extension = [System.IO.Path]::GetExtension($fullPath).ToLowerInvariant()
    if ($AllowedExtensions -notcontains $extension) {
        throw "Export extension '$extension' is not allowed for this action."
    }

    $parent = [System.IO.Path]::GetDirectoryName($fullPath)
    if (-not (Test-Path -LiteralPath $parent -PathType Container)) {
        throw "Export folder does not exist: $parent"
    }
    if ((Test-Path -LiteralPath $fullPath -PathType Leaf) -and -not $Overwrite) {
        throw "Export target already exists. Set overwrite to true only after confirming replacement."
    }

    return $fullPath
}

try {
    $arguments = $ArgumentsJson | ConvertFrom-Json
    $sw = Get-SolidWorksApplication

    switch ($Action) {
        "status" {
            $revision = $null
            try { $revision = [string]$sw.RevisionNumber() } catch { $revision = $null }

            $activeSummary = $null
            if ($null -ne $sw.ActiveDoc) {
                $activeSummary = Get-DocumentSummary -Document $sw.ActiveDoc
            }

            Write-BridgeResult -Ok $true -RequestedAction $Action -Data ([ordered]@{
                connected       = $true
                revision        = $revision
                active_document = $activeSummary
            })
        }

        "inspect-active" {
            $document = Get-ActiveDocument -Application $sw
            $summary = Get-DocumentSummary -Document $document
            $inspection = [ordered]@{
                document         = $summary
                custom_properties = Get-CustomProperties -Document $document
                features         = Get-FeatureSummary -Document $document
                components       = @()
            }

            if ($summary.type_code -eq 2) {
                $inspection.components = Get-AssemblyComponents -Document $document
            }

            Write-BridgeResult -Ok $true -RequestedAction $Action -Data $inspection
        }

        "rebuild" {
            $document = Get-ActiveDocument -Application $sw
            $success = [bool]$document.EditRebuild3()
            Write-BridgeResult -Ok $success -RequestedAction $Action -Data ([ordered]@{
                document = Get-DocumentSummary -Document $document
                rebuilt  = $success
            }) -ErrorMessage $(if ($success) { $null } else { "SOLIDWORKS reported that the rebuild did not complete successfully." })
        }

        "force-rebuild" {
            $document = Get-ActiveDocument -Application $sw
            $success = [bool]$document.ForceRebuild3($false)
            Write-BridgeResult -Ok $success -RequestedAction $Action -Data ([ordered]@{
                document = Get-DocumentSummary -Document $document
                rebuilt  = $success
            }) -ErrorMessage $(if ($success) { $null } else { "SOLIDWORKS reported that the forced rebuild did not complete successfully." })
        }

        "save" {
            $document = Get-ActiveDocument -Application $sw
            $path = [string]$document.GetPathName()
            if ([string]::IsNullOrWhiteSpace($path)) {
                throw "The active document has never been saved. Use SOLIDWORKS Save As first so the destination is explicit."
            }

            $errors = 0
            $warnings = 0
            $success = [bool]$document.Save3(1, [ref]$errors, [ref]$warnings)
            Write-BridgeResult -Ok $success -RequestedAction $Action -Data ([ordered]@{
                path         = $path
                save_errors  = $errors
                save_warnings = $warnings
            }) -ErrorMessage $(if ($success) { $null } else { "SOLIDWORKS reported that the document was not saved." })
        }

        { $_ -in @("export-step", "export-pdf") } {
            $document = Get-ActiveDocument -Application $sw
            $documentType = [int]$document.GetType()
            $requestedPath = [string](Get-ArgumentValue -Arguments $arguments -Name "path" -DefaultValue "")
            $overwrite = [bool](Get-ArgumentValue -Arguments $arguments -Name "overwrite" -DefaultValue $false)

            if ($Action -eq "export-step") {
                if ($documentType -notin @(1, 2)) {
                    throw "STEP export requires an active part or assembly."
                }
                $exportPath = Assert-ExportPath -Path $requestedPath -AllowedExtensions @(".step", ".stp") -Overwrite $overwrite
            }
            else {
                if ($documentType -ne 3) {
                    throw "PDF export requires an active drawing."
                }
                $exportPath = Assert-ExportPath -Path $requestedPath -AllowedExtensions @(".pdf") -Overwrite $overwrite
            }

            $clearResult = $document.ClearSelection2($true)
            $errors = 0
            $warnings = 0
            $success = [bool]$document.Extension.SaveAs(
                $exportPath,
                0,
                1,
                $null,
                [ref]$errors,
                [ref]$warnings
            )

            Write-BridgeResult -Ok $success -RequestedAction $Action -Data ([ordered]@{
                path            = $exportPath
                export_errors   = $errors
                export_warnings = $warnings
                selection_cleared = [bool]$clearResult
            }) -ErrorMessage $(if ($success) { $null } else { "SOLIDWORKS reported that the export failed." })
        }

        "set-custom-property" {
            $document = Get-ActiveDocument -Application $sw
            $name = [string](Get-ArgumentValue -Arguments $arguments -Name "name" -DefaultValue "")
            $value = [string](Get-ArgumentValue -Arguments $arguments -Name "value" -DefaultValue "")
            $configuration = [string](Get-ArgumentValue -Arguments $arguments -Name "configuration" -DefaultValue "")

            if ([string]::IsNullOrWhiteSpace($name)) {
                throw "Custom property name is required."
            }
            if ($name.Length -gt 255) {
                throw "Custom property name is too long."
            }
            if ($value.Length -gt 4096) {
                throw "Custom property value is too long."
            }

            $manager = $document.Extension.CustomPropertyManager($configuration)
            $resultCode = [int]$manager.Add3($name, 30, $value, 2)
            Write-BridgeResult -Ok $true -RequestedAction $Action -Data ([ordered]@{
                name          = $name
                value         = $value
                configuration = $configuration
                result_code   = $resultCode
            })
        }
    }
}
catch {
    Write-BridgeResult -Ok $false -RequestedAction $Action -ErrorMessage $_.Exception.Message
}
