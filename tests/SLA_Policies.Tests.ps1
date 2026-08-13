Describe "SLA Policies" {
    InModuleScope FreshservicePSU {
        BeforeDiscovery {
            Connect-FreshService -Name ItsFine_Prod -NoBanner
        }
        Context "View and List" {
            It "Get-FreshServiceSLAPolicy should return data" -Tag "SLA Policies" {
                $Script:SLAs = Get-FreshServiceSLAPolicy
                $SLAs | Should -Not -BeNullOrEmpty
            }
        }
    }
}
