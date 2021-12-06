/***************************************************************************
Project: Medicaid Spending on 3 Drugs, Quarterly Updates

Purpose: This program reads in all of the data that will be used in P3B in order to estimate the Medicaid rebate.

Author: Marni Epstein

Date: July 2019
Updated: March 2020

Input files: SDUD_imprx.dta
Output files: allSDUD_rebate.dta; fullrebatedata.dta
			 
***************************************************************************/


/***********************
SET GLOBALS - CHANGE
***********************/

*Enter user (computer name)
global user = "MEpstein"

*Enter last year and quarter that we have SDUD data 
global lastyr = 2019
global lastqtr = 3

*Enter today's date to create unique log
global today=031220

*Enter drive letter
*global drive = "C"
global drive = "D"

/****************************************************************
UPDATE DIRECTORIES - WILL UPDATE AUTOMATED BASED ON GLOBALS ABOVE
****************************************************************/

cd "${drive}:\Users\\${user}\Box\LJAF Medicaid SDU\2 Analysis\Quarterly Updates - Medicaid Spending on 3 Drugs\\${lastyr} Q${lastqtr}\Data"
global rebate "${drive}:\Users\\${user}\Box\LJAF Medicaid SDU\2 Analysis\Medicaid rebate adjustments incl inflation"
global medicaid "${drive}:\Users\\${user}\Box\LJAF Medicaid SDU\1 Data\Medicaid enrollment data"
global nadac "${drive}:\Users\\${user}\Box\LJAF Medicaid SDU\1 Data\NADAC"
global asp "${drive}:\Users\\${user}\Box\LJAF Medicaid SDU\1 Data\ASP"
global ful "${drive}:\Users\\${user}\Box\LJAF Medicaid SDU\1 Data\FUL Weighted AMP"
global output "${drive}:\Users\\${user}\Box\LJAF Medicaid SDU\2 Analysis\Medicaid rebate adjustments incl inflation"
global dispensefee "${drive}:\Users\\${user}\Box\LJAF Medicaid SDU\1 Data\Dispensing Fees"
global fss "${drive}:\Users\\${user}\Box\LJAF Medicaid SDU\1 Data\Federal Supply Schedules"
global ndcunits "${drive}:\Users\\${user}\Box\LJAF Medicaid SDU\1 Data\NDC numbers\Units per package"

/*********************************************************************
Create list of unique NDCs that we'll calculate rebates for, by NDC-9 
This is only for drugs that appear in the 2010 SDUD onwards
*********************************************************************/

*Use this dataset so that we capture only the NDCs that appear in SDUD
use "SDUD_imprx.dta", clear
keep if year >= 2010

*Generate a list of the brand and generic drugs for the rebate calculation. Note that none of the NDCs with missing generic status are in SDUD
tab Generic, m

*Create an indicator for if the drug only shows up in SDUD pre-NADAC (no entries after 2014)
bys ndc_s11: egen maxyr = max(year) 

*Get a unique list of NDCs for the pre- and post-2014 periods
duplicates drop ndc_s11, force

*Merge with NDC list to get route info
merge 1:1 ndc_s11 using "ndc_all.dta"

*There may be _m == 1, which are entries that are only in the SDUD dataset and not the NDC list.
*This is because we keep SDUD entries based on ndc-9, so there may be no corresponding ndc-11.
drop if _m == 2
drop _m

*For entries that have missing NDC info but have the same NDC-9 as an entry with that info, use that info
gen missingdose = DosageForm == ""
sort ndc_s9 missingdose
bys ndc_s9: gen test = DosageForm[1]
replace DosageForm = test if DosageForm == ""
drop test


*Export NDC list
/***
egen NDC_wdashes = concat(ndc_s1 ndc_s2 ndc_s3), punct("-")
export excel NDC_wdashes ProprietaryName DosageForm Route LabelerName NonproprietaryName SubstanceName using "NDC list for FSS.xlsx", firstrow(varlabels) replace
drop NDC_wdashes
****/


*Look at DosageForm to determine 5i status
tab DosageForm, m
tab Generic if inlist(DosageForm, "IMPLANT", "INJECTION", "INJECTION, SOLUTION", "Injection", "SOLUTION")

*Potential 5i drugs. Vivitrol is missing Dosage form for 2 NDCs so we add in the seond line to capture these
gen potential5i = inlist(DosageForm, "IMPLANT", "INJECTION", "INJECTION, SOLUTION", "Injection", "SOLUTION", "KIT", "Vial from kit")
replace potential5i = 1 if Generic == "Vivitrol"

keep ndc_s11 ndc_s9 Generic genericindicator StartMarketingDate drugtype maxyr potential5i DosageForm
sort ndc_s9 

*****
*Since we calculate rebate at the NDC-9 level, and we've filled in dosage form for all NDC-11, we now parse down to unique NDC-9s
*****
duplicates drop ndc_s9, force

*Merge with NADAC list to determine which drugs are 5i drugs
merge m:1 ndc_s9 using "nadac_unique_ndc.dta"

*Drop entries from the NADAC list only
drop if _m == 2

keep ndc_s11 ndc_s9 Generic genericindicator StartMarketingDate drugtype maxyr _m potential5i DosageForm

/***************************************************************
Create an indicator for 5i. This is for brand and generic drugs
***************************************************************/
*Non-5i drugs - from above
gen drug_5i = 0 if potential5i == 0

*Potential 5i drugs but have a NADAC, so likely NOT a 5i drug
replace drug_5i = 0 if _m == 3 &  potential5i == 1

*Drugs that don't match to a NADAC but only appear in SDUD pre-2014 (when NADAC data starts) are likely NOT 5i drugs
replace drug_5i = 2 if _m == 1 & maxyr < 2014 & potential5i == 1

*Probable 5i drugs - from above and also don't match to a NADAC
replace drug_5i = 1 if _m == 1 & potential5i == 1

*Make sure all Vivitrol is 5i
replace drug_5i = 1 if Generic == "Vivitrol"

*Evzio is not a 5i
replace drug_5i = 0 if Generic == "Evzio"

tab drug_5i genericind, m
tab Generic drug_5i, m



*Save unique values for NDCs we'll calculate the rebate for in a matrix. This means saving the numberic version of ndc_s9.
*Also save 5i drug status
destring ndc_s9, gen(ndc_n9)
format ndc_n9 %9.0f
sort genericindicator
mkmat ndc_n9 drug_5i genericindicator

mat def ndcmat = (ndc_n9, drug_5i, genericindicator)
global num = rowsof(ndcmat)


di "NDC list of unique NDCs in SDUD 2010 onwards"
matlist ndcmat, format(%11.0f)

list ndc_s9 Generic if drug_5i > 0

*Save list of which NDCs are 5i drugs
keep ndc_s9 drug_5i Generic 
save "NDC_5i.dta", replace


/******************************************************************
Distribute suppressed spending when national total spending is not suppressed
Do not subtract dispensing fees
******************************************************************/

*Look at how different the sum of states is from national total data
	use "SDUD_imprx.dta", clear
	keep if year >= 1993
	replace imprx = 0 if imprx < 0 

	preserve
	tempfile temp1 
	keep if state == "XX"
	keep state utilizationtype ndc_s11 year quarter totalamountreimbursed medicaidamountreimbursed units
	save "`temp1'"
	restore

	drop if state == "XX"
	
	*Count number of states and number of suppressed states
	gen statecount = 1
	gen total_supstate = totalamountreimbursed == .
	gen medicaid_supstate = medicaidamountreimbursed == .
	gen units_supstate = units == .
	
	*Collapse to get the sum of the states
	collapse (sum) statecount totalamountreimbursed total_supstate medicaidamountreimbursed medicaid_supstate units units_supstate, by(utilizationtype ndc_s11 year quarter)
	rename totalamountreimbursed sumstate_medicaid
	rename medicaidamountreimbursed sumstate_total
	rename units sumstate_units
	label variable total_supstate "Number of suppressed states for this NDC in this quarter for this FFS/MCO"

	merge 1:1 utilizationtype ndc_s11 year quarter  using "`temp1'"

	drop _m
	
	*Look at ratio of national totals / sum of states
	gen total_ratio = totalamountreimbursed / sumstate_medicaid
	gen medicaid_ratio =  medicaidamountreimbursed / sumstate_total
	gen units_ratio = units / sumstate_units
	summarize total_ratio medicaid_ratio units_ratio, detail

	*Suppressed amount to distribute = national total - sum of states
	gen suptotal_distribute = round(totalamountreimbursed - sumstate_medicaid, 0.1)
	gen supmedicaid_distribute =  round(medicaidamountreimbursed - sumstate_total, 0.1)
	gen supunits_distribute = round(units - sumstate_units, 0.1)
	
	*If sum of states is higher than national total, replace the amount to distribute with 0
	replace suptotal_distribute = 0 if suptotal_distribute < 0
	replace supmedicaid_distribute = 0 if supmedicaid_distribute < 0
	replace supunits_distribute = 0 if supunits_distribute < 0

	keep utilizationtype ndc_s11 year quarter total_supstate suptotal_distribute supmedicaid_distribute supunits_distribute
	save "nattotals_distribute.dta", replace
	
/*************************************************************************************************
Distribute this amount to states
************************************************************************************************/
use "SDUD_imprx.dta", clear
keep if year >= 1993
replace imprx = 0 if imprx < 0 

count if totalamountreimbursed == . & year >= 2010
count if medicaidamountreimbursed == . & year >= 2010
count if units == . & year >= 2010
count if suppressionused == "true" & year >= 2010

