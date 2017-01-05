# FlindersTheses-alma2equella

## Batch Process / Load / Harvest procedure

### High level

- Prepare XML bib records if required
- Prepare scanned files
- Run the processing script (produces embargoed and non-embargoed EBI CSV files)
- Copy EBI files to PC
- Load into Equella via EBI
- Harvest bibs into Alma/Primo

### Detailed level

Pre-requisites:
- Extract new set of XML bib metadata from Alma (if recent metadata updates).
- Append MMS ID to each bib filename using: add_mmsid2filename.rb
- Extract the new batch of scanned files from "Digitised" folder (shared drive).

If you are verifying filenaming and metadata aspects and so do not require
the scanned files for EBI loading, you can create zero-byte version of each
scan file (with the correct timestamp) by:
- using Busybox "ls -e > FILE_LIST" (under MobaXterm, Cygwin or similar)
- Transfer FILE_LIST from your local Windows PC to the Linux host
- Create the file list:
```
cd ~/ThesisScanPrj/alma2equella/src/digitised
touch_file_list.sh FILE_LIST
```

Process the batch of scanned files on Linux host:
* Process the scanned thesis files. Redirect stdout & stderr for later inspection.
```
time ~/ThesisScanPrj/alma2equella/bin/process_almaxml_wrap.sh 2> iii.err |tee iii.log
```
- Inspect iii.log & iii.err & bibs_fix.err
- Check for file naming errors, MMS ID errors, etc
- Check that the following match the expected results.
  * file-count
  * thesis-count
  * XML 502.type.fixed1 (EBI @selected_type)
  * XML degree_category.fixed1
- Check that none of the following are present.
  * Fields containing "UNKNOWN".
  * Fields containing "[manuscript]".
  * XML fields containing unescaped double-quotes (which will be badly
    escaped within CSV files)
```
awk -F\" '/<meta tagcode.*(fixed|cleaned)/ {print NF}' 99*.xml |sort -n |uniq -c
```
- Check if there are any embargoed records (separate EBI CSV file in separate directory).

Load the batch of scanned files on the Windows PC:
- Copy thesis_*.csv files from linux host to PC.
  * Sanity check in spreadsheet
- Run EBI app
  * Connection tab
    + Institution URL: https://my_equella_server.example.com
    + Username: MyUsername
    + Password: MyPassword
    + Click "Test / Get collections"
    + Collection: "Theses: Scanned"
  * CSV tab
    + Click Browse then navigate to theses_ebi.csv created above
    + fake.X.ref_no: Column Data Type - Ignore
    + keyword: Delimiter - "|"
    + subject: Delimiter - "|"
    + uuid: Delimiter - "|"; Column Data Type - Attachment Locations
- Equella:
  * Check record count
  * Check subset of records
  * Check harvest count
- Run Alma harvest
  * Check record count
  * Check subset of records
- Run Primo harvest
  * Check subset of records
- Post import tasks
  * Provide call numbers to Collection Maintenance team
  * Move scan file batch to next workflow folder
  * Copy EBI log & 2x CSV to some standard location

Harvest...

