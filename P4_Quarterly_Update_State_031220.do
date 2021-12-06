/***************************************************************************
Project: Medicaid Spending on 3 Drugs, Quarterly Updates

Purpose: This program summarizes SDUD on buprenorphine, naloxone and naltrexone to the state level.

Author: Marni Epstein

Date: January 16, 2018
Updated: March 2020

Input files: allSDUD_rebate.dta

Instructions and Notes:
	1. Update the globals at the top of the program. Everything else will update automatically.
	2. Create the appropriate subfolders within the Output folder. 
		Create two folders called "COMMS Data Viz" and "Data Catalog Uploads." Within the "COMMS Data Viz" folder,
		create a subfolder called "Output_{DATE}" where date is the current date. 
		Create a new COMMS folders when re-outputting so as to not write over previous version in case there is any confusion with the website.
	
***************************************************************************/

/***********************
SET GLOBALS - CHANGE
***********************/

*Enter user (computer name)
*global user = "EWiniski"
global user = "MEpstein"

*Enter whether you are using Box or Box Sync
global box = "Box"
*global box = "Box Sync"

*Enter last year and quarter that we have SDUD data 
global lastyr = 2019
global lastqtr = 3

*Enter today's date to create unique log
global today=031220

*Enter subfolder for COMMS data viz output. This should be within Output/COMMS Data Viz 
global comms = "Outout_030320"  // <------------ CHANGE FILE PATH

*Enter drive letter
*global drive = "C"
global drive = "D"

/****************************************************************
UPDATE DIRECTORIES - WILL UPDATE AUTOMATED BASED ON GLOBALS ABOVE
****************************************************************/

cd "${drive}:\Users\\${user}\\${box}\LJAF Medicaid SDU\2 Analysis\Quarterly Updates - Medicaid Spending on 3 Drugs\\${lastyr} Q${lastqtr}\Data"
global commsoutput "${drive}:\Users\\${user}\\${box}\LJAF Medicaid SDU\2 Analysis\Quarterly Updates - Medicaid Spending on 3 Drugs\\${lastyr} Q${lastqtr}\Output\COMMS Data Viz\\${comms}" 
global log "${drive}:\Users\\${user}\\${box}\LJAF Medicaid SDU\2 Analysis\Quarterly Updates - Medicaid Spending on 3 Drugs\\${lastyr} Q${lastqtr}\Logs" 
global datacat "${drive}:\Users\\${user}\\${box}\LJAF Medicaid SDU\2 Analysis\Quarterly Updates - Medicaid Spending on 3 Drugs\\${lastyr} Q${lastqtr}\Output\Data Catalog Uploads"
global output "${drive}:\Users\\${user}\Box\LJAF Medicaid SDU\2 Analysis\Quarterly Updates - Medicaid Spending on 3 Drugs\\${lastyr} Q${lastqtr}\Output"

 *Create global for current year and quarter
global yearquarter = "${lastyr}Q${lastqtr}"

*Turn log on
log using "${log}\P3_quarterly_update_state_${today}.log",  replace


/******************************************************
Create shell to fill in missing quarters with zeros
Use dataset with imputed RX values for suppressed cells
*******************************************************/
	use "allSDUD_rebate.dta", clear
	
	*If data is suppressed, the number of units, prescriptions and Medicaid amount reimbursed will be missing
	*We have to treat them as zero in order to sum
	replace units = 0 if units == .
	replace imprx = 0 if imprx == .
	replace adjmedamt = 0 if adjmedamt == .
	replace unadjmedamt = 0 if unadjmedamt == .

	*Collapse to have one obs per State-Year-Quarter-type of drug-generic with the sum of the number of prescriptions, units and total spending
	collapse (sum) units imprx adjmedamt unadjmedamt, by (state year quarter drugtype)

	*Save data to  merge back on to shell 
	keep if year == 2017 //this year has 156 obs (3 drugs * 52 states) for all quarters
	keep state year quarter drugtype
	replace year = 2010
	
	*Replicate for all years 
	*Save original version to copy
	tempfile base
	save "`base'"

	forvalues num = 2011/$lastyr{
		
		*Save current version, to add new year onto
		tempfile toappend
		save "`toappend'"
		
		use "`base'", clear
		replace year = `num'
		append using "`toappend'"
	}

	*Add in both values for the generic indicator
	gen genericind = "generic" 
	tempfile temp
	save "`temp'"
	replace genericind = "brand"
	append using "`temp'"

	*Check that there are 8 quarters of data for all states per drug type in all years (4 quarters*2 types of generic indicator)
	bys year: tab state drugtype

	*Save shell with all quarters by drug and by generic/brand
	save "shell_drug_generic.dta", replace