*Create a variable that's the percent of rx / all rx for suppressed states for that NDC in that quarter
bys utilizationtype ndc_s11 year quarter: egen totrx_sup = total(imprx) if suppressionused == "true" & state != "XX"
*br utilizationtype ndc_s11 year quarter state totalamountreimbursed imprx totrx_sup suppressionused if suppressionused == "true"

*Merge in national totals to distribute. m:1 because we want all entries for states to get the same nat total to distriube variable
merge m:1 utilizationtype ndc_s11 year quarter using "nattotals_distribute.dta"
drop _m

*br utilizationtype ndc_s11 year quarter state totalamountreimbursed imprx totrx_sup suptotal_distribute total_supstate suppressionused if suppressionused == "true"

*Check if number of suppressed states is the same as the variable from nattotals_distribute.dta
gen statecount = 1
bys utilizationtype ndc_s11 year quarter: egen numsupstates = total(statecount) if suppressionused == "true" & state != "XX"
*br utilizationtype ndc_s11 year quarter state numsupstates total_supstate totalamountreimbursed imprx totrx_sup suppressionused if numsupstates != total_supstate & suppressionused == "true" & state != "XX"

*Create variable that's the share of prescriptions out of total prescriptions in suppressed states
gen sup_imprx_share = imprx / totrx_sup if suppressionused == "true" & state != "XX"
*br utilizationtype ndc_s11 year quarter state totalamountreimbursed imprx totrx_sup sup_imprx_share suppressionused if suppressionused == "true"

*For states where total and Medicaid spending is missing, distribute the suppresed amount, calcualted above
replace totalamountreimbursed = suptotal_distribute * sup_imprx_share if suppressionused == "true" & state != "XX"
replace medicaidamountreimbursed = supmedicaid_distribute * sup_imprx_share if suppressionused == "true" & state != "XX"
replace units = supunits_distribute * sup_imprx_share if suppressionused == "true" & state != "XX"
replace suppressionused = "Distributed from nat total" if suppressionused == "true" & state != "XX" & (totalamountreimbursed != . | medicaidamountreimbursed != . | units != .)

*Count how many obs still have missing spending amounts
count if totalamountreimbursed == . & year >= 2010
count if medicaidamountreimbursed == . & year >= 2010
count if units == . & year >= 2010
tab year quarter if suppressionused == "true"

*Drop extra variables
drop total_supstate suptotal_distribute supmedicaid_distribute totrx_sup statecount numsupstates sup_imprx_share

*Look at units per rx by drug
gen unitsrx = units / imprx
bys ndc_s11: egen meduntsrx = median(unitsrx)
gen varunitsrx = unitsrx / meduntsrx 
count if varunitsrx > 2 | varunitsrx < 0.5
drop varunitsrx


/**************************************************
Add in Generic and drugtype variables when they're missing for an ndc_s9
**************************************************/
gsort + ndc_s9 - Generic
by ndc_s9: gen fill_Gen = Generic[1]
replace Generic = fill_Gen if Generic == ""

gsort + ndc_s9 - drugtype
by ndc_s9: gen fill_drugtype = drugtype[1]
replace drugtype = fill_drugtype if drugtype == ""

drop fill_Gen fill_drugtype

*Hard code drugtype for NDC where it's missing
*br if drugtype == ""
replace drugtype = "bup" if inlist(ndc_s11, "52427069811" , "52427071211")
replace Generic = "generic" if inlist(ndc_s11, "52427069811" , "52427071211")


*Export list of NDCs and units - RUN ONCE AND THEN COMMENT OUT
/*
preserve
duplicates drop ndc_s11, force
sort drugtype ndc_s11
drop ndc
egen ndc = concat(ndc_s1 ndc_s2 ndc_s3), punct("-")
keep ndc_s11 ndc Generic drugtype meduntsrx
order ndc_s11 ndc drugtype Generic meduntsrx
sort ndc_s11
export excel using "${ndcunits}/Units per RX SDUD Output_${lastyr}Q${lastqtr}.xlsx", replace firstrow(variables)
save "ndcunits_${lastyr}Q${lastqtr}.dta", replace
restore
*/



/*************************************************************
Merge in final data with units per package size created in P3A
*************************************************************/
drop ndc
merge m:1 ndc_s11 using "ndcunits.dta"
drop _m
sort ndc_s11 year quarter state 

gen proxyprice = totalamountreimbursed / units
gen expectedunits = imprx * Finalunitsperpackage
gen SDUDunits = units
gen SDUDunitsperrx = unitsrx
gen unitsource = "SDUD"

*Convert units to make sure they're per kit instead of ML for: Narcan, Evzio, Probuphine, Vivitrol

/*** *Narcan ***/
	tab ndc_s11 Finalunitsperpackage if Generic == "Narcan"

	*63481035810 - units / package = 1, but comes in a box of 10, 1ML spray. Assume that SDUD units are correct, as multiple units per rx would be multiple 1mL vials
	br ndc_s11 year quarter utiliz imprx units unitsrx expectedunits proxyprice if ndc_s11 == "63481035810" 

	*63481035910 - units / package = 1, but comes in a box of 10, 2ML spray. We expect 1 unit per rx, more if multiple vials. No way to tell if 1 rx for 2 units is actually 2 vials or is 2mL
	br ndc_s11 year quarter utiliz imprx units unitsrx expectedunits proxyprice if ndc_s11 == "63481035910" 
	*gen testunits = units / 10 if inlist(units, 10, 20, 60) & ndc_s11 == "63481035910"
	*gen testprice = totalamountreimbursed / testunits

	*63481036505 - 10ML box of 1. We divide units by 10 if units/rx is more than 10 in SDUD. 
	*Note that this assumes all rx in these cases are coded as 1 unit = 10mL (10), and will not capture cases where there are multiple rx and one is coded as unit = 1 and another is unit = 10.
	br ndc_s11 year quarter utiliz imprx units unitsrx expectedunits proxyprice if ndc_s11 == "63481036505" 
	replace unitsource = "units / ML" if unitsrx >= 10 & ndc_s11 == "63481036505" 
	replace units = units/10 if unitsrx >= 10 & ndc_s11 == "63481036505"
	replace unitsource = "expected units"  if units < 1 & ndc_s11 == "63481036505"
	replace units = 1 * imprx if units < 1 & ndc_s11 == "63481036505" 
	replace unitsrx = units / imprx
	replace proxyprice = totalamountreimbursed / units

	*63481036805 - 10ML box of 1. Divide units by 10 if SDUD units/rx is over 10, which we assume means 1 vial of 10mL was coded as 10 and not 1.
	br ndc_s11 year quarter utiliz imprx units unitsrx expectedunits proxyprice if ndc_s11 == "63481036805" 
	replace unitsource = "units / ML" if unitsrx >= 10 & ndc_s11 == "63481036805" 
	replace units = units/10 if unitsrx >= 10 & ndc_s11 == "63481036805" 
	replace unitsrx = units / imprx
	replace proxyprice = totalamountreimbursed / units

	*63481037710 - 2ML, box of 10. Most rx =1  are coded as units = 2. We assume all units/rx = 2 are coded as 2mL and not 2 vials.
	br ndc_s11 year quarter utiliz imprx units unitsrx expectedunits proxyprice if ndc_s11 == "63481037710" 
	replace unitsource = "units / ML" if unitsrx > 1 & ndc_s11 == "63481037710" 
	replace units = units / 2 if unitsrx > 1 & ndc_s11 == "63481037710" 
	replace units  = expectedunits if units < expectedunits & ndc_s11 == "63481037710" 
	replace unitsrx = units / imprx
	replace proxyprice = totalamountreimbursed / units

	*69547035302 - 2 vials, 0.1ML per vial. Seems to be coded as 0.2units per 1RX
	br ndc_s11 year quarter utiliz imprx units unitsrx expectedunits proxyprice if ndc_s11 == "69547035302" 
	replace unitsource = "expected units" if units < expectedunits & ndc_s11 == "69547035302"
	replace units = imprx * 2 if units < expectedunits & ndc_s11 == "69547035302"
	replace unitsrx = units / imprx
	replace proxyprice = totalamountreimbursed / units

/*** Evzio ***/
	tab ndc_s11 Finalunitsperpackage if Generic == "Evzio"

	*60842003001 - 2 auto-injectors
	br ndc_s11 year quarter utiliz imprx units unitsrx expectedunits proxyprice if ndc_s11 == "60842003001" 
	replace unitsource = "expected units" if units < expectedunits & ndc_s11 == "60842003001" 
	replace units = imprx * 2 if units < expectedunits & ndc_s11 == "60842003001" 
	replace unitsrx = units / imprx
	replace proxyprice = totalamountreimbursed / units

	*60842005101 - 2 auto-injectors
	br ndc_s11 year quarter utiliz imprx units unitsrx expectedunits proxyprice if ndc_s11 == "60842005101" 
	replace unitsource = "expected units" if units < expectedunits & ndc_s11 == "60842005101"
	replace units = imprx * 2 if units < expectedunits & ndc_s11 == "60842005101" 
	replace unitsrx = units / imprx
	replace proxyprice = totalamountreimbursed / units


