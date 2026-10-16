import sys
url,key=(sys.argv[1:3]+["__SUPABASE_URL__","__SUPABASE_KEY__"])[:2] if len(sys.argv)>2 else ("__SUPABASE_URL__","__SUPABASE_KEY__")
s=open('template.html').read().replace('__DATA__',open('data.json').read()).replace('__SUPABASE_URL__',url).replace('__SUPABASE_KEY__',key)
open('index.html','w').write(s); print(len(s))