/**************************************
(1) Quarterly by drug by generic status
**************************************/

*Merge shell back onto original data
use "allSDUD_rebate.dta", clear

drop genericindicator
gen genericind = "generic" if Generic == "generic"
replace genericind = "brand" if genericind == ""
label variable genericind "Generic indicator"

gen byte units_missing = missing(units)
gen byte imprx_missing = missing(imprx)
gen byte adjmedamt_missing = missing(adjmedamt)
gen byte unadjmedamt_missing = missing(unadjmedamt)

/************************************************************************
Generic - the variable in the NDC list either "generic" or the brand name.
Create an indicator that either generic or brand
*************************************************************************/

*Collapse to have one obs per State-Year-Quarter-type-generic of drug with the sum of the number of prescriptions, units and total spending
collapse (sum) units units_missing imprx imprx_missing adjmedamt adjmedamt_missing unadjmedamt unadjmedamt_missing, by (state year quarter drugtype genericind)

*Drop national total data from SDUD. We want to use the sum of the states instead
drop if state == "XX"

*Add in the sum of the states
tempfile temp1
save "`temp1'"
collapse (sum) units units_missing imprx imprx_missing adjmedamt adjmedamt_missing unadjmedamt unadjmedamt_missing, by (year quarter drugtype genericind)
gen state = "XX"
append using "`temp1'"
tab state

*Indicate which sums are actually missing with a temporary value of 99999, since collapse marks them all as 0
replace units = 999999 if units == 0 & units_missing > 0
replace imprx = 999999 if imprx == 0 & imprx_missing > 0
replace adjmedamt = 999999 if adjmedamt == 0 & adjmedamt_missing > 0
replace unadjmedamt = 999999 if unadjmedamt == 0 & unadjmedamt_missing > 0

drop units_missing imprx_missing adjmedamt_missing unadjmedamt_missing

*Merge onto shell to create empty rows with values of 0 when there are no claims
*There should be no _m == 1 (data but no row in the shell)
*_m == 2 are states that have rows in the shell but no data
merge 1:m state year quarter drugtype genericind using "shell_drug_generic.dta"
drop _m
*bys year: tab state drugtype

*Replace missing values (meanning no claims for that state/quarter) with zeros
replace units = 0 if units == .
replace imprx = 0 if imprx == .
replace adjmedamt = 0 if adjmedamt == .
replace unadjmedamt = 0 if unadjmedamt == .

*Replace 99999s with missing, which means the quarter is fully suppressed
replace units = . if units == 999999
replace imprx = . if imprx == 999999
replace adjmedamt = . if adjmedamt == 999999
replace unadjmedamt = . if unadjmedamt == 999999

/*
*For now, we treat suppressed quarters and quarters with no entries as 0. Take this out if you want to differentiate between the two conditions
replace units = 0 if units == .
replace imprx = 0 if imprx == .
replace adjmedamt = 0 if adjmedamt == .
*/

*Collapse to get the totals for three drugs and merge it back onto this dataset
tempfile temp1
save "`temp1'"
collapse (sum) units imprx adjmedamt unadjmedamt, by (state year quarter genericind)
gen drugtype = "all"
append using "`temp1'"