/*** Probuphine ***/
*We don't expect anyone to get more than 1 Probuphine implant per prescription, so we use expected units
	tab ndc_s11 Finalunitsperpackage if Generic == "Probuphine", m

	*52440010014 - 4 pouch in 1 carton, but we count the 4 pouches as 1 implant
	*All suppressed in 2019 Q2
	br ndc_s11 year quarter state utiliz imprx units unitsrx expectedunits proxyprice if ndc_s11 == "52440010014" 

	*58284010014 - 4 pouch in 1 carton, but we count the 4 pouches as 1 implant
	*Since we don't expect anyone to get a prescription for 2 Probuphine implants at once, we use the expected units
	br ndc_s11 year quarter state utiliz imprx units unitsrx expectedunits proxyprice if ndc_s11 == "58284010014" 
	replace unitsource = "expected units" if ndc_s11 == "58284010014" 
	replace units = expectedunits if ndc_s11 == "58284010014" 
	replace unitsrx = units / imprx
	replace proxyprice = totalamountreimbursed / units


/*** Vivitrol ***/
*We don't expect anyone to get more than 1 Vivitrol injection per prescription, so we use expected units
	tab ndc_s11 Finalunitsperpackage if Generic == "Vivitrol"

	*63459030042 - 1 kit of 380 mg/4mL vial of VIVITROL
	br ndc_s11 year quarter state utiliz imprx units unitsrx expectedunits proxyprice if ndc_s11 == "63459030042" 
	replace unitsource = "expected units" if ndc_s11 == "63459030042" 
	replace units = expectedunits if ndc_s11 == "63459030042" 
	replace unitsrx = units / imprx
	replace proxyprice = totalamountreimbursed / units

	*65757030001 - 1 kit of 380 mg vial of VIVITROL
	br ndc_s11 year quarter state utiliz imprx units unitsrx expectedunits proxyprice if ndc_s11 == "65757030001" 
	replace unitsource = "expected units" if ndc_s11 == "65757030001" 
	replace units = expectedunits if ndc_s11 == "65757030001" 
	replace unitsrx = units / imprx
	replace proxyprice = totalamountreimbursed / units

	*65757030201 - I am pretty sure this NDC was entered incorrectly - there is 1 entry for 1 RX, units 380, and I can't find this NDC online
	br ndc_s11 year quarter state utiliz imprx units unitsrx expectedunits proxyprice if ndc_s11 == "65757030201" 
	replace ndc_s11 = "65757030202" if ndc_s11 == "65757030201" 

	*65757030202 - 380mg/4 mL vial 
	br ndc_s11 year quarter state utiliz imprx units unitsrx expectedunits proxyprice if ndc_s11 == "65757030202" 
	replace unitsource = "expected units" if ndc_s11 == "65757030202" 	
	replace units = expectedunits if ndc_s11 == "65757030202" 
	replace unitsrx = units / imprx
	replace proxyprice = totalamountreimbursed / units

/******************
For the rest of NDCs that are not ML and don't have a package size of 1, we use the expected units if SDUD units is lower than expected units.
Note that the Finalunitsperpackage and expectedunits variables will be missing for ML drugs
******************/
replace unitsource = "expected units" if units < expectedunits & Finalunitsperpackage != 1 & Finalunitsperpackage != .
replace units = expectedunits if units < expectedunits & Finalunitsperpackage != 1 & Finalunitsperpackage != .

replace unitsource = "ML SDUD" if BillingUnit == "ML"

tab unitsource if units != . & units != 0 & state != "XX" & year >= 2010 & year < 2019


*For the rest, which are drugs measured in ML and drugs with a package size of 1, we use units from SDUD

*Export to check
/*
sort ndc_s11 Generic utiliz ndc_s11 year quarter state
export excel ndc_s11 Generic utiliz year quarter state imprx SDUDunits SDUDunitsperrx units unitsrx proxyprice ///
	if inlist(Generic, "Narcan", "Evzio", "Probuphine", "Vivitrol") & state != "XX"  ///
	using "${qtroutput}/Check units and price for kits.xlsx", firstrow(variables) sheetmodify
*/
	
*Save state data with distributed data and adjusted units
save "SDUD_imprx_distr.dta", replace


/****************************************************
Compress down to NDC-9 and combine FFS and MCO
****************************************************/
use "SDUD_imprx_distr.dta", clear

*Drop national totals, since we'll sum up states
drop if state == "XX"

count if imprx != . & imprx != 0

*We don't include obs with under 5 prescriptions
drop if imprx <= 5

*Count non-suppressed quarters by generic status by STATE quarters
tab suppressionused genericindicator if year >= 2010 & year != 2019

*Don't include obs when spending = 0 but units/rx > 0 (managed care bundled payments)
count if totalamountreimbursed == 0 & units > 0
count if totalamountreimbursed == 0 & imprx > 0
*Denominator
count if imprx != . & imprx != 0

*Also don't include managed care obs when the value is 100% lower than the value before and after - also likely bundled payemnts
sort utilizationtype ndc_s11 state year quarter
bys utilizationtype ndc_s11 state: gen pricepercbefore = (proxyprice / proxyprice[_n-1])
bys utilizationtype ndc_s11 state: gen pricepercafter = (proxyprice / proxyprice[_n+1]) 
count if pricepercbefore <= .5 & pricepercafter <= .5 & utilizationtype == "MCOU"
gen bundledirregularity = 1 if pricepercbefore <= .5 & pricepercafter <= .5 & utilizationtype == "MCOU"

*Just for rebate amt calculation, don't sum up the units if spending is 0 or it's lower than the quarters before and after
*This would under-estimate the AMP estimate (by adding in units but not the corresponding spending)
*And is likely because of bundled payments
replace units = 0 if totalamountreimbursed == 0 & units > 0
replace units = 0 if totalamountreimbursed == 0 & imprx > 0

replace units = 0 if bundledirregularity == 1
replace totalamountreimbursed = 0 if bundledirregularity == 1

*Collapse to the national total level (sum of states) and combine FFS/MCO, and collapse to NDC-9
collapse (sum) totalamountreimbursed medicaidamountreimbursed units imprx genericindicator (first) Generic drugtype Finalunitsperpackage BillingUnit, by(ndc_s9 year quarter)
gen state = "sum of states"
replace genericindicator = 1 if genericindicator >= 1
label values genericindicator genericlab
tab genericindicator, m

label variable totalamountreimbursed "Total amount reimbursed (sum of states)"
label variable medicaidamountreimbursed "Medicaid amount reimbursed (sum of states)"
label variable units "Total units, based off package size and SDUD"

count if missing(totalamountreimbursed)
tab genericindicator, m


*Generate estimated AMP (Price per unit) variable. Use TOTAL price, not just Medicaid price. 
*We will modify the AMP value based on a few other data sources, so also create a variable preserve original SDUD AMP value
gen AMP = totalamountreimbursed / units
replace AMP = 0 if totalamountreimbursed == 0 /* instead of missing */
label variable AMP "Average manufacturer price (AMP) used in rebate calculation"

*Create variable to preserve original SDUD AMP value
gen AMP_SDUD = AMP
label variable AMP_SDUD "Average manufacturer price (AMP) from SDUD"

*Variable to note source of AMP
gen AMPsource = "SDUD"


/************************************************************************************************************
Merge in 5i drugs
************************************************************************************************************/

*Merge with list of which drugs are 5i drugs
merge m:1 ndc_s9 using "NDC_5i.dta"

*Check that all _m == 1 are SDUD entries from pre-2010
*_m == 2 are entries that are in the 5i file only (have an XX entry but no sum of states)
tab year  if _m == 1
tab ndc_s9 if _m == 1 & year > 2010

drop if _m == 2
drop _m

*Check how many quarters are potential 5i
tab drug_5i genericindicator if year >= 2010 & year != 2019, m


/*************************************************************************************************
Merge in ASP file. We will want ASP to calculate AMP for 5i drugs. 
We use m:1 because there are multiple state entries per NDC/year/quarter
_m == 1 are SDUD entries without corresponding ASP obs
_m == 2 are ASP obs without SDUD entries - we don't want to keep these
************************************************************************************************/
merge m:1 ndc_s9 year quarter using "ASP.dta"
drop if _m == 2
drop _m

*Check how many 5i NDCs have ASP obs
count if inlist(drug_5i, 1, 2) & ndc9_redASP != .
count if inlist(drug_5i, 1, 2) & ndc9_redASP == .

tab ndc_s9 if inlist(drug_5i, 1, 2) & ndc9_redASP != .
*br if inlist(drug_5i, 1, 2) & ASP != .

*Sort by year/quarter 
sort ndc_s9 year quarter 

/******************************************************************************
Convert ASP units to SDUD units, for the 9 NDC-9s with matching ASP data.
ASP data is usually listed per MG, while SDUD is per ML (unless we know otherwise, such as the injections below)

Note: in 2019 Q2, the data was edited and there are no obs for NDC 174780042, which previously had ASP data
If there is a new NDC that is not listed below, check ASP to SDUD units and add in as necessary
******************************************************************************/
tab ndc_s9 ASPdosage if inlist(drug_5i, 1, 2) & ndc9_redASP != .

*(1) 006416132 - geneneric naloxone injection. ASP = 1mg, SDUD = 0.4mg/mL
replace ndc9_redASP = ndc9_redASP * 0.4 if ndc_s9 == "006416132"
*br ndc_s9 ASPdosage ndc9_redASP AMP if ndc_s9 == "006416132"

*(2) 124960100 - Sublocade. ASP = 3 greater than 100mg, 1 less than 100mg. SDUD = 100 mg/0.5 mL.
*   			 SDUD seems to be showing the price per injection, so we use the same measure for ASP
replace ndc9_redASP = ndc9_redASP / 0.5 if ndc_s9 == "124960100"
*br ndc_s9 ASPdosage ndc9_redASP AMP medicaidamountreimbursed units if ndc_s9 == "124960100"

