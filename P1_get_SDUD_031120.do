/***************************************************************************
Project: Medicaid Spending on 3 Drugs, Quarterly Updates

Purpose: This program pulls in all State Drug Utilization Data and subsets it to just keep records for
	buprenorphine, naloxone and naltrexone

Author: Marni Epstein

Date: October 24, 2018. Edited November 7, 2018. Edited by Emma Winiski on September 24, 2019.

Input files: Downloaded SDUD: Box Sync\LJAF Medicaid SDU\1 Data\State Drug Utilization Data\Downloaded 2018-11-07
			 NDC Codes: Box Sync\LJAF Medicaid SDU\1 Data\NDC numbers
			 Unsuppressed SDUD file from Alex Gertner
			 
Output files: intermediate.dta

Instructions and Notes:
	1. When new data comes out, save the SDUD CSV with the data through the new quarter over the old version. 
		Older quarters in that year will likely get updated when a new quarter comes out, so we want to replace the quarters we already have data for.
	2. Check if new drugs have come onto the market for buprenorphine, naloxone and naltrexone. 
			- search https://www.accessdata.fda.gov/scripts/cder/ndc/. Under "nonproprietary name" search for the three drugs.
			- Download the spreadsheet of all drugs and compare to the existing lists. Using an excel formula to see if each new NDC 
				is in the old list is helpful to find the new drugs. 
				Example excel formula where 1 means the drug is not already in the list: =IF(COUNTIF(range,value),"0","1")
			- If there are new drugs, add them to the spreadsheet that exists already. It is important to add them to the spreadsheet 
				rather than replace it, because if a drug gets taken off the market, it won't show up in the NDC directory after its 
				taken off the market. We want to keep the expired records in our list so that we pull the entries from earier years.
			- If you are unsure if a drug is used for the purpose we care about (i.e. MAT and not pain management), look up the drug label here:
				https://dailymed.nlm.nih.gov/dailymed/index.cfm. Look under "Indications and Use" for the primary purpose.
			- Check if new drugs are generic or brand name. If brand name, add to the list of brand name drugs in this program.
	3. Add the "use" and "generic" columns to the new drug entires. Also add "source" and "date added."
	4. If you save a new version of the NDC list, update the file name in this program. 

	Note: Per advice from John Holahan on July 23, 2018, we have decided against adjusting spending amounts. This way, we will be comparing actual Medicaid spending from year to year. In previous iterations, we used adjustments from the BLS
		that can be found at https://data.bls.gov/cgi-bin/surveymost?cu.  See the "Read Me" file in the 2017 Medicaid MAT OUD State Data folder for a more detailed explanation. 
	
	
				
*---- Search "CHANGE" to find the filenames to update in this program. ----*

***************************************************************************/


/***********************
SET GLOBALS - CHANGE
***********************/

*Enter user (computer name)
*global user = "EWiniski"
global user = "MEpstein"

*Enter last year and quarter that we have SDUD data 
global lastyr = 2019
global lastqtr = 3

*Enter download date of SDUD files. This should match the date on the folder name where the 
*files are saved as well as the download date in the file names which can be found here:
*Box Sync\LJAF Medicaid SDU\1 Data\State Drug Utilization Data
*For some reason, when we downloaded files as "CSV for Excel" some state totals were getting dropped out
*So downloaded everything just as a CSV, hopefully this will resolve that issue
global sdud_dwnld_date = "20200311"

*Enter computer drive
global drive = "D"


/****************************************************************
UPDATE DIRECTORIES - WILL UPDATE AUTOMATED BASED ON GLOBALS ABOVE
****************************************************************/
*Set directory and output folder
cd "${drive}:\Users\\${user}\Box\LJAF Medicaid SDU\2 Analysis\Quarterly Updates - Medicaid Spending on 3 Drugs\\${lastyr} Q${lastqtr}\Data"
global output "${drive}:\Users\\${user}\Box\LJAF Medicaid SDU\2 Analysis\Quarterly Updates - Medicaid Spending on 3 Drugs\\${lastyr} Q${lastqtr}\Output" 