*Add labels for the variables that are missing them
label variable drugtype "Drug type"
label variable units "Number of Units"
label variable imprx "Number of Prescriptions, Imputed for Suppressed cells"
label variable adjmedamt "Adjusted Medicaid amount spent (after rebate)"
label variable unadjmedamt "Unadjusted Medicaid amount spent (without rebate)"

*Add variable indicating which values will change in future revisions. Last year/quarter
gen futurerevision = "no"
replace futurerevision = "yes" if year == $lastyr & quarter >= $lastqtr

*Drop last year's quarters that we don't yet have data for (the shell fills in all 4 quarters with zerso)
drop if year == $lastyr & quarter > $lastqtr

*Sort and check a single year of a single state
sort state year quarter genericind drugtype
order state year quarter genericind drugtype units imprx adjmedamt
*br if year == 2019 & state == "AK"

*Export CSV of quarterly generic/brand name for COMMS
preserve
drop units
export delimited "${commsoutput}\Quarterly_bydrug_bygeneric_${yearquarter}.csv", replace 
restore

*Export CSV for the data catalog
preserve
drop units
rename imprx adjusted_prescriptions
rename adjmedamt adjusted_spending
rename unadjmedamt unadjusted_spending
export delimited "${datacat}\Quarterly_bydrug_bygeneric_${yearquarter}.csv", replace
restore

*Save
save "quarterly_drug_generic.dta", replace



/*************************************
(2) Annual by drug by generic status
*************************************/

/***********************************************************************************
If we are missing 1 quarters of the latest year, impute the missing quarter
based on the average percent change of the 4 previous quarters
Note: If you want to impute the last two quarters, add in "| $lastqtr == 3" to the top conditional statement
***********************************************************************************/