*(3) 124960300 - Sublocade. ASP = 2 greater than 100mg, 3 less than 100mg. SDUD = 300mg/1.5mL
*   			 SDUD seems to be showing the price per injection, so we use the same measure for ASP
replace ndc9_redASP = ndc9_redASP / 1.5 if ndc_s9 == "124960300"
br ndc_s9 year quarter ASPdosage ndc9_redASP AMP medicaidamountreimbursed units if ndc_s9 == "124960300"

*(4) 174780041 - geneneric naloxone injection. ASP = 1mg. SDUD = .4 mg/mL
replace ndc9_redASP = ndc9_redASP * 0.4 if ndc_s9 == "174780041"
*br ndc_s9 ASPdosage ndc9_redASP ndc9_redASP_adj AMP if ndc_s9 == "174780041"

*(5) 174780042 - geneneric naloxone injection. ASP = 1mg. SDUD = .4 mg/mL
replace ndc9_redASP = ndc9_redASP * 0.4 if ndc_s9 == "174780042"
*br ndc_s9 ASPdosage ndc9_redASP ndc9_redASP_adj AMP if ndc_s9 == "174780042"

*(6) 582840100 - Probuphine. ASP = 74.2mg. SDUD = 80 mg/1.
*Note: These are likely the same dose. About Probuphine: "74.2 mg (buprenorphine) per implant (equivalent to 80 mg buprenorphine HCl)"
*br ndc_s9 ASPdosage ndc9_redASP AMP if ndc_s9 == "582840100"

*(7) 634590300 - Vivitrol. ASP = 1mg. SDUD = 1 kit of 380 mg vial of VIVITROL
replace ndc9_redASP = ndc9_redASP * 380 if ndc_s9 == "634590300"
*br ndc_s9 ASPdosage ndc9_redASP AMP if ndc_s9 == "634590300"

*(8) 657570300 - Vivitrol. ASP = 1mg. SDUD = 1 kit of 380 mg vial of VIVITROL
replace ndc9_redASP = ndc9_redASP * 380 if ndc_s9 == "657570300"
*br ndc_s9 ASPdosage ndc9_redASP AMP if ndc_s9 == "657570300"

*(9) 674570599 - geneneric naloxone injection. ASP = 1mg. SDUD =  0.4 MG/ML
replace ndc9_redASP = ndc9_redASP * 0.4 if ndc_s9 == "674570599"
*br ndc_s9 ASPdosage ndc9_redASP AMP if ndc_s9 == "674570599"


*Look at which quarters of the 5i NDCs with ASP data have missing ASP data
*br ndc_s9 year quarter units imprx AMP ndc9_redASP if ndc_s9 == "634590300"
*174780041 is missing ASP for the first quarter, 2017 Q3
*634590300 is missing ASP data for 2011 Q4 and on.

*For NDC-9 63459-0300, we calcualte the average SDUD AMP to ASP ratio for the 4 last quarters of ASP - 2010 Q4 - 2011 Q3
*And apply that ratio to SDUD AMP for later quarters, since ASP data is missing
egen yearqtr = concat(year quarter)
gen ASP_SDUDAMP = ndc9_redASP / AMP
egen avgASPratio = mean(ASP_SDUDAMP) if ndc_s9 == "634590300" & (yearqtr >= "20104" & yearqtr <= "20113")
egen ASPratio = mean(avgASPratio) if ndc_s9 == "634590300"
replace ndc9_redASP = AMP * ASPratio if ndc_s9 == "634590300" & ndc9_redASP == . 
drop yearqtr  ASP_SDUDAMP avgASPratio ASPratio
*br ndc_s9 year quarter units imprx AMP ndc9_redASP if ndc_s9 == "634590300"


/**********************************************************************
Check substutition criteria for 5i drugs with matching ASP entries
Criteria: if ASP (reducing the reported ASP + 6% to ASP) exceeds the AMP for a drug by 5 percent in the 2 previous quarters or 3 of the previous 4 quarters
Sean recommends that we don't calculate this on our own, we just check the notes section of the ASP file
**********************************************************************/

gen ASP_AMP_ratio = ndc9_redASP / AMP
label variable ASP_AMP_ratio "ASP to AMP ratio. If 5i drug and ratio over 1.05, use ASP to estimate AMP"

list ndc_s9 year quarter ndc9_redASP AMP ASP_AMP_ratio if inlist(drug_5i, 1, 2) & ndc9_redASP != .
tab ndc_s9 if inlist(drug_5i, 1, 2) & ASP_AMP_ratio != .

*Check which NDCs/quarters meet the substitution criteria
count if ASP_AMP_ratio > 1.05 & inlist(drug_5i, 1, 2) & ASP_AMP_ratio != .
list ndc_s9 state year quarter ndc9_redASP AMP ASP_AMP_ratio notes_AMPsub if ASP_AMP_ratio > 1.05 & inlist(drug_5i, 1, 2) & ASP_AMP_ratio != .
tab ndc_s9 year if ASP_AMP_ratio > 1.05 & inlist(drug_5i, 1, 2) & ASP_AMP_ratio != .

*Chech how many quartesr have an ASP value that is more than 5% smaller than SDUD AMP
count if ASP_AMP_ratio < 0.95 & inlist(drug_5i, 1, 2) & ASP_AMP_ratio != .

*Also check if the notes section indicates that AMP was substituted for ASP
tab Notes if inlist(drug_5i, 1, 2) & ndc9_redASP != .
tab notes_AMPsub if inlist(drug_5i, 1, 2) & ndc9_redASP != .

*Always use ASP data to estimate AMP if it's available, even if the notes section don't indicate substitution
replace AMP = ndc9_redASP if !missing(ndc9_redASP) & inlist(drug_5i, 1, 2)

*Variable to note source of AMP
replace AMPsource = "ASP" if !missing(ndc9_redASP) & inlist(drug_5i, 1, 2)
label variable AMPsource "AMP source"

/***************************************************************
Merge in estimated Best Price from Federal Supply Schedules
***************************************************************/
merge 1:1 ndc_s9 year quarter using "fss.dta"

*_m == 1 are SDUD entries that don't have FSS data
*_m == 2 are FSS entries that don't appear in the SDUD
drop if _m == 2
drop _m
tab genericindicator if  FSS_ndc9 != .

*Note: We divided FSS prices by package size to get price per unit when we read in data in P3A


/***************************************************************
Merge CPI_U values and save baseline CPI and AMP values
***************************************************************/

merge m:1 year quarter using "CPI_U.dta"

*Make sure all the unmatched entries are from years in CPI_U that don't have SDUD data
tab year quarter if _m == 1
tab year if _m == 2

drop if _m == 2
drop _m

*Save dataset with brand name AMP and CPI values. We keep the earlier years to calculate baseline CPI and AMP for now.
save "brand_amp.dta", replace


/*************************************
Calculate generic AMP. 
We use the lower of (1) weighted AMP published by CMS in the FUL files or (2) NADAC 
*************************************/
use "weightedamp_ful.dta", clear

*Merge with dataset to calculate rebate for generics. Use 1:m because there can be multiple NDC/year/quarter in using bc of FFS/MCO
merge 1:1 ndc_s9 year quarter using "brand_amp.dta"

*m == 1  are entries from weighted AMP FUL file that are not in SDUD - drop
*m == 2 are SDUD entries without weighted AMP entries - keep. All brand drugs should be _m == 2
tab genericind _m, m
drop if _m == 1
drop _m

*Merge in NADAC data
merge 1:1 ndc_s9 year quarter using "nadac_ndc.dta"

*_m == 1 are SDUD entries that don't have NADACs
*_m == 2 are NADAC entries that don't appear in SDUD - drop
drop if _m == 2
drop _m

*Create variable that's the lower of weighted AMP or NADAC
egen genamp = rowmin(avg_NADAC_unit avg_weightedAMP)
gen genampsource = "NADAC" if avg_NADAC_unit < avg_weightedAMP
replace genampsource = "WAMP FUL" if  avg_weightedAMP <= avg_NADAC_unit & genamp != .

*year-quarter variable
egen yearquarter = concat(year quarter)
destring yearquarter, replace

*Indicator for obs with non-missing generic AMP (WAMP or NADAC) AND non-missing SDUD AMP
gen missingAMP = missing(genamp) | missing(AMP)

*Quarters post-2014Q3 that don't have WAMP or NADAC data
count if missingAMP == 1 & genericindicator == 1 & AMP != .
sort missingAMP ndc_s9 year quarter


/*************************************
We create a FUL to NADAC ratio and use it to adjust NADAC downwards
*************************************/
gen ful_nadac_ratio = avg_weightedAMP / avg_NADAC_unit if avg_weightedAMP != . & avg_NADAC_unit != .
gen bothsources = avg_weightedAMP != . & avg_NADAC_unit != .

*Create counter for when we have both NADAC and FUL data. This is only for bothsources == 1
sort bothsources genericindicator ndc_s9 year quarter
bys bothsources genericindicator ndc_s9: gen bothcount = _n

*Average ratio of FUL to NADAC ratio of the earliest 4 quarters
by bothsources genericindicator ndc_s9: egen avg_ful_nadac = mean(ful_nadac_ratio) if bothcount <= 4 & bothsources == 1 & genericindicator == 1 
summarize avg_ful_nadac, det

*Assign this ratio to all quarters for the NDC
bys ndc_s9: egen avg_ful_nadac2 = mean(avg_ful_nadac)

*Sort and apply the ratio to quarters where we only have FUL data
replace genampsource = "Adjusted NADAC" if genampsource == "NADAC"
replace genamp = genamp * avg_ful_nadac2 if genampsource == "Adjusted NADAC" & genamp != . & avg_ful_nadac2 != .