*Source data
global sdud "${drive}:\Users\\${user}\Box\LJAF Medicaid SDU\1 Data\State Drug Utilization Data\Downloaded ${sdud_dwnld_date}"
global ndc "${drive}:\Users\\${user}\Box\LJAF Medicaid SDU\1 Data\NDC numbers"
global unsup "${drive}:\Users\\${user}\Box\LJAF Medicaid SDU\1 Data\State Drug Utilization Data\Unsuppressed data (CD) received 20200115\CSV files from CD"
global medicaid "${drive}:\Users\\${user}\\Box\LJAF Medicaid SDU\1 Data\Medicaid enrollment data"

**************************************************************************************************************************


/***********************************************************
Read in NDC codes for buprenorphine, naloxone and naltrexone
***********************************************************/

* Naloxone
import excel using "${ndc}\Naloxone_031120.xlsx", firstrow clear // <-- CHANGE filename to update
tab Use
keep if Use == "overdose"
gen drugtype = "naloxone"
save "naloxone_ndc.dta", replace

*Naltrexone
import excel using "${ndc}\Naltrexone_031120.xlsx", firstrow clear // <-- CHANGE filename to update
tab Use
keep if Use == "opioid blocker"
gen drugtype = "naltrexone"
save "naltrexone_ndc.dta", replace

*Buprenorphine
import excel using "${ndc}\Buprenorphine_031120.xlsx", firstrow clear // <-- CHANGE filename to update
tab Use
keep if Use == "treatment"
gen drugtype = "bup"
save "bup_ndc.dta", replace

*Concatenate datasets together for a list of all NDCs we want to keep
append using "naloxone_ndc.dta" "naltrexone_ndc.dta", force

*Split NDC on dash. Save as ndc_n for numeric
split NDCPackageCode, generate(ndc_n) parse("-") destring

*Pad with zeros to get to the 5-4-2 format
gen ndc_s1  = string(ndc_n1,"%05.0f")
gen ndc_s2  = string(ndc_n2,"%04.0f")
gen ndc_s3  = string(ndc_n3,"%02.0f")

*Create NDC-11 string
egen ndc_s11 = concat(ndc_s1 ndc_s2 ndc_s3)
sort ndc_s11

*Create NDC-9 string, which is just the labeler and product code (not the package code)
egen ndc_s9 = concat(ndc_s1 ndc_s2)

*Check for duplicate entries
duplicates report ndc_s11
duplicates tag ndc_s11, gen(dup)

*Drop duplicates, keeping the entry that is from the FDA site
drop if dup > 0 & Source != "FDA NDC Directory" 
list if dup > 0

*Make sure there are no duplicates left
drop dup
duplicates report ndc_s11
duplicates tag ndc_s11, gen(dup)

*Keep the key variables and save
keep Generic NDCPackageCode drugtype Source Secondarysource ndc_s11 ndc_s9 StartMarketingDate ApplNo Route DosageForm ProprietaryName LabelerName NonproprietaryName SubstanceName Strength PackageDescription
save "ndc_all.dta", replace

*Create short version that's just a list of ndc-9s
keep ndc_s9 Generic
duplicates drop ndc_s9, force
save "ndc_short.dta", replace