if $lastqtr == 4 {

	use "quarterly_drug_generic.dta", clear

	*Drop most recent quarter of data since we will be imputing it based on the average percent change
	drop if year == $lastyr & quarter == $lastqtr

	save "quarterly_drug_generic_wo_last_qtr.dta", replace

	egen yearquarter = concat(year quarter)

	/******
	Create globals indicating the last 4 quarters. 
	Note that this does not include the actual last quarter, since we treat it as preliminary.
	******/
	gl secondtolastyr = $lastyr - 1

	*If the last quarter is 3, we start with quarter 3 in the previous year
	if $lastqtr == 3 {
		gl previousyr_1 = ${secondtolastyr}3
		gl previousyr_2 = ${secondtolastyr}4
		gl previousyr_3 = ${lastyr}1
		gl previousyr_4 = ${lastyr}2
	}
	*If the last quarter is 4, we start with quarter 4 in the previous year
	else if $lastqtr == 4 {
		gl previousyr_1 = ${secondtolastyr}4
		gl previousyr_2 = ${lastyr}1
		gl previousyr_3 = ${lastyr}2
		gl previousyr_4 = ${lastyr}3
	}
	di "4 quarters before the last quarter: $previousyr_1 $previousyr_2 $previousyr_3 $previousyr_4"

	*Only keep the last 4 quarters of data
	keep if inlist(yearquarter, "$previousyr_1", "$previousyr_2", "$previousyr_3", "$previousyr_4")
	drop year quarter futurerevision

	*Reshape to wide
	reshape wide units imprx adjmedamt, i(state genericind drugtype) j(yearquarter) string
	
	order state genericind drugtype units* imprx* adjmed*
	
	*Create percent change variables. If a quarter is 0 (which is suppressed or no entry for that quarter), don't calculate a percentage change
	foreach var in units imprx adjmedamt {
	
		*If there is a value that is entirely suppressed, use the value from the quarter before. 
		replace `var'${previousyr_2} = `var'${previousyr_1} if `var'${previousyr_2} == . & !missing(`var'${previousyr_1})
		replace `var'${previousyr_3} = `var'${previousyr_2} if `var'${previousyr_3} == . & !missing(`var'${previousyr_2})
		replace `var'${previousyr_4} = `var'${previousyr_3} if `var'${previousyr_4} == . & !missing(`var'${previousyr_3})
		
		gen `var'_perc_change_2 = `var'${previousyr_2} / `var'${previousyr_1} if `var'${previousyr_2} != 0 & `var'${previousyr_1} !=0
		gen `var'_perc_change_3 = `var'${previousyr_3} / `var'${previousyr_2} if `var'${previousyr_3} != 0 & `var'${previousyr_2} !=0
		gen `var'_perc_change_4 = `var'${previousyr_4} / `var'${previousyr_3} if `var'${previousyr_4} != 0 & `var'${previousyr_3} !=0
		
		*Note_ rowmean averages across non-missing observations
		egen `var'_avg_perc_change = rowmean(`var'_perc_change_2 `var'_perc_change_3 `var'_perc_change_4)
	}

	*Create inflated values for the quarters we're missing from the latest year by inflating the quarters based on the average percent change
	if $lastqtr == 4 {
		foreach var in units imprx adjmedamt {
			gen `var'${lastyr}4 = `var'${previousyr_4} * `var'_avg_perc_change
			
			*If the last quarter is missing but the second to last quarter is not, use that.
			replace `var'${lastyr}4 = `var'${previousyr_3} * `var'_avg_perc_change if `var'${previousyr_4} == . & !missing(`var'${previousyr_3})
		
		}
		keep state genericind drugtype units${lastyr}4 imprx${lastyr}4 adjmedamt${lastyr}4
	}
	else if $lastqtr == 3 {
		foreach var in units imprx adjmedamt {
			gen `var'${lastyr}3 = `var'${previousyr_4} * `var'_avg_perc_change
			gen `var'${lastyr}4 = `var'${lastyr}3 * `var'_avg_perc_change
		} 
		keep state genericind drugtype units${lastyr}4 imprx${lastyr}4 adjmedamt${lastyr}4 units${lastyr}3 imprx${lastyr}3 adjmedamt${lastyr}3
	}

	*Reshape back to long format to merge back in with the main dataset
	reshape long
	
	gen year = substr(yearquarter, 1, 4)
	gen quarter = substr(yearquarter, 5, 1)
	destring year quarter, replace
	drop yearquarter
	
	*Collapse to get the totals for three drugs so that they add up and merge it back onto this dataset
	drop if drugtype == "all"

	tempfile temp1
	save "`temp1'"
	collapse (sum) units imprx adjmedamt, by (state year quarter genericind)
	gen drugtype = "all"
	append using "`temp1'"

	*Merge with the main dataset and collapse to annual by drug
	append using "quarterly_drug_generic_wo_last_qtr.dta"
	
	*Save dataset with last quarter imputer based on the percent change in the previous 4 quarters
	save "quarterly_drug_generic_lastqtr_imputed.dta", replace

}

*If we only have 1 or 2 quarters of the latest year, use the original dataset and drop the last year for the annual estimates
if inlist($lastqtr, 1, 2, 3) {
		use "quarterly_drug_generic.dta", clear
		
		drop if year == $lastyr
}

*Make sure we have 4 quarters of data for all years
tab year quarter
tab state

*Make sure that there aren't any negative imprx values. This shouldn't happen, but for some reason it did one run for Sublocade so we want to double check
list state year quarter genericind drugtype imprx if imprx < 0
replace imprx = 0 if imprx < 0

*Collapse to the annual level, still by generic status
collapse (sum) units imprx adjmedamt unadjmedamt, by (state year drugtype genericind)
gen quarter = "all"

label variable state "State"
label variable year "Year"
label variable quarter "Quarter"
label variable units "Number of Units"
label variable imprx "Number of Prescriptions"
label variable adjmedamt "Adjusted Medicaid amount spent (after rebate)"
label variable unadjmedamt "Unadjusted Medicaid amount spent (without rebate)"


*Add variable indicating which values will change in future revisions, 
*which is the last year if we only have 1 quarter of the new year or 4 quarters and we inflate up
gen futurerevision = "no"
if inlist($lastqtr, 1, 4) {
	replace futurerevision = "yes" if year == $lastyr
}