/*************************************
Look at generic AMP (FUL or NADAC-adjusted to FUL) to SDUD AMP ratio
*************************************/
gen genamp_SDUDamp = genamp / AMP
summarize genamp_SDUDamp if genericindicator == 1, detail


/*************************************
For drugs that appear in the FUL data, we compute a SDUD to FUL/NADAC ratio using 
the average ratio for the earliest 4 quarters that the drug appears in the FUL/NADAC files. 
We apply this ratio to SDUD AMP for pre-2016 years. 
*************************************/

*Create variable for 4 eariest quarters that the NDC appears in FUL/NADAC files and SDUD AMP is not missing
*Use by and not bysort so that we keep the sort from the line above, which includes year and quarter
sort missingAMP genericindicator ndc_s9 year quarter
by missingAMP genericindicator ndc_s9: gen fulqtrs = _n if missingAMP == 0 & genericindicator == 1
*br missingAMP ndc_s9 year quarter AMP genamp fulqtrs genericrebate if genericindicator == 1

*Calculate the average Weighted AMP Ful - NADAC / SDUD AMP ratio for the 4 EARLEIST non-missing quarters that the generic drug appears in FUL
by missingAMP genericindicator ndc_s9: egen avg_genamp_SDUDamp = mean(genamp_SDUDamp) if fulqtrs <= 4 & missingAMP == 0 & genericindicator == 1  
*br missingAMP genericrebate ndc_s9 year quarter genampsource genamp AMP ge namp_SDUDamp fulqtrs avg_genamp_SDUDamp
*Sourceholder is the source (NADAC/WAMP that we use for the ratio).
sort ndc_s9 fulqtrs
bys ndc_s9: gen sourceholder = genampsource[1] if genericindicator == 1 

*Calculate the average Weighted AMP Ful - NADAC / SDUD AMP ratio for the 4 LATEST non-missing quarters that the generic drug appears in FUL
sort missingAMP genericindicator ndc_s9 year quarter
by missingAMP genericindicator ndc_s9: egen numfulqtrs = count(genericindicator) if missingAMP == 0 & genericindicator == 1  
by missingAMP genericindicator ndc_s9: egen avg_genamp_SDUDamp_latest = mean(genamp_SDUDamp) if fulqtrs >= (numfulqtrs - 3) & missingAMP == 0 & genericindicator == 1 
*br missingAMP genericindicator ndc_s9 year quarter genampsource genamp AMP genamp_SDUDamp fulqtrs avg_genamp_SDUDamp avg_genamp_SDUDamp_latest if genericindicator == 1 
*Sourceholder is the source (NADAC/WAMP that we use for the later ratio).
gsort ndc_s9 - fulqtrs
bys ndc_s9: gen sourceholder_latest = genampsource[1] if genericindicator == 1 

*Check summary of the average ratios. Only look at summary stats for fulqtrs == 1 because 
*if some NDCs have less than 4 fulqtrs the weighting will be off
summarize avg_genamp_SDUDamp avg_genamp_SDUDamp_latest if missingAMP == 0 & avg_genamp_SDUDamp != . & fulqtrs == 1, detail

*Assign the average FUL weighted AMP/SDUD AMP ratio to all quarters for the NDC/utilization type
bys ndc_s9: egen avg_genamp_SDUDamp2 = mean(avg_genamp_SDUDamp)
label variable avg_genamp_SDUDamp "Average FUL weighted AMP - NADAC / SDUD AMP ratio for first 4 quarters of FUL/NADAC data"

bys ndc_s9: egen avg_genamp_SDUDamp2_latest = mean(avg_genamp_SDUDamp_latest)
label variable avg_genamp_SDUDamp "Average FUL weighted AMP - NADAC / SDUD AMP ratio for last 4 quarters of FUL/NADAC data"

sort ndc_s9 year quarter
*br utilizationtype ndc_s11 year quarter weightedaverageamps AMP FULamp_SDUDamp fulqtrs avg_FULamp_SDUDamp avg_FULamp_SDUDamp2

/*************************************
If there is a non-missing weighted AMP FUL - NADAC value, use this for AMP
For earlier quarters, apply the average ratio from th 4 earliest quarters to AMP
*************************************/
*Create variable that is first and last quarter that we have NADAC/WAMP FUL data
sort ndc_s9 fulqtr
bys ndc_s9: gen firstgenampqtr = yearquarter[1]
gsort + ndc_s9 - fulqtr
bys ndc_s9: gen lastgenampqtr = yearquarter[1]


*Use weighted AMP from FUL -NADAC instead of SDUD AMP when applicable
replace AMP = genamp if missingAMP == 0 & genericindicator == 1 & drug_5i == 0
replace AMPsource = genampsource if missingAMP == 0 & genericindicator == 1 & drug_5i == 0

*Use the average FUL weighted AMP - NADAC / SDUD AMP ratio * AMP for non-missing AMP quarters BEFORE NADAC/FUL data was available. Only do this for 2014Q3 and on.
*Only use the ratio if it's pre-2016Q2 (fulqtrs is missing) and we have a ratio for this NDC/utilization type
replace AMP = AMP * avg_genamp_SDUDamp2 if !missing(AMP) & !missing(avg_genamp_SDUDamp2) & yearquarter < firstgenampqtr & genericindicator == 1 & drug_5i == 0
gen temp = " ratio, early qtrs"
replace AMPsource = sourceholder + temp if !missing(AMP) & !missing(avg_genamp_SDUDamp2) &  yearquarter < firstgenampqtr & genericindicator == 1 & drug_5i == 0
drop temp

*Use the average FUL weighted AMP - NADAC / SDUD AMP ratio * AMP for non-missing AMP quarters AFER NADAC/FUL data was available. Only do this for 2014Q3 and on.
replace AMP = AMP * avg_genamp_SDUDamp2_latest if !missing(AMP) & !missing(avg_genamp_SDUDamp2) & yearquarter > lastgenampqtr & genericindicator == 1 & drug_5i == 0
gen temp = " ratio, latest qtrs"
replace AMPsource = sourceholder + temp if !missing(AMP) & !missing(avg_genamp_SDUDamp2) &  yearquarter > lastgenampqtr & genericindicator == 1 & drug_5i == 0
drop temp

*Check the AMP source breakdown
tab AMPsource genericind, m

*If you want to check what years are affected by this adjustment, run the following code
/*
gen adjAMP = AMP * avg_FULamp_SDUDamp2 if !missing(AMP) & !missing(avg_FULamp_SDUDamp2) & missing(fulqtrs)
tab year quarter if adjAMP != .
drop adjAMP
*/

drop missingAMP

save "all_amp.dta", replace
tab AMPsource genericindicator if year >= 2010 & year != 2019

/*****************************************************
Save baseline AMP and CPI in a matrix for each NDC
Use the first non-missing quarter the NDC is in SDUD for brand drugs
and the first quarter after 2014Q3 for generics
Save results in a matrix
*****************************************************/
use "all_amp.dta", clear

* $num is the number of brand name NDCs, saved in matrix ndcmat above
di "Number of unique name NDCs: $num"

*Add a variable in that counts quarters starting at our first quarter, 1993 Q1. Remains constant based on quarter, not whether there is data
gen qtrcounter = .
local count = 1
forvalues year == 1993/2018{
	forvalues quarter = 1/4 {
		replace qtrcounter = `count' if year == `year' & quarter == `quarter'
		local ++count
	}
}

*Variable that counts the quarters we have data for, starting at the first time the drug appears
bys ndc_s9: egen firstqtrs = rank(qtrcounter)

*Create matrix to save results with 5 columns: NDC, year of first non-missing occurance in SDUD, quarter of first non-missing occurance in SDUD, baseline AMP from this first quarter, and CPI_U of that first quarter
mat baseline = J($num,5,.)

