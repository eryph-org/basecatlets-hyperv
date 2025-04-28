
powershell_script 'removing recovery partition' do
    code <<-EOH
    get-partition | where Type -eq Recovery | Remove-Partition -Confirm:$false

    EOH

end