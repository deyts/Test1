select  /*+ index(aipa ap_invoices_n30,xs xx_sup_n1) */  xs.vendor_name vendor_number, aipa.attribute1 ,-- global_attribute13 , 
sum(DECODE(aipa.pay_group_lookup_code,'MPS VENDOR',nvl((aipa.invoice_amount - aipa.amount_paid ),0),0)) total_MPS_VENDOR,
sum(DECODE(aipa.pay_group_lookup_code,'PART D VENDOR',nvl((aipa.invoice_amount - aipa.amount_paid ),0),0)) total_PART_D_VENDOR,
sum(DECODE(aipa.pay_group_lookup_code,'MCCVA VENDOR',nvl((aipa.invoice_amount - aipa.amount_paid ),0),0)) total_MCCVA_VENDOR,
(sum(DECODE(aipa.pay_group_lookup_code,'MPS VENDOR',nvl((aipa.invoice_amount - aipa.amount_paid ),0),0)) +
sum(DECODE(aipa.pay_group_lookup_code,'PART D VENDOR',nvl((aipa.invoice_amount - aipa.amount_paid ),0),0)) +
sum(DECODE(aipa.pay_group_lookup_code,'MCCVA VENDOR',nvl((aipa.invoice_amount - aipa.amount_paid ),0),0))) TOTAL_UNPAID_AMOUNT
 from ap.ap_invoices_all aipa, xx_sup xs, ap.ap_suppliers aps
where aipa.vendor_id = aps.vendor_id
AND aps.segment1 =  xs.vendor_name
and aipa.payment_status_flag IN ('N','P')
and aipa.attribute1 = xs.vendor_site 
group by xs.vendor_name , aipa.attribute1 --, global_attribute13;
having 
(sum(DECODE(aipa.pay_group_lookup_code,'MPS VENDOR',nvl((aipa.invoice_amount - aipa.amount_paid ),0),0)) != 0 OR
sum(DECODE(aipa.pay_group_lookup_code,'PART D VENDOR',nvl((aipa.invoice_amount - aipa.amount_paid ),0),0)) != 0 OR
sum(DECODE(aipa.pay_group_lookup_code,'MCCVA VENDOR',nvl((aipa.invoice_amount - aipa.amount_paid ),0),0)) != 0 )
order by 1,2



--2) Query for Partially Paid Invoices
select  /*+ index(aipa ap_invoices_n30,xs xx_sup_n1) */  xs.vendor_name vendor_number, aipa.attribute1 ,-- global_attribute13 , 
sum(DECODE(aipa.pay_group_lookup_code,'MPS VENDOR',nvl((aipa.invoice_amount - aipa.amount_paid ),0),0)) total_MPS_VENDOR,
sum(DECODE(aipa.pay_group_lookup_code,'PART D VENDOR',nvl((aipa.invoice_amount - aipa.amount_paid ),0),0)) total_PART_D_VENDOR,
sum(DECODE(aipa.pay_group_lookup_code,'MCCVA VENDOR',nvl((aipa.invoice_amount - aipa.amount_paid ),0),0)) total_MCCVA_VENDOR,
(sum(DECODE(aipa.pay_group_lookup_code,'MPS VENDOR',nvl((aipa.invoice_amount - aipa.amount_paid ),0),0)) +
sum(DECODE(aipa.pay_group_lookup_code,'PART D VENDOR',nvl((aipa.invoice_amount - aipa.amount_paid ),0),0)) +
sum(DECODE(aipa.pay_group_lookup_code,'MCCVA VENDOR',nvl((aipa.invoice_amount - aipa.amount_paid ),0),0))) TOTAL_UNPAID_AMOUNT
 from ap.ap_invoices_all aipa, xx_sup xs, ap.ap_suppliers aps
where aipa.vendor_id = aps.vendor_id
AND aps.segment1 =  xs.vendor_name
and aipa.payment_status_flag = 'P'
and aipa.attribute1 = xs.vendor_site
group by xs.vendor_name , aipa.attribute1 --, global_attribute13;
having 
(sum(DECODE(aipa.pay_group_lookup_code,'MPS VENDOR',nvl((aipa.invoice_amount - aipa.amount_paid ),0),0)) != 0 OR
sum(DECODE(aipa.pay_group_lookup_code,'PART D VENDOR',nvl((aipa.invoice_amount - aipa.amount_paid ),0),0)) != 0 OR
sum(DECODE(aipa.pay_group_lookup_code,'MCCVA VENDOR',nvl((aipa.invoice_amount - aipa.amount_paid ),0),0)) != 0 )
order by 1,2