forvalues n = 1/$num {

		di ""
		di "Number = `n'"
		preserve

		gl ndc_n = ndcmat[`n',1]
			
		*Count characters and add leading zeros if they got dropped, since the NDC is stored as numeric in the matric
		gl count = strlen("$ndc_n")
		
			if $count == 9 {
				gl ndc_s = "${ndc_n}"
			}
			else if $count == 8 {
				gl ndc_s = "0${ndc_n}"
			}
			else if $count == 7 {
				gl ndc_s = "00${ndc_n}"
			}
			else if $count == 6 {
				gl ndc_s = "000${ndc_n}"
			}
			else if $count == 5 {
				gl ndc_s = "0000${ndc_n}"
			} 
			
		di "NDC = $ndc_s "
		
		keep if ndc_s9 == "$ndc_s"
		
		*Make sure there is at least one obs. If not, skip down.
		*Note: program should probably be restructed to create the NDC list later to avoid this problem, but this is an easy band-aid
		gl obs = _N
		if $obs > 0 {

			*Save whether this is a generic or brand drug
			mean genericindicator , coeflegend
			gl gen = _b[genericindicator]
			
			*keep the first non-missing, non-zero observation (first time this NDC appears in SDUD)
			sort year quarter
			keep if AMP != . & AMP != 0
			
			
			*If generic, use the first quarter after 2014Q3. Only keep when there are over 10 rx, unless there are no quarters with over 10 rx
			if $gen == 1 {
				keep if yearquarter >= 20143
				
				*Only do this if there is at least 1 obs, or else we get an error
				gl obs = _N
				if $obs > 0 {
					*We only want to use obs where prescriptions are over 10 for the baseline, unless all are under 10
					gen over10 = imprx > 10
					egen numover10 = total(over10)
					*If there is at least one obs with over 10 rx, use it. Otherwise, just use the first three quarters 
					if numover10 > 1 {
						keep if imprx > 10
					}
				}
			
				*Only do this if there is at least 1 obs, or else we get an error
				gl obs = _N
				if $obs > 0 {
					keep if _n == 1
					gen baselineamp = AMP
				}
				
			}
			*If brand , average AMP across the three earliest quarters. Only use three quartres starting at baseline,
			* meaning if there is a skipped quarter because rx < 11, we don't use the three earliest, we only use data if we have it for the three first quarters
			else if $gen == 0 {
				
				*We only want to use obs where prescriptions are over 10 for the baseline, unless all are under 10
				gen over10 = imprx > 10
				egen numover10 = total(over10)
				*If there is at least one obs with over 10 rx, use it. Otherwise, just use the first three quarters 
				if numover10 > 1 {
					keep if imprx > 10
				}
			
				*Save firstqtrs value from first non-missing, non-zero, rx > 10 obs
				gl first = qtrcounter[1]
				
				*Keep first three quarters after baseline
				keep if qtrcounter <= $first + 2
				
				*Only do this if we have more than 1 observation, or else we get an error
				gl obs = _N
				if $obs > 0 {
					*Average AMP across these quarters
					egen baselineamp = mean(AMP)
				}
				
				*And only keep first quarter
				keep if _n == 1
			}
		}
		
		*If there are no non-missing, non-zero observations with imprx > 10, fill globals in with missing
		gl obs = _N
		di "Number of observations: $obs"
		
		if $obs == 0 {
			gl year = .
			gl quarter = .
			gl amp = .
			gl cpi = .
			
			di "No non-suppressed observations for NDC $ndc_s for `type'"
		}
		else if $obs == 1 {
			gl year = year
			gl quarter = quarter
			gl amp = baselineamp
			gl cpi = CPI
			
			di "First occurance: Year = $year Quarter = $quarter "
		}
		
		
		matrix baseline[`n',1] = $ndc_n
		matrix baseline[`n',2] = $year
		matrix baseline[`n',3] = $quarter
		matrix baseline[`n',4] = $amp
		matrix baseline[`n',5] = $cpi

		restore
}


*Look at matrix, formatted to show NDCs without scientific notation and no decimals
mat list baseline, format(%11.0f)

clear
*Turn matrix into dataset so that we can merge it onto the main dataset
	svmat double baseline
	format baseline1 %011.0f
	gen ndc_s9  = string(baseline1,"%09.0f")
	drop baseline1
	rename baseline2 baselineyear
	rename baseline3 baselinequarter
	rename baseline4 baselineAMP
	rename baseline5 baselineCPI


order ndc_s9
sort ndc_s9  

save "baseline_AMP_CPI.dta", replace

use "baseline_AMP_CPI.dta", clear

*Merge with main dataset. We use the same baseline AMP baseline CPI for each NDC/utilization type
merge 1:m ndc_s9 using "all_amp.dta"

* _m == 1 are NDCs with no other info
* _m == 2 are SDUD entries pre-2010. We only calculate baseline AMP for NDCs 2010 and later, so if a drug is only pre-2010 it will be here
* _m == 3 are drugs that we will calculate a rebate for
tab baselineyear if _m == 1, m
tab year if _m == 2
drop if _m == 1 | _m == 2
drop _m


/****************************************************************************************************
Calculate rebate for brand name drugs
We calculate the rebate for national totals only, and apply it to states amounts base on NDC/quarter
*****************************************************************************************************/

*We only calculate the rebate for 2010 and onwards.
drop if year < 2010 | (year == $lastyr & quarter == $lastqtr)
tab year quarter

* JUST FOR METHODS PAPER, LOOK AT JUST 2018. DELETE/STAR OUT FOR QUARTERLY ANALYSIS
*drop if year == 2019
tab AMPsource genericind, m

/*************************************
Step 1: Basic Rebate Calculation
The basic rebate amount for Single Source or Innovation (S/I) drugs is the greater of quarterly AMP minus BP 
or AMP times 23.1% (Rounded to 7 Places).
*************************************/
gen basic_rebate_23 = round(AMP * .231, 0.0000001) if genericindicator == 0
gen basic_rebate_BP = round(AMP - FSS_ndc9, 0.0000001) if genericindicator == 0
replace basic_rebate_BP = 0 if basic_rebate_BP == . & genericindicator == 0

*Can switch this to check without BP provision
egen basicrebate = rowmax(basic_rebate_23 basic_rebate_BP) if genericindicator == 0
*gen basicrebate = basic_rebate_23

label variable basicrebate "Basic rebate - higher of 23.1%  or AMP - FSS for brand drugs, 13% for generics"

*Look at the breakdown by 23.1% of AMP vs AMP - BP
gen basicrebatesource = "23.1% AMP" if basic_rebate_23 >= basic_rebate_BP & genericindicator == 0
replace basicrebatesource = "AMP - BP (FSS)" if basic_rebate_BP > basic_rebate_23 & genericindicator == 0
tab basicrebatesource genericindicator, m

tab ndc_s9 Generic if basicrebatesource == "AMP - BP (FSS)"


/*************************************
Step 2: Additional Rebate Calculation
Additional rebate = (Baseline AMP / Baseline CPI-U) x Quarterly CPI-U (Rounded to 7 Places)
Compare the additional rebate amount to the quarterly AMP: 
	if the number is less than the quarterly AMP, subtract it from the quarterly AMP to determine the additional rebate amount; 
	if the number is equal to or greater than the quarter’s AMP, the additional rebate amount is equal to zero.

*The additional rebate amount is basically the baseline AMP * growth factor, or allowable growth.
	If it is equal or greater than AMP, it means AMP has not exceeded allowable growth, and the additional rebate is 0.
	If it is less than AMP, meaning AMP has exceeded allowable growth, the additional rebate is the amount that AMP
		has exceeded the allowable growth, aka AMP - allowable growth.
*************************************/
gen addrebate_amt = round((baselineAMP / baselineCPI) * CPI, 0.0000001) if genericindicator == 0
label variable addrebate_amt "Allowable AMP growth = baseline AMP * (quarterly CPI / baseline CPI)"

gen addrebate_final = .
replace addrebate_final = AMP - addrebate_amt if addrebate_amt < AMP & !missing(addrebate_amt) & !missing(AMP) & genericindicator == 0
replace addrebate_final = 0 if addrebate_amt >= AMP & !missing(addrebate_amt) & !missing(AMP) & genericindicator == 0
replace addrebate_final = 0 if addrebate_final == . & genericindicator == 0
label variable addrebate_final "Additional rebate = AMP - allowable AMP growth if AMP > allowable growth, else 0"

*Checks
*Final additional rebate = AMP - additional rebate amount if additional rebate is less than AMP
*br ndc_s11 baselineAMP addrebate_amt AMP addrebate_final if addrebate_amt < AMP & !missing(addrebate_amt) & !missing(AMP) & genericindicator == 0
*Final additional rebate  = 0 if additional rebate is greater than or equal to AMP
*br ndc_s11 baselineAMP addrebate_amt AMP addrebate_final if addrebate_amt >= AMP & !missing(addrebate_amt) & !missing(AMP) & genericindicator == 0

*Drugs where the AMP exceeds allowable growth (additional rebate > 0)
tab ndc_s9 Generic if addrebate_final > 0 & genericindicator == 0

/*************************************
Step 3: Total Rebate Calculation
Total Rebate = Basic Rebate + Additional Rebate 
This amount is rounded to 6 places 
This amount is rounded to 4 places 
*************************************/
gen totalrebate_temp1 = basicrebate + addrebate_final if genericindicator == 0
gen totalrebate_temp2 = round(totalrebate_temp1, 0.000001)
gen totalrebate = round(totalrebate_temp2, 0.0001)
label variable totalrebate "Total rebate amount = basic rebate + additional rebate"

/*************************************
Step 4: Comparison of Total Rebate Amount to Quarterly AMP
If the total rebate amount is greater than the quarterly AMP, it is reduced to equal AMP,
	and if not, the total rebate amount does not change.
*************************************/
gen finalrebate = totalrebate
replace finalrebate = AMP if totalrebate > AMP & genericindicator == 0
label variable finalrebate "Final rebate amount, if total rebate amount > AMP, final rebate = AMP"

*Drugs that hit the rebate cap
tab ndc_s9 Generic if totalrebate > AMP & genericindicator == 0

save "rebate_brand.dta", replace



/*************************************
Rebate calculation for generic drugs
*************************************/
use "rebate_brand.dta", clear
/*************************************
We calculate a basic rebate for all generic quarters
*************************************/
count if genericindicator == 1  
count if genericindicator == 1 & year >= 2017

/*************************************
Step 1: Basic Rebate Calculation
For "N" drugs, the unit rebate amount (URA) is equal to 13% of average manufacturer price (AMP).
This value is rounded to 6 decimal places and then to 4 decimal places
*************************************/
replace basicrebate = round(AMP * 0.13, 0.000001) if genericindicator == 1 & yearquarter < 20171

replace finalrebate = round(basicrebate, 0.0001) if genericindicator == 1 & yearquarter < 20171


/*************************************
Quarters 2017 and On
*************************************/

/*************************************
Step 1: Basic Rebate Calculation
For "N" drugs, the unit rebate amount (URA) is equal to 13% of average manufacturer price (AMP).
This value is rounded to 7 decimal places.
*************************************/
replace basicrebate = round(AMP * 0.13, 0.0000001) if genericindicator == 1 & year >= 2017

/*************************************
Step 2: Additional Rebate Calculation - use baseline of 2014 Q3
Additional rebate = (Baseline AMP / Baseline CPI-U) x Quarterly CPI-U (Rounded to 7 Places)
Compare the additional rebate amount to the quarterly AMP: 
	if the number is less than the quarterly AMP, subtract it from the quarterly AMP to determine the additional rebate amount; 
	if the number is equal to or greater than the quarter’s AMP, the additional rebate amount is equal to zero.

*The additional rebate amount is basically the baseline AMP * growth factor, or allowable growth.
	If it is equal or greater than AMP, it means AMP has not exceeded allowable growth, and the additional rebate is 0.
	If it is less than AMP, meaning AMP has exceeded allowable growth, the additional rebate is the amount that AMP
		has exceeded the allowable growth, aka AMP - allowable growth.
*************************************/
replace addrebate_amt = round((baselineAMP / baselineCPI) * CPI, 0.0000001) if genericindicator == 1 & year >= 2017 & AMP != .

replace addrebate_final = AMP - addrebate_amt if addrebate_amt < AMP & !missing(addrebate_amt) & !missing(AMP) & genericindicator == 1 & year >= 2017
replace addrebate_final = 0 if addrebate_amt >= AMP & !missing(addrebate_amt) & !missing(AMP) & genericindicator == 1 & year >= 2017
replace addrebate_final = 0 if addrebate_final == .& genericindicator == 1 & year >= 2017

*Checks
*Final additional rebate = AMP - additional rebate amount if additional rebate is less than AMP
*br ndc_s11 baselineAMP addrebate_amt AMP addrebate_final if addrebate_amt < AMP & !missing(addrebate_amt) & !missing(AMP) & genericindicator == 1 & year >= 2017
*Final additional rebate  = 0 if additional rebate is greater than or equal to AMP
*br ndc_s11 baselineAMP addrebate_amt AMP addrebate_final if addrebate_amt >= AMP & !missing(addrebate_amt) & !missing(AMP) & genericindicator == 1 & year >= 2017

/*************************************
Step 3: Total Rebate Calculation
Total Rebate = Basic Rebate + Additional Rebate (both rounded to 7 decimal places)
This amount is rounded to 6 places 
This amount is rounded to 4 places 
*************************************/
replace totalrebate_temp1 = basicrebate + addrebate_final if genericindicator == 1 & year >= 2017
replace totalrebate_temp2 = round(totalrebate_temp1, 0.000001) if genericindicator == 1 & year >= 2017
replace totalrebate = round(totalrebate_temp2, 0.0001) if genericindicator == 1 & year >= 2017

/*************************************
Step 4: Comparison of Total Rebate Amount to Quarterly AMP
If the total rebate amount is greater than the quarterly AMP, it is reduced to equal AMPAMPsource,
	and if not, the total rebate amount does not change.
*************************************/
replace finalrebate = totalrebate if genericindicator == 1 & year >= 2017
replace finalrebate = AMP if totalrebate > AMP & genericindicator == 1 & year >= 2017

*Drugs that hit the rebate cap
tab ndc_s9 Generic if totalrebate > AMP & genericindicator == 1 & year >= 2017


tab AMPsource genericindicator, m

*Check if there are duplicate records. All data is missing.
duplicates list ndc_s9 year quarter


save "fullrebatedata.dta", replace

/****************************************************************************
Only keep essential variables to merge with state data and calcualte rebate.
****************************************************************************/
use "fullrebatedata.dta", clear

sort ndc_s9 year quarter

*Look at 2 drugs we use in the rebate example
*br if ndc_s9 == "124961208" & year == 2018 & quarter == 1
*br if ndc_s9 == "503830287" & year == 2018 & quarter == 1


*Look at rebate as a percent of AMP
gen rebatepercAMP = finalrebate / AMP
summarize rebatepercAMP if genericind == 0 /* brand */
summarize rebatepercAMP if genericind == 0 [weight = imprx] /* brand */
summarize rebatepercAMP if genericind == 1 & yearquarter >= 20143 /* generic */
summarize rebatepercAMP if genericind == 1 & yearquarter >= 20143 [weight = imprx] /* generic */

*print Vivitrol
sort ndc_s9 year quarter
/*
export excel ndc_s9 year quarter AMP_SDUD AMP AMPsource ndc9_redASP baselineAMP /// 
	basicrebate addrebate_final finalrebate if Generic == "Vivitrol" using "${output}/Vivitrol rebate data.xlsx", firstrow(varlabels) sheetmodify
*/

keep ndc_s9 year quarter AMP_SDUD AMP basicrebate addrebate_final finalrebate AMPsource drug_5i
order ndc_s9 year quarter AMP_SDUD AMP basicrebate addrebate_final finalrebate AMPsource drug_5i

save "nationaltotal_rebates.dta", replace



/************************************************************************************
Print out rebate data for NDCs with highest prescription counts in 2018
************************************************************************************/

*Add in original SDUD data, with adjusted units and distributed national total + suppressed state spending/units to get NDC name
use "SDUD_imprx_distr.dta", clear
keep if year >= 2010

*We just want to keep the variable Generic by NDC
keep ndc_s9 Generic drugtype ndc_s1 ndc_s2 ndc_s3 
gsort ndc_s9 - Generic
duplicates drop ndc_s9 drugtype, force

merge 1:m ndc_s9 using "fullrebatedata.dta"
keep if _m == 3
drop _m


*Only keep 2018
drop if year != 2018

*Sort by number of units
gsort - year - units
keep if _n <= 50 | inlist(Generic, "Narcan", "Evzio", "Probuphine", "Vivitrol")
*br year quarter numberofprescriptions ndc_s11 utilizationtype productname Generic

egen ndc9 = concat(ndc_s1 ndc_s2), punct("-")
gen temp = ""
replace temp = drugtype if genericindicator == 1
egen drugname = concat(Generic temp), punct(" ")

label variable ndc9 "National Drug Code (5-4)"
label variable baselineyear "Baseline year - first year NDC appears in SDUD claims for this utilziation type"
label variable baselinequarter "Baseline quarter - first quarter NDC appears in SDUD for this utilziation type"
label variable baselineCPI "Baseline CPI-U, ie CPI-U for the first year/quarter NDC appears in SDUD"
label variable baselineAMP "Baseline AMP, ie AMP for first year/quarter NDC appears in SDUD"
label variable Generic "Drug name/generic status"
label variable drugtype "Drug type (buprenorphine, naltrexone or naloxone)"
label variable quarter "Quarter"
label variable ndc9_redASP "ASP for 5i drugs, reduced from reported ASP+6% to just ASP - brand drugs only, by NDC-9"
label variable avg_weightedAMP "Weighted AMP from FUL file - generic drugs only, by NDC-9"
label variable avg_NADAC_unit "NADAC per unit - generic drugs only, by NDC-9"
label variable drug_5i "5i drug - 1 if yes, 0 if no, missing if generic"
label variable imprx "Number of prescriptions reimbursed, imputed if suppressed"
label variable units "Number of units reimbursed, from SDUD and edited from package size"
label variable drugname "Drug name/type"

keep ndc9 drugname drugtype state year quarter imprx units  ///
baselineyear baselinequarter baselineAMP baselineCPI CPI ///
AMP_SDUD drug_5i ndc9_redASP /*ASP_AMP_ratio*/ avg_weightedAMP avg_NADAC_unit ///
AMP AMPsource basicrebate addrebate_amt addrebate_final totalrebate finalrebate
 
order ndc9 drugname drugtype state year quarter imprx units   ///
baselineyear baselinequarter baselineAMP baselineCPI CPI ///
AMP_SDUD drug_5i ndc9_redASP /*ASP_AMP_ratio*/ avg_weightedAMP avg_NADAC_unit ///
AMP AMPsource basicrebate addrebate_amt addrebate_final totalrebate finalrebate

*Export to rebate summary doc
*export excel using "${output}/Urban AV_Medicaid SDUD_Rebate estimates for highest prescribed MOUD Rx V7.xlsx", sheet("National total, rebate calc") firstrow(varlabels) sheetmodify

*Save list of NDCs
keep ndc9 year quarter
gen ord = _n
save "ndcs_toprint_forsummary.dta", replace


/****************************************************************************
Merge calculated national total rebates with state data and apply rebate to 
	Medicaid amount spent (not total) for states
****************************************************************************/
use "SDUD_imprx_distr.dta", clear
keep if year >= 2010 

*Drop state == "XX" we'll calculate the sum of the states in the next program
drop if state == "XX"

*Values that have imprx <= 5 and/or suspected bunled payments won't match 
merge m:1 ndc_s9 year quarter using "nationaltotal_rebates.dta"
tab imprx if _m == 1 & (year != $lastyr & quarter != $lastqtr)
drop _m

*Variable that is the year and quarter
egen yearquarter = concat(year quarter)
destring yearquarter, replace

*Count total quarters
tab genericind if year != 2019, m /* all */

/* brand quarters that are non-zero, non-suppresed and have a rebate amount */
count if genericind == 0 & year != 2019 & medicaidamountreimbursed != . & medicaidamountreimbursed != 0 & finalrebate != .

/* generic quarters that are non-zero, non-suppressed and have a rebate amount */
count if genericind == 1 & year != 2019 & medicaidamountreimbursed != . & medicaidamountreimbursed != 0 & finalrebate != .

*Rename rebate variable to indicate that it's the rebate per unit
rename finalrebate finalrebate_perunit

*The rebate is per unit. Multiply by the number of units to get rebate amount for this value
gen finalrebate_perqtr = finalrebate_perunit * units

*Subtract the rebate amount from the Medicaid amount spent 
gen adjmedamt = medicaidamountreimbursed - finalrebate_perqtr

*If we didn't calculate a rebate for the national total, just subtract the basic rebate
replace adjmedamt = medicaidamountreimbursed - (medicaidamountreimbursed * .231) if adjmedamt == . & medicaidamountreimbursed != . & genericindicator == 0
replace adjmedamt = medicaidamountreimbursed - (medicaidamountreimbursed * .13) if adjmedamt == . & medicaidamountreimbursed != . & genericindicator == 1

*If we suspect this is a bundled care obs (unadj spending = 0 and rx > 0), don't subtract the rebate amount
*Even if there is a positive non-Medicaid amount but a 0 Medicaid amount, we don't give Medicaid the full rebate
replace adjmedamt = 0 if medicaidamountreimbursed == 0 & imprx > 0

*Check how many rebate amounts are higher than the Medicaid amount spent
gen rebate_0 = 1 if adjmedamt < 0
tab rebate_0 genericindicator, m
drop rebate_0

*According to Sean, if the rebate amount is greater than the amount Medicaid paid, Medicaid is still eligible for the full rebate
*replace adjmedamt = 0 if adjmedamt < 0

*Rename variable that is Medicaid spending pre-rebate
rename medicaidamountreimbursed unadjmedamt

egen ndc = concat(ndc_s1 ndc_s2 ndc_s3), punct("-")

label variable ndc "National Drug Code (5-4-2)"
label variable utilizationtype "FFS or MCO"
label variable AMP "Average Manufacturer Price (AMP)"
label variable AMPsource "Source for AMP calculation"
label variable finalrebate_perunit "Final rebate amount per unit, calculated at the national level"
label variable finalrebate_perqtr "Final rebate amount for this quarter"
label variable adjmedamt "Final Medicaid amount spent after rebate"
label variable Generic "Drug name/generic status"

sort state utilizationtype year quarter ndc

*Look at rebate as a percent of spending
gen rebatepercSPEND = finalrebate_perqtr / unadjmedamt
summarize rebatepercSPEND if genericind == 0 /* brand */
summarize rebatepercSPEND if genericind == 0 [weight = imprx], detail /* brand */
summarize rebatepercSPEND if genericind == 1 & yearquarter >= 20143, detail /* generic */
summarize rebatepercSPEND if genericind == 1 & yearquarter >= 20143 [weight = imprx], detail /* generi */


save "allSDUD_rebate.dta", replace


/****************************************
Print data for highest prescribed drugs
*****************************************/
use "allSDUD_rebate.dta", clear

gen ndc9 = substr(ndc, 1, 10)

keep ndc ndc9 state year quarter utilizationtype Generic units imprx ///
	totalamountreimbursed AMP AMPsource finalrebate_perunit finalrebate_perqtr unadjmedamt adjmedamt
order ndc ndc9 state year quarter utilizationtype Generic units imprx ///
	totalamountreimbursed AMP AMPsource finalrebate_perunit finalrebate_perqtr unadjmedamt adjmedamt

*Export full data by generic/brand
*export excel if Generic != "generic" using "${output}/Rebate analysis summary.xlsx", sheet("State NDC-level brand") firstrow(varlabels) sheetreplace
*export excel if Generic == "generic" using "${output}/Rebate analysis summary.xlsx", sheet("State NDC-level generic") firstrow(varlabels) sheetreplace

* Print rebate for the NDCs printed at the national toal level
merge m:1 ndc9 year quarter using "ndcs_toprint_forsummary.dta"
keep if _m == 3
drop _m

sort ord ndc state quarter utilizationtype
drop ord
*export excel using "${output}/Urban AV_Medicaid SDUD_Rebate estimates for highest prescribed MOUD Rx V7.xlsx", sheet("States, rebate applied") firstrow(varlabels) sheetmodify




/****************************************
Final summary numbers
*****************************************/
*global output "${drive}:\Users\\${user}\Box\LJAF Medicaid SDU\2 Analysis\Quarterly Updates - Medicaid Spending on 3 Drugs\\${lastyr} Q${lastqtr}\Output"
*putexcel set "${output}/Check rebate ${lastyr} Q${lastqtr}.xlsx", sheet("Summary adj vs unadj spend") modify
putexcel set "${output}/Urban AV_Medicaid SDUD_Rebate estimates for highest prescribed MOUD Rx V8.xlsx", sheet("Summary adj vs unadj spend") modify

*All years
use allSDUD_rebate.dta, clear
drop if year == 2019
collapse (sum) unadjmedamt adjmedamt, by(drugtype genericindicator)
decode genericindicator, gen (generic)
drop genericindicator
tempfile temp1
save "`temp1'"
collapse (sum) unadjmedamt adjmedamt, by(drugtype)
gen generic = "All"
append using "`temp1'"
sort drugtype generic

gen rebateperc = (unadjmedamt - adjmedamt) / unadjmedamt * 100

mkmat unadjmedamt adjmedamt
mat def print = (unadjmedamt, adjmedamt)

putexcel B5 = mat(print)

*2018
use allSDUD_rebate.dta, clear
keep if year == 2018
collapse (sum) unadjmedamt adjmedamt, by(drugtype genericindicator)
decode genericindicator, gen (generic)
drop genericindicator
tempfile temp1
save "`temp1'"
collapse (sum) unadjmedamt adjmedamt, by(drugtype)
gen generic = "All"
append using "`temp1'"
sort drugtype generic

gen rebateperc = (unadjmedamt - adjmedamt) / unadjmedamt * 100

mkmat unadjmedamt adjmedamt
mat def print = (unadjmedamt, adjmedamt)

putexcel B16 = mat(print)




/****************************************
Check what's going on with 2013 and 2014 bup
*****************************************/
use "allSDUD_rebate.dta", clear
keep if year == 2013 | year == 2014
keep if drugtype == "bup"

gen rebateperc = (unadjmedamt - adjmedamt) / unadjmedamt * 100

drop year_quarter
egen yearqtr = concat(year quarter)

bys yearqtr: summarize rebateperc

sort yearqtr ndc_s11 state
*br state utilizationtype ndc_s11 Generic drugtype year quarter imprx units SDUDunits SDUD_editedunits SDUD_editedunits unadjmedamt adjmedamt finalrebate_perunit finalrebate_perqtr rebateperc if ndc_s11 == "12496130602"

bys yearqtr: egen totunits = total(units)
bys yearqtr: egen totexpectedunits = total(expectedunits)
gen expected_units = totexpectedunits / totunits

tab  yearqtr expected_units

gen SDUD_editedunits =  units / SDUDunits
 
tab ndc_s11
tab ndc_s11 if rebateperc > 60
 
 

 /****** Check national total level ******/
use "fullrebatedata.dta", clear 
*keep if year == 2013 | year == 2014
keep if drugtype == "naloxone"
keep if genericind == 1

gen rebateshare = (finalrebate * units) / totalamountreimbursed * 100
gen rebateAMP = (finalrebate) / AMP * 100
gen medshare = medicaidamountreimbursed / totalamountreimbursed * 100
gen medspendgrowth = medicaidamountreimbursed / medicaidamountreimbursed[_n-1]

sort year quarter ndc_s9
br ndc_s9 year quarter imprx totalamountreimbursed medicaidamountreimbursed units baselineyear baselinequarter baselineAMP AMP FSS_ndc9 basic_rebate_23 basic_rebate_BP basicrebate basicrebatesource addrebate_amt addrebate_final totalrebate finalrebate rebateshare rebateAMP


/** Notes
2013 adn 2014 brand bup have no 5i drugs - 1 quarter of Bunavail, 47 Suboxone, 3 Subutex, 9 Zubsolv

(1) 124961202 - 2013 Q3 and 4 BP is -0.03333
	FSS BP is around 70/80, steadily increasing, and is -1 for 2013 Q3 and 4
	When we divide by units (30), we get a value of -0.03 for these quarters
(2) 124961208 - 2013 Q3 and 4 BP is -0.03333
	Same as above - FSS BP is around 140/150, steadily increasing, and is -1 for 2013 Q3 and 4
	When we divide by units (30), we get a value of -0.03 for these quarters
(3) 124961283 - FSS is 1.8 for all 2013 quarters and 3.36 for all 2014 quarters
	FSS values are steady before and after, which means this might be a real jump
(4) 124961306 - FSS is 3.4 for all 2013 quarters and 6.0 for all 2014 quarters
	FSS values are steady before and after, which means this might be a real jump
(5) 541230957 - FSS starts in 2014 2, basic rebate and final rebate jump up $1 
 
 
 
124961204 - normal
124961212 - normal
124961278 - normal
124961310 - no FSS data
541230914 - normal
 
*/
 
/****** Check why rebate is such a larger % in 2018 then 2017 for 0.4mg/1mL generics ******/
use "fullrebatedata.dta", clear 
 
keep if inlist(ndc_s9, "004091212", "004091215", "004091782", "006416132", "174780041", "674570292", "674570599", "700690071")
keep if year == 2017 | year == 2018

sort ndc_s9 year
gen rebateshare = finalrebate / AMP * 100
br ndc_s9 imprx year quarter baselineyear baselinequarter baselineAMP AMP AMPsource AMP_SDUD basicrebate addrebate_amt addrebate_final finalrebate  rebateshare
 
 
 
*Check Evzio launch price
use "fullrebatedata.dta", clear 
keep if Generic == "Evzio"
sort ndc_s9 year quarter
br ndc_s9 imprx year quarter baselineyear baselinequarter baselineAMP AMP AMPsource AMP_SDUD basicrebate addrebate_amt addrebate_final finalrebate  

 