sort state year genericind drugtype
order state year quarter genericind drugtype units imprx adjmedamt

*Export CSV of annual generic/brand name for COMMS
preserve
drop units
export delimited "${commsoutput}\Annual_bydrug_bygeneric_${yearquarter}.csv", replace 
restore

*Export CSV for the data catalog
preserve
drop units
rename imprx adjusted_prescriptions
rename adjmedamt adjusted_spending
rename unadjmedamt unadjusted_spending
export delimited "${datacat}/Annual_bydrug_bygeneric_${yearquarter}.csv", replace
restore

save "annual_bydrug_bygeneric.dta", replace

/**********************************************************
(3) Quarterly by drug (combined generic and brand)

We don't use the estimated latest quarter created in step 2, 
as those are only used in the annual estimates
**********************************************************/
use "quarterly_drug_generic.dta", clear

collapse (sum) units imprx adjmedamt unadjmedamt, by (state year quarter drugtype)
gen genericind = "all"

order state year quarter drugtype genericind

label variable units "Number of Units"
label variable imprx "Number of Prescriptions"
label variable adjmedamt "Adjusted Medicaid amount spent (after rebate)"
label variable unadjmedamt "Unadjusted Medicaid amount spent (without rebate)"


/**************************************************
Per Capita estimates - per 1,000 Medicaid enrollees
**************************************************/

merge m:1 state year quarter using "Medicaid_quarterly.dta"
drop _m

/*************************************************************
Calculate quarterly per cap. The 4 quarterly per cap estimates 
should sum to the annual estimate calcaulated later
*************************************************************/

gen percap_units = units / medicaid_Q * 1000
gen percap_rx = imprx / medicaid_Q * 1000
gen percap_adjmedamt = adjmedamt / medicaid_Q * 1000
gen percap_unadjmedamt = unadjmedamt / medicaid_Q * 1000

label variable medicaid_Q "Quarterly Medicaid enrollment"
label variable percap_units "Per capita units - quarterly per 1,000 Medicaid enrollees"
label variable percap_rx "Per capita prescriptions - quarterly per 1,000 Medicaid enrollees"
label variable percap_adjmedamt "Per capita adjusted Medicaid amount spent (after rebate) - quarterly per 1,000 Medicaid enrollees"
label variable percap_unadjmedamt "Per capita unadjusted Medicaid amount spent (without rebate) - quarterly per 1,000 Medicaid enrollees"

*Add variable indicating which values will change in future revisions. 
gen futurerevision = "no"
replace futurerevision = "yes" if year == $lastyr & quarter >= $lastqtr

*Drop the last year's quarters that we don't yet have data for (the shell fills in all 4 quarters with zeros)
drop if year == $lastyr & quarter > $lastqtr
drop if year < 2010

*Sort
sort state year quarter genericind drugtype
order state year quarter genericind drugtype units imprx adjmedamt

*Export CSV for COMMS
preserve
drop units medicaid_Q percap_units
export delimited "${commsoutput}\Quarterly_bydrug_${yearquarter}.csv", replace  /* CHANGE  file name */
restore

*Export CSV for the data catalog
preserve
drop units percap_units  
rename imprx adjusted_prescriptions
rename adjmedamt adjusted_spending
rename unadjmedamt unadjusted_spending
rename medicaid_Q quarterly_medicaid_enrollment
rename percap_adjmedamt percap_spending
export delimited "${datacat}/Quarterly_bydrug_${yearquarter}.csv", replace
restore

*Save
save "quarterly_drug.dta", replace

/************************************************
(4) Annual by drug (combined generic and brand)

Use the estimated last quarter created in Step 2 if we have three quarters of data
************************************************/
if $lastqtr == 4 {
	use "quarterly_drug_generic_lastqtr_imputed.dta", clear
}
else {
	use "quarterly_drug.dta", clear
	drop if year == $lastyr 
}

collapse (sum) units imprx adjmedamt unadjmedamt, by (state year drugtype)
gen quarter = "all"
gen genericind = "all"