/*********************************************************
Read in SDUD and subset to NDC numbers from our list above
Save complete raw file and a version subset to just the three drugs of interest.
*********************************************************/
forvalues year = 1991/$lastyr {

	di "Year=`year'"
	
	*Assign string indicating how many quarters we have data for, to match the file name for SDUD files
	
	*If not the last year, create the string "Q1-Q4"
	if `year' < $lastyr {
		gl qtrname = "Q1-Q4"
	}
	*If the last year, assign either just "Q1" or "Q1-Q#", where Q# is the last quarter we have data for
	else if `year' == $lastyr {
		if $lastqtr == 1 {
			gl qtrname = "Q1"
		}
		else {
			gl qtrname = "Q1-Q${lastqtr}"
		}	
	}
	
	*di "Path = ${sdud}\State_Drug_Utilization_Data_${sdud_dwnld_date}_`year'_${qtrname}"
	
	*Note: Make sure there are no commmas in the numbers in the saved CSV
	import delimited using "${sdud}\State_Drug_Utilization_Data_${sdud_dwnld_date}_`year'_${qtrname}.csv", varnames(1) clear
	
	save "rawsdud_`year'.dta", replace
}


/** Check non-numeric values ***/
forvalues year = 1991/$lastyr {

	di "Year = `year'"
	use "rawsdud_`year'.dta", clear
	
	tostring labelercode productcode packagesize, replace
	
	gen byte notnumlab = real(labelercode)==.
	gen byte notnumprod = real(productcode)==.
	gen byte notnumpack = real(packagesize)==.

	tab notnumlab
	list if notnumlab == 1
	
	tab notnumprod
	list if notnumprod == 1
	
	tab notnumpack
	list if notnumpack == 1
}


/**** Subset to just buprenorphine, naltrexone or naloxone ****/
forvalues year = 1991/$lastyr {

	di "Year = `year'"
	use "rawsdud_`year'.dta", clear
	
	*Create NDC-11 and NDC-9 string variables. Force specifies that non-numeris be turned into missing values
	*Pad with zeros to get to the 5-4-2 format
	destring labelercode productcode packagesize, replace force
	
	gen ndc_s1  = string(labelercode,"%05.0f")
	gen ndc_s2  = string(productcode,"%04.0f")
	gen ndc_s3  = string(packagesize,"%02.0f")
	
	egen ndc_s11 = concat(ndc_s1 ndc_s2 ndc_s3)
	sort ndc_s11

	*Create string ndc short which is just the labeler and product code (not the package code, whcih only tells us about size)
	egen ndc_s9 = concat(ndc_s1 ndc_s2)
	
	*Take out commas in order to destring. A few years aren't strings and we get an error, so make sure they're all strings
	tostring unitsreimbursed numberofprescriptions totalamountreimbursed medicaidamountreimbursed nonmedicaidamountreimbursed, replace format(%20.2f) force
	foreach var in unitsreimbursed numberofprescriptions totalamountreimbursed medicaidamountreimbursed nonmedicaidamountreimbursed {
		replace `var' = subinstr(`var', ",", "", .)
	}
	
	destring unitsreimbursed numberofprescriptions totalamountreimbursed medicaidamountreimbursed nonmedicaidamountreimbursed, replace force
	
	*Save full dataset
	save "rawsdud_clean_`year'", replace

	*Merge with NDC-9 list to keep only the drugs that are on this NDC-9 list
	di "Merge with NDC-9 list"
	merge m:1 ndc_s9 using "ndc_short.dta"
	keep if _m == 3
	drop _m
	
	*Merge with full NDC data on NDC-11 to get the info on the NDCs
	di "Merge with NDC-11 list to get NDC info"
	merge m:1 ndc_s11 using "ndc_all.dta"
	
	*_m = 1 are obs where we have the NDC-9 but no info for that NDC-11 in our NDC list. Keep
	drop if _m == 2
	drop _m

	
	save "sdud`year'", replace

}




