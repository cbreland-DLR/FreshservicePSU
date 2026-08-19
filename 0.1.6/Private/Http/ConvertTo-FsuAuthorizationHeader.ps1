function ConvertTo-FsuAuthorizationHeader {
    <#
    .SYNOPSIS
        Builds a Freshservice Basic Authorization header from a SecureString API key.

    .DESCRIPTION
        Freshservice v2 authenticates with the API key as the Basic username
        and the literal 'X' as the password. The plaintext key exists only
        inside this call. Only the unmanaged BSTR produced by
        SecureStringToBSTR is explicitly zeroed, via ZeroFreeBSTR -- that is
        the one buffer this function can reliably clear. The managed
        $plain string and the UTF-8 byte array are ordinary .NET objects;
        the CLR does not guarantee zeroing or a bounded lifetime for them,
        and this function makes no claim that their memory is scrubbed.
        The return value is the header value 'Basic <base64>', which
        callers attach to a single request and must not log.
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory)]
        [securestring]$Secret,

        [string]$CorrelationId
    )

    $bstr = [IntPtr]::Zero
    try {
        $bstr = [System.Runtime.InteropServices.Marshal]::SecureStringToBSTR($Secret)
        $plain = [System.Runtime.InteropServices.Marshal]::PtrToStringBSTR($bstr)
        if ([string]::IsNullOrEmpty($plain)) {
            throw (New-FsuErrorRecord -ErrorId 'FreshservicePSU.Http.EmptySecret' -Message 'The resolved credential was empty.' -Category AuthenticationError -CorrelationId $CorrelationId)
        }

        $bytes = [System.Text.Encoding]::UTF8.GetBytes($plain + ':X')
        return 'Basic ' + [Convert]::ToBase64String($bytes)
    } finally {
        if ($bstr -ne [IntPtr]::Zero) {
            [System.Runtime.InteropServices.Marshal]::ZeroFreeBSTR($bstr)
        }
    }
}
