/***************************************************************************
Project: Medicaid Spending on 3 Drugs, Tracking brief

Purpose: This program outputs data for the figures used in the 2019 Q2 release brief.
		 It uses annual spending and prescriptions, 2010-2019 Q2.
		 

Author: Marni Epstein

Date: January 16, 2018
Updated: March 19, 2020

Input files: Box Sync\LJAF Medicaid SDU\2 Analysis\Quarterly Updates - Medicaid Spending on 3 Drugs\2019 Q3\Data\allSDUD_rebate.dta


***************************************************************************/

/***********************
SET GLOBALS - CHANGE
***********************/

*Enter user (computer name)
global user = "EWiniski"
*global user = "MEpstein"

*Enter last year and quarter that we have SDUD data 
global lastyr = 2019
global lastqtr = 3

*Enter version of output document, if applicable
global v = "1"

*Enter today's date to create unique log
global today=032620

*Enter computer drive
global drive = "C"

*Enter Box of Box sync
global box = "Box"

/****************************************************************
UPDATE DIRECTORIES - WILL UPDATE AUTOMATED BASED ON GLOBALS ABOVE
****************************************************************/

cd "${drive}:\Users\\${user}\\${box}\LJAF Medicaid SDU\2 Analysis\Quarterly Updates - Medicaid Spending on 3 Drugs\\${lastyr} Q${lastqtr}\Data"
global output "${drive}:\Users\\${user}\\${box}\LJAF Medicaid SDU\2 Analysis\Quarterly Updates - Medicaid Spending on 3 Drugs\\${lastyr} Q${lastqtr}\Output" 
global log "${drive}:\Users\\${user}\\${box}\LJAF Medicaid SDU\2 Analysis\Quarterly Updates - Medicaid Spending on 3 Drugs\\${lastyr} Q${lastqtr}\Logs" 

 *Create global for current year and quarter
global yearquarter = "${lastyr}Q${lastqtr}"



/****************************************************************************************************************************
Export data for tables and figures for brief
All figures are for national totals
****************************************************************************************************************************/

/*************************************************************************************************************
FIGURE 1
Medicaid Spending on Buprenorphine, Naltrexone, and Naloxone Prescriptions for OUD from 2010 to 2018
*************************************************************************************************************/
use "annual_drug.dta", clear
keep if state == "XX"
drop if inlist(year, 2008, 2009, 2019)

keep state year drugtype adjmedamt
format %12.0g adjmedamt
reshape wide adjmedamt, i(state drugtype) j(year)

*Print spending in millions
forvalues year = 2010/2018 {
	replace adjmedamt`year' = adjmedamt`year' / 1000000
	label variable adjmedamt`year' "`year' Spending (millions)"
}

export excel using "${output}\Brief Figures_${yearquarter}${v}.xlsx", sheet("Figure 1", modify) firstrow(varlabels)


/*************************************************************************************************************
FIGURE 2
Medicaid Spending on All Prescriptions for OUD, by State Expansion Status from 2010 to 2018 
*************************************************************************************************************/
use "annual_drug.dta", clear
drop if inlist(year, 2008, 2009, 2019)
keep if drugtype == 0
collapse (sum) adjmedamt, by(expansion year)
reshape wide adjmedamt, i(expansion) j(year)

*Print spending in millions
forvalues year = 2010/2018 {
	replace adjmedamt`year' = adjmedamt`year' / 1000000
	label variable adjmedamt`year' "`year' Spending (millions)"
}

export excel using "${output}\Brief Figures_${yearquarter}${v}.xlsx", sheet("Figure 2") sheetmodify firstrow(varlabels)


/*************************************************************************************************************
FIGURE 3
Medicaid Spending on Buprenorphine, Naltrexone, and Naloxone Prescriptions for OUD, 
by State Expansion Status from 2010 to 2018 
*************************************************************************************************************/
use "annual_drug.dta", clear
drop if drugtype == 0
drop if inlist(year, 2008, 2009, 2019)

collapse (sum) adjmedamt, by(expansion year drugtype)
reshape wide adjmedamt, i(expansion drugtype) j(year)

sort drugtype expansion
order drugtype expansion

forvalues year = 2010/2018 {
	replace adjmedamt`year' = adjmedamt`year' / 1000000
	
	label variable adjmedamt`year' "`year' Spending (millions)"
}
export excel using "${output}\Brief Figures_${yearquarter}${v}.xlsx", sheet("Figure 3") sheetmodify firstrow(varlabels)


/*************************************************************************************************************
FIGURE 4
Medicaid-Covered Prescriptions for Buprenorphine, Naltrexone, and Naloxone Prescriptions for OUD, 
by State Expansion Status from 2010 to 2018 
*************************************************************************************************************/
use "annual_drug.dta", clear
drop if drugtype == 0
drop if inlist(year, 2008, 2009, 2019)

collapse (sum) imprx, by(expansion year drugtype)
format %12.0g imprx
reshape wide imprx, i(expansion drugtype) j(year)

sort drugtype expansion
order drugtype expansion

export excel using "${output}\Brief Figures_${yearquarter}${v}.xlsx", sheet("Figure 4") sheetmodify firstrow(varlabels)