/**************************************************
Per Capita estimates - per 1,000 Medicaid enrollees
**************************************************/
merge m:1 state year using "Medicaid_annual.dta"
drop _m

* Here we are using the total number of Medicaid enrollees, NOT the adjusted Medicaid OUD rate that was calculated in the last program
gen percap_units = units / medicaid_A * 1000
gen percap_rx = imprx / medicaid_A * 1000
gen percap_adjmedamt = adjmedamt / medicaid_A * 1000
gen percap_unadjmedamt = unadjmedamt / medicaid_A * 1000

sort state year genericind drugtype
order state year quarter genericind drugtype units imprx adjmedamt unadjmedamt percap_units percap_rx percap_adjmedamt percap_unadjmedamt

label variable quarter "Quarter"
label variable units "Number of Units"
label variable imprx "Number of Prescriptions"
label variable adjmedamt "Adjusted Medicaid amount spent (after rebate)"
label variable unadjmedamt "Unadjusted Medicaid amount spent (without rebate)"

label variable percap_units "Per capita units - annual per 1,000 Medicaid enrollees"
label variable percap_rx "Per capita prescriptions - annual per 1,000 Medicaid enrollees"
label variable percap_adjmedamt "Per capita adjusted Medicaid amount spent (after rebate) - annual per 1,000 Medicaid enrollees"
label variable percap_unadjmedamt "Per capita unadjusted Medicaid amount spent (without rebate) - annual per 1,000 Medicaid enrollees"
label variable medicaid_A "Annual Medicaid enrollment"