--Remittance Report

select distinct subscriber_id from mpstds.tds_ap_invoice_remittance
where error_msg like '%ERROR - Member Update ERROR - (Please check Supplier, SubscriberId,%'
and PROCESSED_FLAG = 0
and vendor_site_code is null 
and vendor_id is null

UNION             

select distinct alternate_id from mpstds.tds_ap_invoice_remittance                                    
where error_msg like     '%ERROR - Member Update ERROR - (Please check Supplier, AlternateId, Supplier Inactive Date OR Pay site) -- NDF Could not update claims for AlternateId%'
and PROCESSED_FLAG = 0
and vendor_site_code is null 
and vendor_id is null
                                           


select CLIENT_ID	,INVOICE_DATE,RX_NUMBER,SERVICE_DATE,HS_ID,SUBSCRIBER_ID,PATIENT_LAST_NAME,PATIENT_FIRST_NAME from mpstds.tds_ap_invoice_remittance a
	 where error_msg like 'ERROR - Invalid Invoice Amount%' order by a.invoice_date desc
	 
                     select distinct user_batch_id,period_start_date,period_end_date
from mpstds.tds_ar_invoices
where client_id = 'ABCPP' --'CDB'
order by 1 desc -- 5936

and period_start_date = :p_start_date –- ex: ’01-APR-2018’
and period_end_date   = :p_end_date; 

	 
	 
	  select aps.vendor_name , assa.vendor_site_code ,assa.pay_site_flag ,assa.inactive_date
    from apps.ap_supplier_sites_all assa , apps.ap_suppliers aps
 where  aps.vendor_id = assa.vendor_id
 and assa.vendor_site_code in (
select distinct nabp from apps.tds_ap_invoice_remittance
where error_msg like 'ERROR - Vendor Update ERROR - (Please check Supplier, NABP, Pharmacy Code, Supplier%' and SOURCE_DATA<> 'ADAP'
)
order by 3

tds_claim_adjust_pkg

			SELECT as1.vendor_id , as1.vendor_name , vendor_site_code , assa.inactive_date
                                            FROM apps.ap_supplier_sites_all assa, apps.ap_suppliers as1
                                           WHERE     assa.vendor_Id = as1.vendor_id
                                           and vendor_site_code IN (	
			select distinct nabp from mpstds.tds_ap_invoice_remittance
where error_msg like '%single-row subquery returns more than one row%' --'%ERROR - Vendor Update ERROR -- Could not update claims for NABP%'
and PROCESSED_FLAG = 0
and vendor_site_code is null and vendor_id is null
)
and NVL(assa.inactive_date,SYSDATE+1) > sysdate
order by 3

TDS_CHK_OUTBOUND_FILE_GEN_PKG.CHK_MAIN

select  * from mpstds.tds_ap_invoice_remittance
where error_msg like '%single-row subquery returns more than one row%'
and PROCESSED_FLAG = 0
and vendor_site_code is null 
and vendor_id is null

select client_admin_fee from mpstds.tds_ar_billing
where hs_id In (select  i.orig_hs_id_adjustment
FROM mpstds.tds_ar_billing i
where user_batch_id = 5885 and client_id = 'MRTP' -- 368723.92
and billing_invoice_num in (   'MRTP-10779',    'MRTP-10780')
and client_admin_fee = 0
and MASS_ADJ_INDICATOR = 'Y')
and client_id = 'MRTP'

select *  from mpstds.tds_ap_invoice_remittance   where mass_adj_indicator = 'Y'


tds_reports_pkg

