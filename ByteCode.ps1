Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing

# --- משתנים גלובליים ---
$SourceFiles = @()
$OutputFolder = ""
$FormTitle = "Embedded Code Generator"

# ---------------------------------------------------------------------------------------
## 1. הגדרת הפונקציות הראשיות ליצירת הסקריפט
# ---------------------------------------------------------------------------------------

function Generate-ExtractedScript {
    param(
        [Parameter(Mandatory=$true)][string[]]$FilesToEmbed,
        [Parameter(Mandatory=$true)][string]$ExtractionPath,
        [string]$AdditionalCode = ""
    )

    if (-not $FilesToEmbed) {
        [System.Windows.Forms.MessageBox]::Show("אנא בחר קבצים להטמעה.", $FormTitle, [System.Windows.Forms.MessageBoxButtons]::OK, [System.Windows.Forms.MessageBoxIcon]::Warning) | Out-Null
        return
    }
    if (-not $ExtractionPath) {
        [System.Windows.Forms.MessageBox]::Show("אנא בחר תיקיית חילוץ.", $FormTitle, [System.Windows.Forms.MessageBoxButtons]::OK, [System.Windows.Forms.MessageBoxIcon]::Warning) | Out-Null
        return
    }

    $FileBytesData = @()
    Write-Host "🔄 מעבד $($FilesToEmbed.Count) קבצים..."

    foreach ($File in $FilesToEmbed) {
        $FileName = Split-Path -Path $File -Leaf
        
        # קורא בייטים גולמיים
        $Bytes = Get-Content -Path $File -Encoding Byte -ErrorAction Stop
        $BytesText = ($Bytes | ForEach-Object { "0x{0:X2}" -f $_ }) -join ", "
        
        $FileBytesData += [PSCustomObject]@{
            FileName = $FileName
            BytesText = $BytesText
        }
    }

    # הכנת מחרוזת הנתונים לסקריפט הפלט
    $FileBytesDataText = @(
        $FileBytesData | ForEach-Object {
            "    @{ FileName = '$($_.FileName)'; BytesText = '$($_.BytesText)' },"
        }
    )
    if ($FileBytesDataText.Count -gt 0) {
        $FileBytesDataText[-1] = $FileBytesDataText[-1] -replace ',$'
    }
    
    # ---------------------------------------------------------------------------------------
    # --- תבנית הסקריפט החילוץ (Extracted.Ps1) ---
    # ---------------------------------------------------------------------------------------
    $ScriptTemplate = @'
# --- Extracted.Ps1 ---
# סקריפט שחזור אוטומטי
# שוחזר בתאריך: $(Get-Date -Format "yyyy-MM-dd HH:mm:ss")

# הגדרת תיקיית הפלט (נתיב קשיח שהוגדר ב-GUI)
$OutputFolder = "$ExtractionPath"
Write-Host "תיקיית הפלט שהוגדרה: $OutputFolder"

function Write-Bytes {
    param(
        [byte[]]$Bytes,
        [string]$Path
    )
    $dir = Split-Path $Path
    if (-not (Test-Path $dir)) {
        New-Item -ItemType Directory -Path $dir -Force | Out-Null
    }
    [System.IO.File]::WriteAllBytes($Path, $Bytes)
}

$FileDataSet = @(
$FileBytesDataText
)

# לולאה על כל הקבצים לשחזור
foreach ($FileEntry in $FileDataSet) {
    
    $OutputFile = Join-Path -Path $OutputFolder -ChildPath $FileEntry.FileName
    Write-Host "🔄 כותב קובץ: $OutputFile..." -ForegroundColor Cyan

    # פתרון יציב: המרת המחרוזת [string] ישירות למערך בייטים [byte[]]
    $BytesText = $FileEntry.BytesText -replace '0x', ''
    
    $Bytes = $BytesText -split ', ' | ForEach-Object {
        if (-not [string]::IsNullOrEmpty($_)) {
            [byte]::Parse($_, [System.Globalization.NumberStyles]::HexNumber)
        }
    }
    
    Write-Bytes -Bytes $Bytes -Path $OutputFile
}

Write-Host "`n✨ סיום שחזור הקבצים." -ForegroundColor Green

# --------------------------------------------------
# --- קוד נוסף שהושתל מה-GUI ---
# --------------------------------------------------
$AdditionalCode

# --------------------------------------------------
'@

    # מילוי התבנית והכתיבה לסקריפט הפלט
    $ScriptContent = $ScriptTemplate -replace '\$ExtractionPath', $ExtractionPath -replace '\$FileBytesDataText', "`n$($FileBytesDataText -join "`n")" -replace '\$AdditionalCode', $AdditionalCode

    $OutputFile = Join-Path -Path (Get-Location) -ChildPath "Extracted.Ps1"
    $ScriptContent | Set-Content $OutputFile -Encoding UTF8

    [System.Windows.Forms.MessageBox]::Show("סקריפט החילוץ Extracted.Ps1 נוצר בהצלחה! יצאו: $($FilesToEmbed.Count) קבצים.", $FormTitle, [System.Windows.Forms.MessageBoxButtons]::OK, [System.Windows.Forms.MessageBoxIcon]::Information) | Out-Null

}


# ---------------------------------------------------------------------------------------
## 2. בניית ה-GUI (הטופס הראשי)
# ---------------------------------------------------------------------------------------

# --- הגדרת הטופס הראשי ---
$Form = New-Object System.Windows.Forms.Form
$Form.Text = $FormTitle
$Form.Size = New-Object System.Drawing.Size(650, 600)
$Form.StartPosition = [System.Windows.Forms.FormStartPosition]::CenterScreen
$Form.FormBorderStyle = [System.Windows.Forms.FormBorderStyle]::FixedSingle
$Form.TopMost = $true
$Form.MaximizeBox = $false
$Form.Font = New-Object System.Drawing.Font("Arial", 10)

# 1. קבצים לבחירה
$LabelFiles = New-Object System.Windows.Forms.Label
$LabelFiles.Text = "קבצים להטמעה:"
$LabelFiles.Location = New-Object System.Drawing.Point(10, 15)
$LabelFiles.Size = New-Object System.Drawing.Size(200, 20)
$Form.Controls.Add($LabelFiles)

$TextBoxFiles = New-Object System.Windows.Forms.TextBox
$TextBoxFiles.Location = New-Object System.Drawing.Point(10, 40)
$TextBoxFiles.Size = New-Object System.Drawing.Size(450, 25)
$TextBoxFiles.ReadOnly = $true
$TextBoxFiles.Text = "לא נבחרו קבצים"
$Form.Controls.Add($TextBoxFiles)

$ButtonSelectFiles = New-Object System.Windows.Forms.Button
$ButtonSelectFiles.Text = "בחר קבצים..."
$ButtonSelectFiles.Location = New-Object System.Drawing.Point(470, 38)
$ButtonSelectFiles.Size = New-Object System.Drawing.Size(150, 30)
$Form.Controls.Add($ButtonSelectFiles)

# 2. תיקיית פלט
$LabelFolder = New-Object System.Windows.Forms.Label
$LabelFolder.Text = "תיקיית חילוץ יעד (בתוך הסקריפט):"
$LabelFolder.Location = New-Object System.Drawing.Point(10, 85)
$LabelFolder.Size = New-Object System.Drawing.Size(300, 20)
$Form.Controls.Add($LabelFolder)

$TextBoxFolder = New-Object System.Windows.Forms.TextBox
$TextBoxFolder.Location = New-Object System.Drawing.Point(10, 110)
$TextBoxFolder.Size = New-Object System.Drawing.Size(450, 25)
$TextBoxFolder.Text = "C:\Extracted_Files" # ברירת מחדל
$Form.Controls.Add($TextBoxFolder)

$ButtonSelectFolder = New-Object System.Windows.Forms.Button
$ButtonSelectFolder.Text = "בחר תיקייה..."
$ButtonSelectFolder.Location = New-Object System.Drawing.Point(470, 108)
$ButtonSelectFolder.Size = New-Object System.Drawing.Size(150, 30)
$Form.Controls.Add($ButtonSelectFolder)

# 3. פאנל קוד נוסף
$LabelCode = New-Object System.Windows.Forms.Label
$LabelCode.Text = "קוד PowerShell נוסף לביצוע בסוף החילוץ:"
$LabelCode.Location = New-Object System.Drawing.Point(10, 160)
$LabelCode.Size = New-Object System.Drawing.Size(400, 20)
$Form.Controls.Add($LabelCode)

$TextBoxCode = New-Object System.Windows.Forms.TextBox
$TextBoxCode.Location = New-Object System.Drawing.Point(10, 185)
$TextBoxCode.Size = New-Object System.Drawing.Size(610, 300)
$TextBoxCode.Multiline = $true
$TextBoxCode.ScrollBars = [System.Windows.Forms.ScrollBars]::Vertical
$TextBoxCode.Font = New-Object System.Drawing.Font("Consolas", 13)
$TextBoxCode.Text = "# הוסף קוד שירוץ לאחר שחזור כל הקבצים, לדוגמה:\n# Invoke-Item (Join-Path -Path \$OutputFolder -ChildPath 'MyApp.exe')"
$Form.Controls.Add($TextBoxCode)

# 4. כפתור יצירת סקריפט (מוקטן)
$ButtonGenerate = New-Object System.Windows.Forms.Button
$ButtonGenerate.Text = "צור סקריפט Extracted.Ps1"
$ButtonGenerate.Location = New-Object System.Drawing.Point(10, 500)
$ButtonGenerate.Size = New-Object System.Drawing.Size(450, 50)
$ButtonGenerate.Font = New-Object System.Drawing.Font("Arial", 12, [System.Drawing.FontStyle]::Bold)
$Form.Controls.Add($ButtonGenerate)


# 5. כפתור יציאה חדש! 🚪
$ButtonExit = New-Object System.Windows.Forms.Button
$ButtonExit.Text = "יציאה"
$ButtonExit.Location = New-Object System.Drawing.Point(470, 500)
$ButtonExit.Size = New-Object System.Drawing.Size(150, 50)
$ButtonExit.Font = New-Object System.Drawing.Font("Arial", 12, [System.Drawing.FontStyle]::Regular)
$ButtonExit.BackColor = [System.Drawing.Color]::LightCoral
$Form.Controls.Add($ButtonExit)


# ---------------------------------------------------------------------------------------
## 3. הגדרת לוגיקת ה-Event Handlers
# ---------------------------------------------------------------------------------------

# לוגיקה לבחירת קבצים
$ButtonSelectFiles.Add_Click({
    $OpenDialog = New-Object System.Windows.Forms.OpenFileDialog
    $OpenDialog.Multiselect = $true
    $OpenDialog.Filter = "All Files (*.*)|*.*"
    $OpenDialog.Title = "בחר קבצים להטמעה"

    if ($OpenDialog.ShowDialog() -eq [System.Windows.Forms.DialogResult]::OK) {
        $global:SourceFiles = $OpenDialog.FileNames
        $TextBoxFiles.Text = "נבחרו $($global:SourceFiles.Count) קבצים: $($global:SourceFiles[0]) ..."
    } else {
        $global:SourceFiles = @()
        $TextBoxFiles.Text = "לא נבחרו קבצים"
    }
})

# לוגיקה לבחירת תיקיית פלט (היעד שיוטמע בסקריפט)
$ButtonSelectFolder.Add_Click({
    $FolderDialog = New-Object System.Windows.Forms.FolderBrowserDialog
    $FolderDialog.Description = "בחר נתיב קשיח להטמעה בסקריפט החילוץ"

    if ($FolderDialog.ShowDialog() -eq [System.Windows.Forms.DialogResult]::OK) {
        $TextBoxFolder.Text = $FolderDialog.SelectedPath
    }
})

# לוגיקה ליצירת הסקריפט
$ButtonGenerate.Add_Click({
    Generate-ExtractedScript -FilesToEmbed $global:SourceFiles -ExtractionPath $TextBoxFolder.Text -AdditionalCode $TextBoxCode.Text
})

# לוגיקה ליציאה מהטופס
$ButtonExit.Add_Click({
    $Form.Close()
})

# הצגת הטופס
$Form.ShowDialog() | Out-Null