* Concatenate datasets. Use force to force different length variables to merge. 
* If there is a numeric/string mismatch, this will also force the numeric variable to string
clear
use "sdud2019"
append using "sdud2018", force
append using "sdud2017", force
append using "sdud2016", force
append using "sdud2015", force
append using "sdud2014", force
append using "sdud2013", force
append using "sdud2012", force
append using "sdud2011", force
append using "sdud2010", force
append using "sdud2009", force
append using "sdud2008", force
append using "sdud2007", force
append using "sdud2006", force
append using "sdud2005", force
append using "sdud2004", force
append using "sdud2003", force
append using "sdud2002", force
append using "sdud2001", force
append using "sdud2000", force
append using "sdud1999", force
append using "sdud1998", force
append using "sdud1997", force
append using "sdud1996", force
append using "sdud1995", force
append using "sdud1994", force
append using "sdud1993", force
append using "sdud1992", force
append using "sdud1991", force

*For some data downloads, some years have this weird formatting in the variable name. Comment out if not applicable this quarter
*rename ïutilizationtype utilizationtype

*Check for duplicates by NDC, utilization type, state, year and quarter
duplicates list ndc_s11 utilizationtype state year quarter
duplicates tag ndc_s11 utilizationtype state year quarter, gen(dup)
list if dup > 0

*There is one duplicate entry for KY MCOU 2014 Q4 Revia, but all the fields are suppressed.
*Keep only one of the duplicate entries
duplicates drop ndc_s11 utilizationtype state year quarter, force
drop dup

save "sdud_alldownloaded", replace

*Save full datasets

* Concatenate datasets. Use force to force different length variables to merge. 
* If there is a numeric/string mismatch, this will also force the numeric variable to string
clear
use "rawsdud_clean_2019"
append using "rawsdud_clean_2018", force
append using "rawsdud_clean_2017", force
append using "rawsdud_clean_2016", force
append using "rawsdud_clean_2015", force
append using "rawsdud_clean_2014", force
append using "rawsdud_clean_2013", force
append using "rawsdud_clean_2012", force
append using "rawsdud_clean_2011", force
append using "rawsdud_clean_2010", force
append using "rawsdud_clean_2009", force
append using "rawsdud_clean_2008", force
append using "rawsdud_clean_2007", force
append using "rawsdud_clean_2006", force
append using "rawsdud_clean_2005", force
append using "rawsdud_clean_2004", force
append using "rawsdud_clean_2003", force
append using "rawsdud_clean_2002", force
append using "rawsdud_clean_2001", force
append using "rawsdud_clean_2000", force
append using "rawsdud_clean_1999", force
append using "rawsdud_clean_1998", force
append using "rawsdud_clean_1997", force
append using "rawsdud_clean_1996", force
append using "rawsdud_clean_1995", force
append using "rawsdud_clean_1994", force
append using "rawsdud_clean_1993", force
append using "rawsdud_clean_1992", force
append using "rawsdud_clean_1991", force

save "rawsdud_clean_1991-2019Q3.dta", replace

forvalues year = 1995/$lastyr {
	export delimited if year == `year' using "rawsdud_clean_`year'.csv", replace
}

/****************************************************************
2019 Q3 / 3/11/20 data download:
There are NO SUPPRESSED OBSERVATIONS in the public SDUD files
There is nothing on the website about this, since ususally all obs with prescriptions < 11 are fully suppressed
We don't use the unsuppressed data that we purchased from CMS or the unsuppressed data from Alex Gertner
	since we have zero suppressed observations from the public file
NOTE: about a week after downloading this file it was taken down by CMS and replaced with a file with the normal suppression rules/
****************************************************************/