SELECT SUBSTR (SYS_CONNECT_BY_PATH (meaning, ','), 2) csv
           -- INTO v_Recipient
            FROM (SELECT meaning,
                        ROW_NUMBER () OVER (ORDER BY meaning) rn,
                        COUNT (*) OVER () cnt
                  FROM apps.fnd_lookup_values
                  WHERE     lookup_type = 'MPS_BILLING_EMAIL_GROUP'
                  AND enabled_flag = 'Y')
            WHERE rn = cnt
            START WITH rn = 1
            CONNECT BY rn = PRIOR rn + 1


select RX_NUMBER , HS_ID, TRANSACTION_CODE, o_ingred_cost_paid , i.o_contract_fee_paid , i.o_sales_tax_paid , amt_deducted, (o_ingred_cost_paid + i.o_contract_fee_paid + i.o_sales_tax_paid - amt_deducted) in_ard , 
CLIENT_ADMIN_FEE_APPLIED , client_admin_fee ,client_billed_amt, new_client_billed_amt ,
 i.MASS_ADJ_INDICATOR, i.orig_hs_id_adjustment
FROM mpstds.tds_ar_billing i
where user_batch_id = 5885 and client_id = 'MRTP' -- 368723.92
and billing_invoice_num in (   'MRTP-10779',    'MRTP-10780')
and MASS_ADJ_INDICATOR = 'Y'
order by ORIG_HS_ID_ADJUSTMENT , i.TRANSACTION_CODE


--GPA16
select RX_NUMBER , HS_ID, TRANSACTION_CODE, o_ingred_cost_paid , i.o_contract_fee_paid , i.o_sales_tax_paid , amt_deducted, (o_ingred_cost_paid + i.o_contract_fee_paid + i.o_sales_tax_paid - amt_deducted) in_ard , 
CLIENT_ADMIN_FEE_APPLIED , client_admin_fee ,client_billed_amt, new_client_billed_amt ,
 i.MASS_ADJ_INDICATOR, i.orig_hs_id_adjustment
FROM mpstds.tds_ar_billing i
where user_batch_id = 5885 --and client_id = 'MRTP' -- 368723.92
and client_id = 'GPA16' --billing_invoice_num in (   'MRTP-10779',    'MRTP-10780')
--and MASS_ADJ_INDICATOR = 'Y'
AND new_client_billed_amt <> (o_ingred_cost_paid + i.o_contract_fee_paid + i.o_sales_tax_paid - amt_deducted)
order by ORIG_HS_ID_ADJUSTMENT , i.TRANSACTION_CODE


select sum(o_ingred_cost_paid + i.o_contract_fee_paid + i.o_sales_tax_paid - amt_deducted) in_ard , 
sum(new_client_billed_amt) , sum(CLIENT_ADMIN_FEE_APPLIED) , sum(client_admin_fee) , sum(client_billed_amt)
 --i.MASS_ADJ_INDICATOR, i.orig_hs_id_adjustment
FROM mpstds.tds_ar_billing i
where user_batch_id = 5885 --and client_id = 'MRTP' -- 368723.92
and client_id = 'GPA16' --billing_invoice_num in (   'MRTP-10779',    'MRTP-10780')
--and MASS_ADJ_INDICATOR = 'Y'


--MBA15

select  sum(new_client_billed_amt) , sum(client_billed_amt) ,tab.billing_invoice_num FROM  mpstds.tds_ar_billing tab
where 
tab.user_batch_id = 5885 
and tab.client_id = 'MAB15' 
group by tab.billing_invoice_num
order by tab.billing_invoice_num


select  sum(new_client_billed_amt)  ,tab.billing_invoice_num FROM  mpstds.tds_ar_billing tab
where 
tab.user_batch_id = 5885 
and tab.client_id = 'MAB15' 
and tab.billing_invoice_num = 'MAB15-1373'
group by tab.billing_invoice_num
order by tab.billing_invoice_num

select total_billed FROM mpstds.tds_ar_invoices i 
where i.user_batch_id = 5885 --and client_id = 'MRTP' -- 368723.92
and i.client_id = 'MAB15' 
and billing_invoice_num ='MAB15-1373'
--group by i.billing_invoice_num
--order by 2

--Specific invoices

select *FROM mpstds.tds_ar_invoices i 
where i.user_batch_id = 5885 --and client_id = 'MRTP' -- 368723.92
and i.client_id = 'MAB15' 
and i.billing_invoice_num = 'MAB15-1373' -- 721.92