/*************************************************************************************************************
FIGURE 5
Medicaid-Covered Prescriptions for Buprenorphine, Naltrexone, and Naloxone Prescriptions for OUD 
per 1,000 Medicaid Enrollees with OUD, by State Expansion Status from 2010 to 2018 
*************************************************************************************************************/

use "annual_drug.dta", clear
drop if drugtype == 0
drop if inlist(year, 2008, 2009, 2019)

collapse (sum) imprx medicaid_A , by(expansion year drugtype)
gen percap_rx = (imprx) / medicaid_A * 1000

drop imprx medicaid_A
reshape wide percap_rx, i(expansion drugtype) j(year)

sort drugtype expansion
order drugtype expansion

export excel using "${output}\Brief Figures_${yearquarter}${v}.xlsx", sheet("Figure 5", modify) firstrow(varlabels) /* CHANGE BACK TO CORRECT FIGURE NUMBER */



/*************************************************************************************************************
FIGURE X - Not included in brief, but leave in output doc
Medicaid Spending on Buprenorphine, Naltrexone, and Naloxone Prescriptions for OUD 
per 1,000 Medicaid Enrollees with OUD from 2010 to 2018 
*************************************************************************************************************/
use "annual_drug.dta", clear
keep if state == "XX"
drop if inlist(year, 2008, 2009, 2019)

keep state year drugtype percap_adjmedamt
reshape wide percap_adjmedamt, i(state drugtype) j(year)

export excel using "${output}\Brief Figures_${yearquarter}${v}.xlsx", sheet("Figure X", modify) firstrow(varlabels) /* Make sure file path is updated to correct version */


/*************************************************************************************************************
APPENDIX TABLE 1
Medicaid Spending on Buprenorphine, Naltrexone, and Naloxone Prescriptions for OUD 
per 1,000 Medicaid Enrollees with OUD from 2010 to 2018 
*************************************************************************************************************/
use "annual_drug.dta", clear
drop if inlist(year, 2008, 2009, 2019)
keep if drugtype == 0

collapse (sum) medicaid_A, by(year expansion)
reshape wide medicaid_A, i(year) j(expansion) 
format %12.0g medicaid*

forvalues expansion = 0/4 {
	replace medicaid_A`expansion' = medicaid_A`expansion' / 1000000
	
	label variable medicaid_A`expansion' "`expansion' Medicaid enrollees (millions)"
}

export excel using "${output}\Brief Figures_${yearquarter}${v}.xlsx", sheet("Table 2", modify) firstrow(varlabels) 


/*************************************************************************************************************
TABLE 3
Medicaid Spending, Number of Prescriptions, Spending per Prescription, and Estimated Net Medicaid Spending per 
Prescription after Federal Rebates for Buprenorphine, Naltrexone, and Naloxone, 2010-2018
*************************************************************************************************************/
use allSDUD_rebate, clear
 
drop if inlist(year, 2008, 2009, 2019)  

*Make sure no obs are missing drugtype and keep only naloxone
tab drugtype, m

*Don't count rx that are from capitated payments, aka spending = 0 and rx > 0
gen imprx_nonzerospending = imprx
replace imprx_nonzerospending = 0 if unadjmedamt == 0 & imprx > 0

collapse (first) Generic (sum) imprx imprx_nonzerospending unadjmedamt adjmedamt, by(ndc_s9 drugtype year)


*Calculate the price per rx by drug 
gen adjprice_rx = adjmedamt / imprx_nonzerospending
gen unadjprice_rx = unadjmedamt / imprx_nonzerospending

*Drop when price per rx is missing (from 0 spending), because this will result in the highet prices showing up as missing
drop if adjprice_rx == .

*Browse most common NDC-9 for each drug in 2019
browse year ndc_s9 unadjmedamt imprx_nonzerospending unadjprice_rx adjprice_rx if inlist(ndc_s9, "124961208", "657570300", "695470353")
format %12.0g unadjmedamt
sort year


*Collapse to drug type 
collapse (sum) imprx imprx_nonzerospending unadjmedamt adjmedamt, by(drugtype year)

*Calculate the price per rx by drug
gen adjprice_rx = adjmedamt / imprx_nonzerospending
gen unadjprice_rx = unadjmedamt / imprx_nonzerospending
browse year drugtype unadjmedamt imprx_nonzerospending unadjprice_rx adjprice_rx 
format %12.0g unadjmedamt
sort year
/*************************************************************************************************************
TABLE 4
Growth in Annual Prescriptions and Rebate-Adjusted Spending on Buprenorphine, Naltrexone, and Naloxone 
Prescriptions, 2010-2018
*************************************************************************************************************/

use allSDUD_rebate, clear

drop if year == 2019

collapse (sum) imprx adjmedamt, by(drugtype year)
reshape wide imprx adjmedamt, i(year) j(drugtype) string

format %12.0g imprx* adjmedamt*

Unsuppressed Medicaid State Drug Utilization Data (SDUD), 1991
This dataset contains unsuppressed Medicaid spending and prescription data for 1991 by state, quarter, and National Drug Code. More information about the Medicaid SDUD data, use this link: https://www.medicaid.gov/medicaid/prescription-drugs/state-drug-utilization-data/state-drug-utilization-data-faq/index.html