/* STAR OUT CODE WHERE WE MERGE IN UNSUPPPRESSED FILES

/****************************************************************
Merge in unsuppressed data that we purchased from CMS
CMS sent us this file in Jan 2020 with data 2014-2018
****************************************************************/
tempfile temp1
forvalues year = 2014/2018 {

	di "year == `year'"
	import delimited using "${unsup}/lds_drug_util_`year'_byst.csv", clear
		rename v1 utilizationtype
		rename v2 state
		rename v3 labelercode
		rename v4 productcode
		rename v5 packagesize
		rename v6 year_quarter
		rename v7 productname
		rename v8 unitsreimbursed
		rename v9 numberofprescriptions
		rename v10 totalamountreimbursed
		rename v11 medicaidamountreimbursed
		rename v12 nonmedicaidamountreimbursed
		
		
	*Replace a few weird values in 2014 and 2017
		if `year' == 2014 {
			replace productcode = 780 if productcode == -780
			replace productcode = 453 if productcode == -453
			replace packagesize = "5" if packagesize == "5-"
			replace packagesize = "7" if packagesize == "7-"
		}
		if `year' == 2017 {
			replace packagesize = "9" if packagesize == "9M"
		}
		
		destring productcode, replace
		destring packagesize, replace
	
	if `year' == 2014 {
		save "`temp1'"
	}
	else {
		append using "`temp1'", force
		save "`temp1'", replace
	}

}

tostring year_quarter, replace
generate year = substr(year_quarter, 1, 4)
generate quarter = substr(year_quarter, 6, 1)
destring year quarter, replace

save "unsupp_states_CMS.dta", replace

*Read in national total data
tempfile temp1
forvalues year = 2014/2018 {

	di "year == `year'"
	import delimited using "${unsup}/lds_drug_util_`year'_natl.csv", clear
		rename v1 utilizationtype
		rename v2 labelercode
		rename v3 productcode
		rename v4 packagesize
		rename v5 year_quarter
		rename v6 productname
		rename v7 unitsreimbursed
		rename v8 numberofprescriptions
		rename v9 totalamountreimbursed
		rename v10 medicaidamountreimbursed
		rename v11 nonmedicaidamountreimbursed
	
		*Replace a few weird values in 2014 and 2017
		if `year' == 2014 {
			replace productcode = 780 if productcode == -780
			replace productcode = 453 if productcode == -453
			replace packagesize = "5" if packagesize == "5-"
			replace packagesize = "7" if packagesize == "7-"
		}
		if `year' == 2017 {
			replace packagesize = "9" if packagesize == "9M"
		}
		
		destring productcode, replace
		destring packagesize, replace
		
	if `year' == 2014 {
		save "`temp1'"
	}
	else {
		append using "`temp1'", force
		save "`temp1'", replace
	}

}

tostring year_quarter, replace
generate year = substr(year_quarter, 1, 4)
generate quarter = substr(year_quarter, 6, 1)
destring year quarter, replace

gen state = "XX"

append using "unsupp_states_CMS.dta"

*Create NDC-11 and NDC-9 string variables. 
	destring labelercode, replace force
	destring productcode, replace force
	destring packagesize, replace force
	
	gen ndc_s1  = string(labelercode,"%05.0f")
	gen ndc_s2  = string(productcode,"%04.0f")
	gen ndc_s3  = string(packagesize,"%02.0f")
	replace ndc_s3 = "" if ndc_s3 == "."

	egen ndc_s11 = concat(ndc_s1 ndc_s2 ndc_s3)
	egen ndc_s9 = concat(ndc_s1 ndc_s2)
	order state ndc_s11 year quarter
	sort state ndc_s11 year quarter

*Save full unsuppressed file from CMS, states and national totals
save "unsupp_all_CMS.dta", replace

use "unsupp_all_CMS.dta", clear
*Merge with NDC list and only keep NDCs of interest
	merge m:1 ndc_s9 using "ndc_short.dta"
	keep if _m == 3
	drop _m


*Rename the 5 unsuppressed variables
rename units units_unsuppressed
rename numberofprescriptions rx_unsuppressed
rename totalamountreimbursed totalamount_unsuppressed
rename medicaidamountreimbursed medicaidspend_unsuppressed
rename nonmedicaidamountreimbursed nonmedicaidspend__unsuppressed

label variable units_unsuppressed "Unsuppressed units from CMS file"
label variable rx_unsuppressed "Unsuppressed prescriptions from CMS file"
label variable totalamount_unsuppressed "Unsuppressed total amount spent from CMS file"
label variable medicaidspend_unsuppressed "Unsuppressed Medicaid amount spent from CMS file"
label variable nonmedicaidspend__unsuppressed "Unsuppressed non-Medicaid amount spent from CMS file"