select NEW_CLIENT_BILLED_AMT , i.* FROM mpstds.tds_ar_billing i 
where i.user_batch_id = 5885 --and client_id = 'MRTP' -- 368723.92
and i.client_id = 'MAB15' 
and i.billing_invoice_num = 'MAB15-1373'
--and i.error_msg is not null
--and NEW_CLIENT_BILLED_AMT = 2.73

select RX_NUMBER , HS_ID, TRANSACTION_CODE, o_ingred_cost_paid , i.o_contract_fee_paid , i.o_sales_tax_paid , amt_deducted, (o_ingred_cost_paid + i.o_contract_fee_paid + i.o_sales_tax_paid - amt_deducted) in_ard , 
CLIENT_ADMIN_FEE_APPLIED , client_admin_fee ,client_billed_amt, new_client_billed_amt ,
 i.MASS_ADJ_INDICATOR, i.orig_hs_id_adjustment  , i.client_ingredient_cost , client_dispensing_fee , O_SALES_TAX_PAID , AMT_DEDUCTED FROM mpstds.tds_ar_billing i
where 1 =1 
/*and ORIG_HS_ID_ADJUSTMENT IN (
'-100000259531484',
'-100000265182953',
'-100000264018917',
'-100000266003737',
'-100000265934645'
)*/
--and mass_adj_indicator = 'Y'
and i.client_id = 'MAB15' 
and i.billing_invoice_num = 'MAB15-1373'
and client_billed_amt <> new_client_billed_amt
--and client_admin_fee <> 0
order by i.ORIG_HS_ID_ADJUSTMENT , i.transaction_code desc

--New q

select adj_group_id , sum(i.client_ingredient_cost) , sum(client_dispensing_fee) , sum(O_SALES_TAX_PAID) , sum(AMT_DEDUCTED) , sum(CLIENT_ADMIN_FEE_APPLIED),
sum (i.client_ingredient_cost) + sum(client_dispensing_fee + O_SALES_TAX_PAID  - AMT_DEDUCTED+ CLIENT_ADMIN_FEE_APPLIED)  , sum (client_billed_amt) , sum (new_client_billed_amt) 
 FROM mpstds.tds_ar_billing i
where 1 =1 
--and mass_adj_indicator = 'Y'
and i.client_id = 'MAB15' 
and i.billing_invoice_num = 'MAB15-1373'
group by adj_group_id
--and client_billed_amt <> new_client_billed_amt
--and client_admin_fee <> 0
--order by i.ORIG_HS_ID_ADJUSTMENT , i.transaction_code desc


select SUM ( CASE WHEN tab.no_cost_flag = 'Y' THEN NVL (tab.client_admin_fee_applied, 0) -- Added for Rev 3.0
                                ELSE NVL (tab.new_client_billed_amt, 0)
                            END) aa  , SUM(NVL (tab.new_client_billed_amt, 0) ) FROM mpstds.tds_ar_billing tab
where user_batch_id = 5885 --and client_id = 'MRTP' -- 368723.92
and client_id = 'MAB15' -- 66673.69
and billing_invoice_num = 'MAB15-1373'

UPDATE mpstds.tds_ar_invoices
SET R_INGREDIENT_COST = R_INGREDIENT_COST + 2.73,
R_SUB_TOTAL = R_SUB_TOTAL + 2.73,
total_billed = total_billed + 2.73
where user_batch_id = 5885 --and client_id = 'MRTP' -- 368723.92
and client_id = 'MAB15' --66670.96
and billing_invoice_num = 'MAB15-1373' --1 row to be updated
/
update mpstds.tds_ar_billing i
set client_ingredient_cost = client_ingredient_cost + 2.73
where 1 =1 
and i.client_id = 'MAB15' 
and i.billing_invoice_num = 'MAB15-1373'
and hs_id = '-100000275949011'  --1 row to be updated
/

