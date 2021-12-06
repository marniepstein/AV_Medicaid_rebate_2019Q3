/***************************************************************************
Project: Medicaid Spending on 3 Drugs, Quarterly Updates

Purpose: This program imputes prescriptions for cells that are suppressed in the 
			SDUD raw data because the number of prescriptions is below 11.

Author: Marni Epstein

Date: Dec 20, 2018

Input files: intermediate.dta, created in P1
Output files: SDUD_imprx.dta

Instructions and Notes:
	A good NDC to test the imputation process is rx00054017713_39
	Made some edits to the imputation process--mainly with condition =1, where the national total is suppressed and two or more states are also suppressed
		We impute 1 or 2 using the rule that is used with condition 2 (based on quarter before or after) to fill
		Need to make sure that the new total doesn't exceed 10

	****************************************************************
	2019 Q3 / 3/11/20 data download:
	There are NO SUPPRESSED OBSERVATIONS in the public SDUD files
	There is nothing on the website about this change, since ususally all obs with prescriptions < 11 are fully suppressed
	This means we do not impute any prescription counts. Run this program anyway to create the variable imprx, 
		even though we will use the prescription counts from the files
	****************************************************************

	
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

*Enter today's date to create unique log
global today=031220

*Enter drive letter
*global drive = "C"
global drive = "D"

/****************************************************************
UPDATE DIRECTORIES - WILL UPDATE AUTOMATED BASED ON GLOBALS ABOVE
****************************************************************/

cd "${drive}:\Users\\${user}\Box\LJAF Medicaid SDU\2 Analysis\Quarterly Updates - Medicaid Spending on 3 Drugs\\${lastyr} Q${lastqtr}\Data"
global output "${drive}:\Users\\${user}\Box\LJAF Medicaid SDU\2 Analysis\Quarterly Updates - Medicaid Spending on 3 Drugs\\${lastyr} Q${lastqtr}\Output" 
global log "${drive}:\Users\\${user}\Box\LJAF Medicaid SDU\2 Analysis\Quarterly Updates - Medicaid Spending on 3 Drugs\\${lastyr} Q${lastqtr}\Logs" 
global nsduh "${drive}:\Users\\${user}\Box\LJAF Medicaid SDU\1 Data\NSDUH State Tables"
global acs "${drive}:\Users\\${user}\Box\LJAF Medicaid SDU\1 Data\ACS"
global medicaid "${drive}:\Users\\${user}\\Box\LJAF Medicaid SDU\1 Data\Medicaid enrollment data"

 *Create global for current year and quarter
global yearquarter = "${lastyr}Q${lastqtr}"

*Turn log on
log using "${log}\P2_imputing_rx_for_suppressed_cells_${today}.log",  replace


*Increase max variable limit
clear
clear matrix 
clear mata
set maxvar 120000 /* max value */


/************************************************************
Save each NDC # in a unique globals, labeled NDC1-NDC#
Use final dataset from P2, which includes the Medicaid rebate
*************************************************************/
use "intermediate.dta", clear

/********
* NOTE: uncomment this if you want to run the imputation program only on 2010 and later
* We run it on the earlier years to get rx in order to estimate spending for suppressed obs, which we use for baseline data for the rebate

*We only want to impute rx for obs 2010 and later. We need to keep the earlier ones for the rebate calculation
keep if year < 2010
save "earlyyrs.dta", replace
tab year

*Only use later years
use "intermediate.dta", clear

*We only want to impute rx for obs 2010 and later. We need to keep the earlier ones for the rebate calculation
keep if year >= 2010
*********/

*Collapse to get one row per NDC
collapse (sum) rx, by (ndc_s11)

*Count the number of obs in the dataset
count
gl numndcs = r(N)