*Merge in with main dataset
merge 1:1 ndc_s11 utilizationtype state year quarter using "sdud_alldownloaded.dta"

* _m == 1 are observations in the suppressed dataset that aren't in the most recent SDUD download - don't keep
* _m == 2 are observations in SDUD download that aren't in the unsuppressed file, mostly from years outside of 2014-2018
tab _m year
drop if _m == 1
drop _m


*Convert upper case to lowercase for the suppression used variable
replace suppressionused = lower(suppressionused)
tab suppressionused, m

*For the suppressed cells we're going to replace with the CMS unsuppressed data, check if prescription counts are over 10
tab year if suppressionused == "true" & !missing(rx_unsuppressed) 
tab rx_unsuppressed if suppressionused == "true" & !missing(rx_unsuppressed) 
tab rx_unsuppressed if suppressionused == "true" & !missing(rx_unsuppressed) & state != "XX"

*90% of all suppressed matches have rx counts under 10, and 89.9% of all state entries
count if suppressionused == "true" & rx_unsuppressed != . & rx_unsuppressed < 11

/**********************************
Use the unsuppressed data from CMS for cells that are suppressed in the most recent data download 
	AND the prescription count in the unsupprssed file is under 11
**********************************/
replace numberofprescriptions = rx_unsuppressed if suppressionused == "true" & rx_unsuppressed != . & rx_unsuppressed < 11
replace unitsreimbursed = units_unsuppressed if suppressionused == "true" & units_unsuppressed != . & rx_unsuppressed < 11
replace totalamountreimbursed = totalamount_unsuppressed if suppressionused == "true" & totalamount_unsuppressed != . & rx_unsuppressed < 11
replace medicaidamountreimbursed = medicaidspend_unsuppressed if suppressionused == "true" & medicaidspend_unsuppressed != . & rx_unsuppressed < 11
replace nonmedicaidamountreimbursed = nonmedicaidspend__unsuppressed if suppressionused == "true" & nonmedicaidspend__unsuppressed != . & rx_unsuppressed < 11

*Indicate which observations have unsuppressed data from the CMS file. 
replace suppressionused = "CMS unsuppressed data" if suppressionused == "true" & rx_unsuppressed != . & rx_unsuppressed < 11
tab year suppressionused, m

/**********************************
For suppressed data where the unsuppressed data from CMS has a prescription count over 10, 
	calculate the total and Medicaid spending per prescription. 
	We will use this to calculate spending after imputing prescriptions
**********************************/
count if suppressionused == "true" & rx_unsuppressed != . & rx_unsuppressed >= 11
generate totalamount_perrx = totalamount_unsuppressed / rx_unsuppressed if suppressionused == "true" & totalamount_unsuppressed != . & rx_unsuppressed >= 11
generate medicaidamount_perrx = medicaidspend_unsuppressed / rx_unsuppressed if suppressionused == "true" & medicaidspend_unsuppressed != . & rx_unsuppressed >= 11
generate units_perrx = units_unsuppressed / rx_unsuppressed if suppressionused == "true" & units_unsuppressed != . & rx_unsuppressed >= 11
generate calctotspend_afterimprx = 1 if suppressionused == "true" & totalamount_unsuppressed != . & rx_unsuppressed >= 11

label variable totalamount_perrx "Unsup total spending per rx for unsup rx > 11. Calc total spending using imprx"
label variable medicaidamount_perrx "Unsup Medicaid spending per rx for unsup rx > 11. Calc total spending using imprx"
label variable units_perrx "Unsup units per rx for unsup rx > 11. Calc total spending using imprx"
label variable calctotspend_afterimprx "Indicator for unsuppressed values with rx > 11, cal spending after imputing rx"

 *Drop unsuppressed variables since we've replaced suppressed values with them
