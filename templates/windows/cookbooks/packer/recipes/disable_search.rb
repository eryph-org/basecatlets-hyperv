# Disable WSearch. Side effect: avoids intermittent MSSrch_SysPrep_Cleanup
# (WindowsSearchEngine) failures during generalize when SearchIndexer.exe
# holds the registry/index files (0x5 / 0x7a).

service 'WSearch' do
  action [:stop, :disable]
  ignore_failure true
end