*Add variable indicating which values will change in future revisions. Last year if we have inflated that year (so if the last quarter isn't 1)
gen futurerevision = "no"
*All of last year will change if the last quarter of the last year is inflated
replace futurerevision = "yes" if year == $lastyr

*Sort
sort state year quarter genericind drugtype
order state year quarter genericind drugtype units imprx adjmedamt

*Export CSV of annual by drug for COMMS
preserve
drop units percap_units medicaid_A 
export delimited "${commsoutput}/Annual_bydrug_${yearquarter}.csv", replace 
restore

*Export CSV for the data catalog
preserve
drop units percap_units  
rename imprx adjusted_prescriptions
rename adjmedamt adjusted_spending
rename unadjmedamt unadjusted_spending
rename percap_adjmedamt percap_spending
rename medicaid_A annual_medicaid_enrollment
export delimited "${datacat}/Annual_bydrug_${yearquarter}.csv", replace
restore


/*******************************************
Add expansion status. 
States are grouped by Medicaid expansion status as either nonexpansion states, expansion states, or late expansion states.
Late expansion states are those that expanded Medicaid after April 2014, as reported by KFF 
https://www.kff.org/health-reform/state-indicator/state-activity-around-expanding-medicaid-under-the-affordable-care-act/?currentTimeframe=0&sortModel=%7B%22colId%22:%22Location%22,%22sort%22:%22asc%22%7D

As of 12/22/18:
•	Non-expansion states are: Alabama, Florida, Georgia, Kansas, Mississippi, Missouri, North Carolina, Oklahoma, South Carolina, South Dakota, Tennessee, Texas, Wisconsin, and Wyoming.
•	Expansion states are Arizona, Arkansas, California, Colorado, Connecticut, Delaware, District of Columbia, Hawaii, Illinois, Iowa, Kentucky, Maryland, Massachusetts, Michigan, Minnesota, Nevada, New Jersey, New Mexico, New York, North Dakota, Ohio, Oregon, Rhode Island, Vermont, Washington, and West Virginia.
•	Late-expansion states are New Hampshire (8/15/2014), Pennsylvania (1/1/2015), Indiana (2/1/2015), Alaska (9/1/2015), Montana (1/1/2016), Louisiana (7/1/2016), Virginia (enrollment began 11/1/2018 for coverage effective 1/1/2019), and Idaho, Maine, Nebraska, and Utah (to be determined).

******
******
******
Per an email from Jenny Kenney sent on 1/8/19, we are reclassifying the states included in the expansion status categories to be First, Second, and Third wave expanders as well as non-expanders
There is an excel sheet where LCC put all of the classifications, which is titled "Medicaid Expansion Decision Categories 2019-01-08" and can be found here:
Box Sync\LJAF Medicaid SDU\2 Analysis\Medicaid expansion status 

*******************************************/

*CHANGE if any new states expanded Medicaid

generate expansion=.
replace expansion=0 if inlist(state, "XX")
replace expansion=1 if inlist(state, "AZ", "AR", "CA", "CO", "CT", "DE") | inlist(state, "DC", "HI", "IL", "IA", "KY", "MD") | ///
	inlist(state, "MA", "MI", "MN", "NV", "NJ") | inlist(state, "NM", "NY", "ND", "OH", "OR", "RI") | inlist(state, "VT", "WA", "WV")
replace expansion=2 if inlist(state, "AK", "IN", "LA", "MT", "NH", "PA")
replace expansion=3 if inlist(state, "ME", "VA")
replace expansion=4 if inlist(state, "AL", "FL", "GA", "ID", "KS", "MS", "MO", "NE", "NC") | inlist(state, "OK", "SC", "SD", "TN", "TX", "UT", "WI", "WY")

label define explab 0 "US Total" 1 "1st Expansion" 2 "2nd Expansion" 3 "3rd Expansion" 4 "Non-Expansion"
label values expansion explab
label variable expansion "Expansion status"

*Check if any states weren't assigned an expansion status
tab state if expansion==.
tab state expansion

*Format drug names for figures
rename drugtype olddrugtype

gen drugtype = 0 if olddrugtype == "all"
replace drugtype = 1 if olddrugtype == "bup"
replace drugtype = 2 if olddrugtype == "naltrexone"
replace drugtype = 3 if olddrugtype == "naloxone"

label define drugval 0 "All drugs" 1 "Buprenorphine" 2 "Naltrexone" 3 "Naloxone"
label values drugtype drugval
label variable drugtype "Drug type"

*Save annual data by drug
save "annual_drug.dta", replace


log close

/************************************
Print summary numbers
************************************/

use "annual_bydrug_bygeneric.dta", clear
keep if state == "XX"
sort drugtype genericind year
order drugtype genericind year
drop quarter futurerevision
export excel "${output}/Summary numbers_${yearquarter}.xlsx", firstrow(varlabels) sheet("Annual, generic status") sheetmodify

use "annual_drug.dta", clear
keep if state == "XX"
sort drugtype genericind year
keep drugtype genericind year state units imprx adjmedamt unadjmedamt
order drugtype genericind year state units imprx adjmedamt unadjmedamt
export excel "${output}/Summary numbers_${yearquarter}.xlsx", firstrow(varlabels) sheet("Annual, all") sheetmodify


use "quarterly_drug_generic.dta", clear
keep if state == "XX"
drop if year == $lastyr & quarter == $lastqtr
sort drugtype genericind year quarter
keep drugtype genericind year quarter state units imprx adjmedamt unadjmedamt
order drugtype genericind year quarter state units imprx adjmedamt unadjmedamt
export excel "${output}/Summary numbers_${yearquarter}.xlsx", firstrow(varlabels) sheet("Quarterly, generic status") sheetmodify


/*

/*** calculate percent that adjusted spending is less than unadjusted spending by drugtype in 2018 *****/
keep if state == "XX"

collapse (sum) units imprx adjmedamt unadjmedamt, by (state year drugtype)

format imprx adjmedamt unadjmedamt %14.0fc
gen percchange = 1 - (adjmedamt / unadjmedamt)

*All years 2010-2018
use annual_drug.dta, clear
keep if state == "XX"

collapse (sum) units imprx adjmedamt unadjmedamt, by (state drugtype)

format adjmedamt unadjmedamt %11.0f
gen percchange = 1 - (adjmedamt / unadjmedamt)





