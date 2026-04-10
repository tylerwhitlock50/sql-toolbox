Option Explicit
Sub SkipEmail()
'Set up error handling
'On Error GoTo Quit

'Declare variables
    Dim ErrMsg As String
    Dim cell As Range
    Dim x As Integer
    Dim SQL1 As String, SQL2 As String, SQL3 As String, DistDate As String, InvStr As String
    Dim strServerName As String, strDatabase As String, strUsername As String, strPassword As String, strCnn As String
    Dim MsgResponse As VbMsgBoxResult
    Dim rs As Variant
    
    
'Compile list of invoices for update
ErrMsg = "Checking table for flags . . ."
    x = 0
    For Each cell In Range("Table1[Exclude]")
        If cell.Text <> "" Then
            x = x + 1
            InvStr = InvStr & cell.Offset(0, -11) & "','"
        End If
    Next
    If x = 0 Then
        MsgBox "There were no records found to process.  No changes made to database.", vbInformation, "Process aborted"
    Else
        InvStr = Left(InvStr, Len(InvStr) - 2)
'Compile update strings
ErrMsg = "Compiling SQL strings . . ."
        DistDate = Format(Date, "yyyy-mm-dd")
        
        SQL1 = "UPDATE SHIPPER_INVOICE SET DISTRIBUTED_DATE='" & DistDate & "' WHERE INVOICE_ID IN ('" & InvStr & ") AND DOCUMENT_ID IS NOT NULL AND DISTRIBUTED_DATE IS NULL;"
        SQL2 = "UPDATE RECEIVABLE SET DISTRIBUTED_DATE='" & DistDate & "' WHERE INVOICE_ID IN ('" & InvStr & ") AND DOCUMENT_ID IS NOT NULL AND DISTRIBUTED_DATE IS NULL;"
        SQL3 = "UPDATE SHIPPER SET DISTRIBUTED_DATE='" & DistDate & "' WHERE INVOICE_ID IN ('" & InvStr & ") AND DOCUMENT_ID IS NOT NULL AND DISTRIBUTED_DATE IS NULL;"
        
        MsgResponse = MsgBox("The script found " & x & " record(s) flagged for email bypass." & vbCr & vbCr & "Do you wish to proceed?", vbYesNo, "Bes' check yo'self . . .")
        
        If MsgResponse = vbYes Then

'Preparing the connection string statements
ErrMsg = "Prepping connection string . . ."
            strServerName = "3CARMS\CAPROD"
            strDatabase = "VECA"
            strUsername = "SYSADM"
            strPassword = "SYSADM"
        
            strCnn = "Driver={SQL Server};Server=" & strServerName & ";Database=" & strDatabase & ";Uid=" & strUsername & ";Pwd=" & strPassword & ";"
            Set rs = CreateObject("ADODB.Recordset")

'Updating the database
ErrMsg = "Updating database . . ."
            rs.Open SQL1, strCnn
            rs.Open SQL2, strCnn
            rs.Open SQL3, strCnn
            
            Set rs = Nothing
            
            Range("table1[Exclude]").ClearContents
            MsgBox "Database updated.", vbInformation, "Process complete"
        Else
        
            MsgBox "Update process canceled.  No changes made to database.", vbInformation, "Process aborted"
        End If
    End If
Exit Sub

Quit:
    Err.Clear
    MsgBox "Script failed at " & ErrMsg & vbCr & vbCr & "Contact support for assistance.", vbCritical, "Process error"
    
End Sub
