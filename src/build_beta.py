import sys
url,key=(sys.argv[1],sys.argv[2]) if len(sys.argv)>2 else ("__SUPABASE_URL__","__SUPABASE_KEY__")
base=open('beta_template.html').read().replace('__DATA__',open('data.json').read()).replace('__SUPABASE_URL__',url).replace('__SUPABASE_KEY__',key)
open('beta_index.html','w').write(base.replace('__IS_BETA__','true'))
open('main_index.html','w').write(base.replace('__IS_BETA__','false').replace('<title>Versjakten BETA</title>','<title>Versjakten</title>'))
print(len(base))
open('admin_index.html','w').write(open('admin_template.html').read().replace('__SUPABASE_URL__',url).replace('__SUPABASE_KEY__',key))