select (M_INGREDIENT_COST + R_INGREDIENT_COST + O_INGREDIENT_COST) INGREDIENT_COST,
(M_DISPENSING_FEE + R_DISPENSING_FEE + O_DISPENSING_FEE) DISPENSING_FEE,
(M_TAX + R_TAX + O_TAX) TAX,
(M_COPAY + R_COPAY + O_COPAY) COPAY,
(M_ADMIN_FEE + R_ADMIN_FEE + O_ADMIN_FEE) ADMIN_FEE,
(M_SUB_TOTAL + R_SUB_TOTAL + O_SUB_TOTAL) SUB_TOTAL
 FROM mpstds.tds_ar_invoices i
where user_batch_id = 5885 --and client_id = 'MRTP' -- 368723.92
and client_id = 'MAB15' --66670.96
and billing_invoice_num = 'MAB15-1373'

select * from  mpstds.tds_ar_invoices i
where user_batch_id = 5885 --and client_id = 'MRTP' -- 368723.92
and client_id = 'MAB15' --66670.96
and billing_invoice_num = 'MAB15-1373'

--GPA16

select distinct period_start_date,period_end_date,user_batch_id
from mpstds.tds_ar_invoices
where client_id = 'GPA16'
order by 3 desc -- 5021

select SUM ( CASE WHEN tab.no_cost_flag = 'Y' THEN NVL (tab.client_admin_fee_applied, 0) -- Added for Rev 3.0
                                ELSE NVL (tab.new_client_billed_amt, 0)
                            END) aa  , SUM(NVL (tab.new_client_billed_amt, 0) ) FROM mpstds.tds_ar_billing tab
where user_batch_id = 5885 --and client_id = 'MRTP' -- 368723.92
and client_id = 'GPA16' -- 21129.09


select sum(TOTAL_BILLED) FROM mpstds.tds_ar_invoices i
where user_batch_id = 5885 --and client_id = 'MRTP' -- 368723.92
and client_id = 'GPA16' -- 21129.09

select sum(NEW_CLIENT_BILLED_AMT) FROM mpstds.tds_ar_billing i
where user_batch_id = 5885 --and client_id = 'MRTP' -- 368723.92
and client_id = 'GPA16' --billing_invoice_num in (   'MRTP-10779',    'MRTP-10780')
--and NEW_CLIENT_BILLED_AMT = 18.65
--and MASS_ADJ_INDICATOR = 'Y'
--AND new_client_billed_amt <> (o_ingred_cost_paid + i.o_contract_fee_paid + i.o_sales_tax_paid - amt_deducted)


select RX_NUMBER , HS_ID, TRANSACTION_CODE, o_ingred_cost_paid , i.o_contract_fee_paid , i.o_sales_tax_paid , amt_deducted, (o_ingred_cost_paid + i.o_contract_fee_paid + i.o_sales_tax_paid - amt_deducted) in_ard , 
CLIENT_ADMIN_FEE_APPLIED , client_admin_fee ,client_billed_amt, new_client_billed_amt ,
 i.MASS_ADJ_INDICATOR, i.orig_hs_id_adjustment
FROM mpstds.tds_ar_billing i
where user_batch_id = 5885 and client_id = 'MAB15' -- 368723.92
--and billing_invoice_num in (   'MRTP-10779',    'MRTP-10780')
and MASS_ADJ_INDICATOR = 'Y'
and client_admin_fee = 0
order by ORIG_HS_ID_ADJUSTMENT , i.TRANSACTION_CODE

select * from apps.ap_supplier_sites_all where vendor_site_code = '1275523912'

select  aia.global_attribute2 hs_id, tab.rx_number , aia.invoice_num , aia.invoice_date , 
  aia.invoice_amount,  aia.attribute1 NPI , aipa.amount payment_amount, aia.PAYMENT_STATUS_FLAG , 
 aca.check_date , aca.check_number 
 from apps.ap_invoices_all aia  , apps.ap_invoice_payments_all aipa , apps.ap_checks_all aca , mpstds.tds_ar_billing tab
 where aia.vendor_site_id = 1023 --in ( 2090265 , 2090264)
 and aia.invoice_id = aipa.invoice_id
 and aipa.check_id = aca.check_id
 and aia.global_attribute2 = tab.hs_id
 and aia.attribute1 = '1275523912'
 and trunc(check_date) between '01-JAN-2021' and '30-APR-2021'
 order by check_date,  aca.check_number