drop units_unsuppressed rx_unsuppressed totalamount_unsuppressed medicaidspend_unsuppressed nonmedicaidspend__unsuppressed

*Save dataset with CMS unsuppressed data
save "sdud_cms_unsup.dta", replace





/****************************************************************
Merge in unsuppressed data from Alex Gertner. His data is 1991 to 2018 Q2
CMS sent him this file in Feb 2019.
NOTE: This is a single file that we have been copying and pasting from each quarterly update. 
****************************************************************/
use "SDUD_unsuppressed_all.dta", clear

tostring year_quarter, replace
generate year = substr(year_quarter, 1, 4)
generate quarter = substr(year_quarter, 5, 1)
destring year quarter, replace
tab year quarter

*We only want to keep this data for until 2013, since we have more recent unsuppressed datafor 2014-2018 
keep if 2013 <= year 
tab year quarter

*Rename the 5 unsuppressed variables
rename units units_unsuppressed
rename prescriptions rx_unsuppressed
rename total_reimbursed totalamount_unsuppressed
rename medicaid_reimbursed medicaidspend_unsuppressed
rename nonmedicaid_reimbursed nonmedicaidspend__unsuppressed

rename utilization_type utilizationtype

*Only keep these 5 variables and the variables we'll use to merge with the main data file
keep ndc_s11 utilizationtype state year quarter units_unsuppressed rx_unsuppressed ///
	totalamount_unsuppressed medicaidspend_unsuppressed nonmedicaidspend__unsuppressed

*There are no national totals in Alex's data because all cells are unsuppressed. Add states up to get national totals
tempfile temp1
save "`temp1'"
collapse (sum) units_unsuppressed rx_unsuppressed totalamount_unsuppressed medicaidspend_unsuppressed nonmedicaidspend__unsuppressed, ///
	by(utilizationtype ndc_s11 year quarter)
gen state = "XX"
append using "`temp1'"

label variable units_unsuppressed "Unsuppressed units from file from Alex Gertner"
label variable rx_unsuppressed "Unsuppressed prescriptions from file from Alex Gertner"
label variable totalamount_unsuppressed "Unsuppressed total amount spent from file from Alex Gertner"
label variable medicaidspend_unsuppressed "Unsuppressed Medicaid amount spent from file from Alex Gertner"
label variable nonmedicaidspend__unsuppressed "Unsuppressed non-Medicaid amount spent from file from Alex Gertner"


*Merge 
merge 1:1 ndc_s11 utilizationtype state year quarter using "sdud_cms_unsup.dta"

* _m == 1 are observations in Alex's dataset that aren't in the most recent SDUD download - don't keep
* _m == 2 are observations in SDUD download that aren't in Alex's unsuppressed file
drop if _m == 1
drop _m


*For the suppressed cells that are still missing, we'll use Alex's unsuppressed data.
*Check if prescription counts are over 10
tab rx_unsuppressed if suppressionused == "true" & !missing(rx_unsuppressed) 
tab rx_unsuppressed if suppressionused == "true" & !missing(rx_unsuppressed) & state != "XX" 

*90% of state suppressed records have rx < 11
count if suppressionused == "true" & rx_unsuppressed != . & rx_unsuppressed < 11

/**********************************
Use the unsuppressed data from Alex for cells that are suppressed in the most recent data download 
	AND the prescription count in the unsupprssed file from Alex is under 11
**********************************/
replace numberofprescriptions = rx_unsuppressed if suppressionused == "true" & rx_unsuppressed != . & rx_unsuppressed < 11
replace unitsreimbursed = units_unsuppressed if suppressionused == "true" & units_unsuppressed != . & rx_unsuppressed < 11
replace totalamountreimbursed = totalamount_unsuppressed if suppressionused == "true" & totalamount_unsuppressed != . & rx_unsuppressed < 11
replace medicaidamountreimbursed = medicaidspend_unsuppressed if suppressionused == "true" & medicaidspend_unsuppressed != . & rx_unsuppressed < 11
replace nonmedicaidamountreimbursed = nonmedicaidspend__unsuppressed if suppressionused == "true" & nonmedicaidspend__unsuppressed != . & rx_unsuppressed < 11

