#Usage:
#./gcvr_group -h input.html -O order_file -o output_file
#

import sys, getopt

argv = sys.argv[1:]

html_file = ''
output_file = ''
order_file = ''
html = []

opts, args = getopt.getopt(argv,"h:O:o:")

for opt, arg in opts:
        if opt == '-h':
                html_file = arg
        elif opt in ("-O"):
                order_file = arg
        elif opt in ("-o"):
                output_file = arg

if html_file == '':
	print ("You need to specify input file (-h)")
	exit(1)
if output_file == '':
	print ("you need to specify output file (-o)")
	exit(1)
if order_file == '':
	print ("you need to specify order file (-O)")
	exit(1)


with open(html_file, "r") as file:
	html.append(file.readline())

head=""
for i in range(0, 312):
	head += html[i]

nrEntry = 0
for line in html:
	if line.count("coverFile") > 0:
		nrEntry += 1
nrEntry -= 1
nr = 312
entryes = []
for i in range(0, nrEntry):
	row = ""
	for j in range (nr , nr+12):
		row += html[j]
	entryes.append(row)
	nr = nr + 14

bottom=""
for i in range(nr , len(html)):
	bottom += html[i]

order = []	
with open(order_file, "r") as file:
	order.append(file.readline())

for i in range(0 , len(order)):
	order[i]=order[i].replace("\n", "")

groupHead='''<tr>
      <td class="lineno"><pre>subs</pre></td>
      </tr>'''

newEntry=[]

for ordEntry in order:
	if ordEntry[0]=='#':
		newEntry.append(groupHead.replace("subs", ordEntry.replace("#", "")))
		continue
	else:
		for entry in entryes:
			if entry.count(ordEntry) > 0:
				newEntry.append(entry)
				entryes.remove(entry)
if len(entryes) > 0:
	newEntry.append(groupHead.replace("subs", "Others"))
	for entry in entryes:
		newEntry.append(entry)
body=""
for entry in newEntry:
	body += entry

newHtml = head + body + bottom

file = open(output_file, "w")

file.write(newHtml)