*Save each NDC in a global
forvalues i = 1/$numndcs {
	gl ndc`i' = ndc_s11[`i']
	
	di "NDC `i' = " ndc_s11[`i']
}

di "Total NDC Codes = $numndcs"


/*********************************************************
Reshape data to wide for the imputation process. 
Note that you have to increase the max number of variables
**********************************************************/
/* Use SDUD data for 3 drugs. This is at the claim (drug) level */
use "intermediate.dta", clear

*Impute Rx for ALL years
*keep if year >= 2010

tab suppressionused, m

*Replace suppressed Rx values as "999999999"
replace rx = 999999999 if suppressionused == "true"

*Create a counter for quarters
egen count = group(year quarter)
gen fill = "_"
egen qtrcount = concat(fill count)

*Save total number of quarters in a global
egen numqtrs = max(count)
summarize numqtrs
global numqtrs = r(mean)

/********
For some reason, there is a duplicate row for one NDC for 2014 quarter 4, national totals in the 2018 Q3 data download
Check if there are any duplicates in this data download.
It is suppressed. Delete the duplicate row so we can reshape. Check that only one row is deleted
ndc_s11 == "00056001170" & state == "XX" & year == 2014 & quarter == 4
********/
duplicates drop state utilizationtype ndc_s11 quarter year, force

*Save original dataset with qtrcount, which we will use to merge the imputed data back in later
sort state qtrcount utilizationtype ndc_s11
save "SDUD_qtrcount.dta", replace


*Convert to wide by quarter
use "SDUD_qtrcount.dta", clear
keep state utilizationtype ndc_s11 rx qtrcount

*Reshape wide by NDC
reshape wide rx, i(state utilizationtype qtrcount) j(ndc_s11) string
reshape wide rx*, i(state utilizationtype) j(qtrcount) string

order rx*, sequential
order state utilizationtype 

*Replace missings with zero. We get a lot of missings from the reshape if there isn't NDC data for a particular quarter.
* Loop through all quarters for each NDC variable
forvalues i = 1/$numndcs { 		//loop through the number of NDCs
	forvalues j = 1/$numqtrs { 	//loop through the number of quarters 
		di "rx${ndc`i'}_`j'"
		replace rx${ndc`i'}_`j' = 0 if rx${ndc`i'}_`j' == .
	}
	
}

save "test.dta", replace

*Create a blank variable that will be 0/1 for suppressed or not for each NDC quarter. 
*It will be cleared at the start of the loop each time.
gen sup = .

*Create variable since we drop it and re-create it each time we go into the 3rd condition
gen notsup_tot = .
		
		
/***************************************************************
Loop through: FFS/MCO, then NDCs, then quarters we have data for
***************************************************************/



*Loop through utilization types (FFS/MCO)
foreach type in FFSU MCOU {

	*Loop through NDCs
	forvalues i = 1/$numndcs {

		*Loop through quarters
		forvalues qtr = 1/$numqtrs{

			di ""
			di "NDC = ${ndc`i'},  Quarter = `qtr', Utilization tpe = `type'"
			di ""
			
			replace sup = .

			*Create globals for the quarter before and after
				gl before = `qtr' - 1
				gl after = `qtr' + 1

				*If first or last quarter, assign the before and after to be the same.
				*Since we use an "or" statement to determine whether the quarter before or after is zero/suppressed, this allows the progarm to run normally
				if `qtr' == 1 {
					gl before =  2
				}
				else if `qtr' == $numqtrs {
					gl after = $numqtrs - 1
				}	

				di "before = $before, quarter = `i', after = $after"


			*Count number of states with suppresed values for this NDC in this year/quarter and utilization type
			count if rx${ndc`i'}_`qtr' == 999999999 & state != "XX" & utilizationtype == "`type'"
			gl sup_states = r(N)
			*Tag suppressed states/utilization types
			replace sup = 1 if rx${ndc`i'}_`qtr' == 999999999 & state != "XX" & utilizationtype == "`type'"
			
			*Count the number of states that don't have suppressed values for this NDC in this year/quarter and utilization type
			count if rx${ndc`i'}_`qtr' != 999999999 & state != "XX" & utilizationtype == "`type'"
			gl notsup_states = r(N)
			replace sup = 0 if rx${ndc`i'}_`qtr' != 999999999 & state != "XX" & utilizationtype == "`type'"
			
			*Check if the national total is suppressed and save it's value
			list rx${ndc`i'}_`qtr' if state == "XX"  & utilizationtype == "`type'"
			summarize rx${ndc`i'}_`qtr' if state == "XX"  & utilizationtype == "`type'"
			gl nattot = r(mean)


			/*****************
			(1) If the national total is suppressed and two or more states are also suppressed:
				(a)	1: For an SDUD quarter that is zero or suppressed before or after the suppression
				(b)	2: For the SDUD quarters that have a non-suppressed value before and after the suppressed value
			However, if doing this leads to over 10 prescriptions, distribute one prescription to each state.
			******************/
			if $nattot == 999999999 & $sup_states > 1 {
				di "Condition 1: National total is suppressed and more than one state is suppressed"

				replace rx${ndc`i'}_`qtr' = 1 if sup == 1 & (inlist(rx${ndc`i'}_${before}, 999999999, 0) | inlist(rx${ndc`i'}_${after}, 999999999, 0))
				replace rx${ndc`i'}_`qtr' = 2 if sup == 1 & (!inlist(rx${ndc`i'}_${before}, 999999999, 0) & !inlist(rx${ndc`i'}_${after}, 999999999, 0))
				
				*Count how many imputed prescriptions this leads to
				egen imp_rx_cond1 = total(rx${ndc`i'}_`qtr') if sup == 1
				summarize imp_rx_cond1
				gl imp_rx_cond1 = r(mean)
				drop imp_rx_cond1
				
				*If this leads to over 10 prescriptions, distribute just 1 to all suppressed states
				if $imp_rx_cond1 > 10 {
					replace rx${ndc`i'}_`qtr' = 1 if sup == 1 
				}
				
			}


			/******************
			(2) If the national total is suppressed and only one state is suppressed, 
				(a) Impute 1 if the quarter before or after is zero or suppressed.
				(b) Impute 4 if the quarters before or after aren't zero or suppressed.
			******************/
			else if $nattot == 999999999 & $sup_states == 1 {
				
				di "Condition 2: National total is suppressed and only one state is suppressed"

				replace rx${ndc`i'}_`qtr' = 1 if sup == 1 & (inlist(rx${ndc`i'}_${before}, 999999999, 0) | inlist(rx${ndc`i'}_${after}, 999999999, 0))
				replace rx${ndc`i'}_`qtr' = 4 if sup == 1 & (!inlist(rx${ndc`i'}_${before}, 999999999, 0) & !inlist(rx${ndc`i'}_${after}, 999999999, 0))
			}

			/********************
			(3) If the national total is not suppressed and at least one state is suppressed, distribute the national total in a 1:4 ratio:
				(a)	1: For an SDUD quarter that is zero or suppressed before or after the suppression
				(b)	4: For the SDUD quarters that have a non-suppressed value before and after the suppressed value
			********************/
			if $nattot != 999999999 & $sup_states >= 1 {
		
				di "Condition 3: National total is not suppressed and at least one state is suppressed"

				*Sum the number of prescriptions from all of the non-suppressed states
				drop notsup_tot
				egen notsup_tot = total(rx${ndc`i'}_`qtr') if sup == 0
				summarize notsup_tot
				gl notsup_tot = r(mean)

				*Calculate the amount to distribute across the suppressed states
				gl todistribute = $nattot - $notsup_tot
				
				*Check that the number of prescriptions to distribute among the suppressed states is less than
				*	10*the number of suppressed states. Print a message in the log if not.
				gl check ${todistribute}-(${sup_states}*10)
				if $check > 0 {
					di "WARNING: THE NUMBER OF PRESCRIPTIONS TO DISTRIBUTE AMONG THE SUPPRESSED STATES"
					di "FOR `type' NDC ${ndc`i'} QUARTER `qtr' IS GREATER THAN 10 * THE NUMBER OF SUPPRESSED STATES"
					di "National total: $nattot "
					di "Number of suppresed states: $sup_states "
					di "States with suppressed values for this NDC and Utilization type:"
					list state if rx${ndc`i'}_`qtr' == 999999999 & utilizationtype == "`type'"
				}
				
				*Check that the number of prescriptions to distribute is not less than 0. If it is, it's likely because of unsuppresed data
				if ${todistribute} < 0 {
					di "WARNING: THE NUMBER OF PRESCRIPTIONS TO DISTRIBUTE IS LESS THAN 0. THIS WILL CREATE NEGATIVE IMPRX VALUES"
					di "FOR `type' NDC ${ndc`i'} QUARTER `qtr'. National total: $nattot. Sum of nonsuppressed states: $notsup_tot"
					di "States with suppressed values for this NDC and Utilization type:"
					list state if rx${ndc`i'}_`qtr' == 999999999 & utilizationtype == "`type'"
				}	
				
				*If the number of prescriptions to distribute is less than 0, replace with 0
				if ${todistribute} < 0 {
					global todistribute = 0
				}
					
				*Count the number of suppressed states with a weight of 1: the quarter before or after is zero or suppressed
				count if sup == 1 & (inlist(rx${ndc`i'}_${before}, 999999999, 0) | inlist(rx${ndc`i'}_${after}, 999999999, 0))
				gl wt1 = r(N)
				
				*Count the number of suppressed states with a weight of 4: the quarters before and after are not zero or suppressed
				count if sup == 1 & (!inlist(rx${ndc`i'}_${before}, 999999999, 0) & !inlist(rx${ndc`i'}_${after}, 999999999, 0))
				gl wt4 = r(N)
				
				*Total weight 
				gl totwt = 1*$wt1 + 4*$wt4
				
				*Distribute the national total based on the total weight and 1:4 ratio
				replace rx${ndc`i'}_`qtr' = round(${todistribute}/${totwt}) if sup == 1 & (inlist(rx${ndc`i'}_${before}, 999999999, 0) | inlist(rx${ndc`i'}_${after}, 999999999, 0))
				replace rx${ndc`i'}_`qtr' = round((${todistribute}/${totwt})*4) if sup == 1 & (!inlist(rx${ndc`i'}_${before}, 999999999, 0) & !inlist(rx${ndc`i'}_${after}, 999999999, 0))
				
				*Need to make sure new total (after imputation) equals the unsuppressed national total
				egen imp_rx_newtotal = total(rx${ndc`i'}_`qtr') if utilizationtype == "`type'" & state != "XX"
				sum imp_rx_newtotal 
				gl imp_rx_newtotal = r(mean)
				drop imp_rx_newtotal
				
				
				gl toedit = $nattot - $imp_rx_newtotal
				di "Difference between unsuppressed national total and new imputed national total: ${toedit}"
				
				*Create a counter variable for each state that has a suppressed value but an unsuppressed national total
			    egen stcount = group(state sup utilizationtype) if sup == 1
				
				if $toedit > 0 {
					forvalues f = 1/$toedit {
						replace rx${ndc`i'}_`qtr' = rx${ndc`i'}_`qtr' + 1 if stcount == `f'
					}	
				}	
					
				else if $toedit < 0 {
					gl toedit_neg = ${toedit}* -1
					forvalues f = 1/$toedit_neg {
						replace rx${ndc`i'}_`qtr' = rx${ndc`i'}_`qtr' - 1 if stcount == `f'
				}

			}
			drop stcount
		}
			
			else {
				di "No suppressed states"
				
			}	
			
		} //end quarter loop

	} // end NDC loop

} //end utilization type loop

save imprx_intermediate, replace



*We need to overwrite the NDCs with suppressed national totals to match the new totals that we just imputed.
drop if state == "XX"
collapse (sum) rx*, by (utilizationtype)

gen state = "newXX"
save newtotal, replace
use imprx_intermediate, clear
append using "newtotal", force
drop if state == "XX"
replace state = "XX" if state == "newXX"
save imprx_intermediate, replace


/**************************************************************************************************
Reshape to long. We have to do this one NDC at a time since the variable names need the same prefix
***************************************************************************************************/

drop sup notsup_tot

tempfile longdata

*We have to reshape long one NDC at a time because the variable prefixes have to be the same
forvalues num = 1/$numndcs {
	di "Reshape back to long: NDC #`num'"
	
	preserve
	
	*Keep all the variables for this NDC
	keep state utilizationtype rx${ndc`num'}_* //-rx${ndc`num'}_$numqtrs
	reshape long rx, i(state utilizationtype) j(ndc_qtr) string

	*If this isn't the first NDC, add it on to an accumulating file
	if `num' != 1 {
		append using "`longdata'"
	}
	
	save "`longdata'", replace
	restore
}

use "`longdata'", clear



*Separate ndc_qtr into NDC and Quarter count variable, which we use to merge onto full dataest
split ndc_qtr, p("_")
rename ndc_qtr1 ndc_s11
rename ndc_qtr2 count
destring count, replace

rename rx imprx 
save "tomerge_wimprx.dta", replace

use "tomerge_wimprx.dta", clear

*Merge back with original dataset
sort state count utilizationtype ndc_s11
merge 1:1 state count utilizationtype ndc_s11 using "SDUD_qtrcount.dta"

/*************
Check: There should be no _m == 2 (from using only). Every original obs from the 
	first dataset should match to the new reshaped data. 
	In the reshape, all quarters get a missing value if they don't have the NDC, so there are many 
	blank (replaced with zero) cells. Only keep state/quarter/NDCs from the original dataset
************/
keep if _m == 3
drop _m

*Drop variables created in this program that we don't want to keep
drop ndc_qtr count fill qtrcount numqtrs

*Convert suppressed values in the original RX variable back to missing that we changed to 999999999 
replace rx = . if rx == 999999999

*Check if any suppressed values are left in states. There should be no suppressed values left in non-natinoal totals.
*Change suppressed national totals back to 0
replace imprx = . if imprx == 999999999 & state != "XX" /* states */
replace imprx = . if imprx == 999999999 & state == "XX" /* national totals */

*Add early years back in. We need them for the rebate calculation
*append using "earlyyrs.dta"

/* NOTE: we don't use this code in 2019 Q3 because there is no unsuppresse data 
*Calculate spending based on unsuppressed spending per rx for the newly imputed prescriptions
replace totalamountreimbursed = totalamount_perrx * imprx if calctotspend_afterimprx == 1
replace medicaidamountreimbursed = medicaidamount_perrx * imprx if calctotspend_afterimprx == 1
replace units = units_perrx * imprx if calctotspend_afterimprx == 1

replace suppressionused = "Unsup data , but unsup rx > 11" if calctotspend_afterimprx == 1
*/

*See how many obs are still missing 
count if missing(imprx) & year > 2010
count if missing(totalamountreimbursed) & year > 2010 & year != 2019
count if missing(medicaidamountreimbursed) & year > 2010 & year != 2019
count if missing(units) & year > 2010 & year != 2019

save "SDUD_imprx.dta", replace


log close