*Indicate which observations have unsuppressed data from Alex's file. 
replace suppressionused = "unsuppressed data from Alex" if suppressionused == "true" & rx_unsuppressed != . & rx_unsuppressed < 11
tab suppressionused, m
tab year suppressionused, m

/**********************************
For suppressed data where the unsuppressed data from Alex has a prescription count over 10, 
	calculate the total and Medicaid spending per prescription. 
	We will use this to calculate spending after imputing prescriptions
**********************************/
count if suppressionused == "true" & totalamount_unsuppressed != . & rx_unsuppressed >= 11
replace totalamount_perrx = totalamount_unsuppressed / rx_unsuppressed if suppressionused == "true" & totalamount_unsuppressed != . & rx_unsuppressed >= 11
replace medicaidamount_perrx = medicaidspend_unsuppressed / rx_unsuppressed if suppressionused == "true" & medicaidspend_unsuppressed != . & rx_unsuppressed >= 11
replace units_perrx = units_unsuppressed / rx_unsuppressed if suppressionused == "true" & units_unsuppressed != . & rx_unsuppressed >= 11
replace calctotspend_afterimprx = 1 if suppressionused == "true" & totalamount_unsuppressed != . & rx_unsuppressed >= 11

 *Drop unsuppressed variables since we've replaced suppressed values with them
drop units_unsuppressed rx_unsuppressed totalamount_unsuppressed medicaidspend_unsuppressed nonmedicaidspend__unsuppressed


* END CODE WHERE WE MERGE IN SUPPRESSED FILES */ 

/***************************************
Add in variable for generic indicator
***************************************/
use "sdud_alldownloaded.dta", clear

gen genericindicator = Generic == "generic"
label define genericlab 0 "Brand name" 1 "Generic"
label values genericindicator genericlab
tab genericindicator, m

*Rename variables to a shorter name
rename numberofprescriptions rx
rename unitsreimbursed units

save "intermediate.dta", replace






/****************************************************************************
Read in Medicaid enrollment estimates and format to merge with larger dataset
****************************************************************************/

*Format quarterly Medicaid enrollment numbers
use "${medicaid}\Medicaid_enrollment_final_12720.dta", clear

keep state Q*
order _all, sequential
order state, first

*Rename variables for reshape
forvalues q = 1/4 {
	forvalues y = 2010/2019{
		rename Q`q'_`y'_final medicaid_Q`q'_`y'
	}
}

reshape long medicaid_Q, i(state) j(qtr_yr) string

gen quarter = substr(qtr_yr, 1, 1)
gen year = substr(qtr_yr, 3, 4)

drop qtr_yr

destring year quarter, replace

*Collapse to calculate national totals
tempfile temp1
save "`temp1'"
collapse (sum) medicaid_Q, by(year quarter)
gen state = "XX"
append using "`temp1'"

order state year quarter medicaid_Q
sort state year quarter

save "Medicaid_quarterly.dta", replace


*Format annual Medicaid enrollment numbers
use "${medicaid}\Medicaid_enrollment_final_12720.dta", clear

keep state annual*

reshape long annual_, i(state) j(year_str) string

gen year = substr(year_str, 1, 4)

drop year_str
rename annual_ medicaid_A

*Collapse to calculate national totals
tempfile temp1
save "`temp1'"
collapse (sum) medicaid_A, by(year)
gen state = "XX"
append using "`temp1'"

order state year medicaid_A
sort state year 
destring year, replace

save "Medicaid_annual.dta", replace


