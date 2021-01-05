CREATE OR REPLACE PACKAGE BODY APPS.tds_ar_billing_interface_pkg IS

/* -------------------------------------------------------------------------------------------------------------------------------
 * Program Name : Billing Process
 * Author Name  : Animesh Kumar
 * Written Date : 01-JAN-2012
 *
 *
 * Modification History :
 * -----------  -------------    ----   ------------------------------------------------------------------------------------------
 * DATE         WHO              REV    DESCRIPTION
 * -----------  -------------    ----   ------------------------------------------------------------------------------------------
 * 01-JAN-2012  Animesh Kumar    1.0    Initial Version Creation
 * 26-FEB-2013  Animesh Kumar    1.1    Added changes for COB
 * 04-APR-2013  Animesh Kumar    1.6    Added changes to accomodate compound cost
 * 26-AUG-2013  Komal Kumar K    1.7    Added changes to footer logic to take billed values instead of remittance values
 * 02-SEP-2014  Animesh Kumar    1.8    Added Source param to billing_claims_update proc
 * 17-FEB-2015  Naveen Chendil   1.9    Added updates to tracking group id for 000215,ROADWM and 000426 to
 *                                      PROCEDURE billing_claims_update
 * 25-FEB-2015  Naveen Chendil   2.0    Added update to tracking group id for 000253 to PROCEDURE billing_claims_update
 * 02-MAR-2015  Naveen Chendil   2.1    Added update to tracking group id for 000238 to PROCEDURE billing_claims_update
 * 19-MAR-2015  Naveen Chendil   2.2    Added update to tracking group id for 000429 to PROCEDURE billing_claims_update
 * 24-MAR-2015  Naveen Chendil   2.3    Added update to tracking group id for 000262 to PROCEDURE billing_claims_update
 * 27-MAR-2015  Sarvesh N        2.4    Commented the update statements as the same tracking group is now allowed across clients
 * 30-MAR-2015  Naveen Chendil   2.5    Updated the co-pay calculation to pick up the client side other payer amount
 * 12-MAY-2015  Sarvesh N        2.6    Changes to fix Divisor is Zero Error in Spread hold logic
 * 17-SEP-2015  Naveen Chendil   2.7    Included changes to update No Cost Flag for No Cost Pharmacies
 * 07-OCT-2015  Sarvesh N        2.8    Changes for Audit Recoupment
 * 29-DEC-2015  Naveen Chendil   2.9    Changes to excluded member claims from updating No Cost Flag
 * 06-JAN-2016  Naveen Chendil   3.0    Changes to admin fee processing for Coupon Claims
 * 14-JAN-2016  Naveen Chendil   3.1    Changes to include prof_service_fee along with contract fee
 * 25-APR-2016  Naveen Chendil   3.3    Updated to remove BidRx claims from High Margin Hold validation
 * 07-JUL-2016  Prasad Chalavadi 3.4    Modified to add query criteria source_data, so it can pull/update unique invoice by source value
 * 01-JAN-2017  Rajesh Patel     3.5    Changes to find parent claim for audit claim
 * 02-MAY-2017  Prasad Chalavadi 3.6    Modified Billing_claims_Update procedure to include processor_fee as per cash network changes
 * 24-JAN-2018  Mallik Kencha    3.7    Modified package to include new custom table lookup type
 * 24-AUG-2020  Tuhin Dey        3.8    MRXFINANCE-1620: Audit Recovery - Modify the TDS AR Billing Claims Update the status = "AUDIT-ANC-PENDING" for PRX Clients to send to Scottsdale team
 * ------------------------------------------------------------------------------------------------------------------------------
 */

-- ==========================================================================
-- ==========================================================================
-- Billing Claims Update
-- ==========================================================================
-- ==========================================================================

PROCEDURE billing_claims_update
(
    p_errbuff  OUT VARCHAR2,
    p_retcode  OUT NUMBER,
    p_org_id   IN  NUMBER,
    p_source   IN  VARCHAR2    -- Rev 1.8
)

 IS

CURSOR c1 IS
    SELECT rowid, rx_number, hs_id, hs_item_no, client_icn, transaction_code, client_id,
           adj_group_id, billing_invoice_id, patient_alias_id, submitted_cardholder_id, submitted_person_cd,
           subscriber_last_name, subscriber_first_name, member_middle_initial, relationship_cd, member_dob,
           gender, drug_code, pharmacy_code, daw_cd, brand_class_cd, mail_order_ind, bill_basis,
           client_ingredient_cost, client_dispensing_fee, client_admin_fee, client_billed_amt,
           link_hs_id, link_hs_item_no, org_id,o_ingred_cost_paid, o_contract_fee_paid, o_sales_tax_paid,
           amt_deducted, claim_adjust_amt, invoice_amount, tracking_group_id, other_coverage_code, amt_deducted_orig,
           other_payment_qualifier, other_amount_paid, o_ingred_cost_paid_orig, client_ingredient_cost_orig, -- added for compound change, 04-APR-2013
           client_other_payer_amount, -- Added for Rev 2.5
           nabp -- Added for Rev 2.7
          ,source_data -- Added for v2.8
          ,if_claim_type_code -- Added for v2.9
          ,prof_service_fee -- Added for v3.1
          ,billing_status  -- Added for 3.5
		  ,mass_adj_indicator --Added for Rev 3.8
          ,NVL(processor_fee,0) processor_fee -- added for 3.6
      FROM mpstds.tds_ar_billing
     WHERE org_id = p_org_id
       AND billing_status IS NULL
       AND source_data = p_source;

    --Added below cursor for v2.8
--Pick only those Claims that are on billing audit hold, and which have a billing schedule date as of sysdate
--What this basically does is, it will pick only those claims on hold that have a billing schedule for that day
CURSOR cur_audit IS
    SELECT tabb.rowid, tabb.rx_number, tabb.hs_id, tabb.hs_item_no,tabb.client_id, tabb.source_data ,DECODE(ffv.flex_value, NULL,'Y','N') prx_client ,  ffv.value_category , ffv.tds_billing_flag, ffv.send_ancillary_flag , ffv.bill_ancillary_flag , ffv.business_extract_flag
      FROM mpstds.tds_ar_billing tabb,
           mpstds.tds_ar_billing_sch_lines tabsl,
           mpstds.tds_ar_cust_header tach,
		   (SELECT ffv.flex_value , ffv.value_category , ffv.attribute1 tds_billing_flag, ffv.attribute2 send_ancillary_flag , ffv.attribute3 bill_ancillary_flag , ffv.attribute4 business_extract_flag
		   from apps.fnd_flex_value_sets ffvs, apps.fnd_flex_values ffv
			where ffvs.FLEX_VALUE_SET_NAME = 'TDS_NON_PRX_CLIENTS'
			and ffvs.flex_value_set_id = ffv.flex_value_set_id
			and ffv.enabled_flag = 'Y'
			and trunc(sysdate) between trunc(nvl(ffv.start_date_active,sysdate-1)) AND trunc(nvl(ffv.end_date_active,sysdate+1))) ffv
     WHERE tabb.org_id = p_org_id
       AND tabb.billing_status = 'HOLD'
       AND tabb.hold_reason_code = 'A'
       --AND tabb.source_data = p_source
       AND TRUNC(tabsl.billing_schedule_date) = TRUNC(SYSDATE)
       AND tabsl.billing_status <> 'Y' -- Updated for Rev 3.2
       AND TRUNC(tabb.adjud_date) < TRUNC(SYSDATE) -- Fetch the claims
       AND tach.customer_id =  tabsl.customer_id
       --AND NVL(tach.auto_billing_flag,'N') ='Y' -- AUTO BILLING FLAG
       AND tach.customer_status = 'A' -- Updated for Rev 3.2
       AND tach.org_id = p_org_id
       AND tach.client_id = tabb.client_id
	   AND tabb.client_id = ffv.flex_value(+) 
       AND tabb.org_id = tach.org_id;
--Added above for v2.8

    l_total_count               PLS_INTEGER :=0;
    l_pass_cnt                  PLS_INTEGER :=0;
    l_failed_cnt                PLS_INTEGER :=0;
    l_invalid_invoice_amt_cnt   PLS_INTEGER :=0;

    --------------------------------
    l_claim_exists             PLS_INTEGER;
    l_error_msg                mpstds.tds_ar_billing.error_msg%TYPE;
    l_copay                    mpstds.tds_ar_billing.amt_deducted%TYPE;
    l_billing_status           mpstds.tds_ar_billing.billing_status%TYPE := NULL;
    l_cust_id                  mpstds.tds_ar_cust_header.customer_id%TYPE;
    l_client_id                mpstds.tds_ar_cust_header.client_id%TYPE;
    l_billing_level            mpstds.tds_ar_cust_header.billing_level%TYPE;
    l_cust_site_id             mpstds.tds_ar_cust_site.customer_site_id%TYPE;
    l_admin_fee                mpstds.tds_ar_billing.client_admin_fee%TYPE;
    l_admin_fee_applied        mpstds.tds_ar_billing.client_admin_fee_applied%TYPE;
    l_spread_contract          mpstds.tds_ar_cust_header.spread_contract%TYPE;
    l_parent_washed_status     mpstds.tds_ar_billing.washed_status%TYPE;
    l_parent_billing_status    mpstds.tds_ar_billing.billing_status%TYPE;
    --l_admin_fee                mpstds.tds_ar_billing.client_admin_fee%TYPE;
    l_new_client_billed_amt    mpstds.tds_ar_billing.client_billed_amt%TYPE;
    l_washed_status            mpstds.tds_ar_billing.washed_status%TYPE;
    l_high_dollar_threshold    mpstds.tds_ar_cust_header.high_dollar_threshold%TYPE;
    l_high_margin_threshold    mpstds.tds_ar_cust_header.high_margin_threshold%TYPE;
    l_cust_site_num            mpstds.tds_ar_cust_site.customer_site_num%TYPE;
    l_hold_reason_code         mpstds.tds_ar_billing.hold_reason_code%TYPE;
    l_hold_reason              mpstds.tds_ar_billing.hold_reason%TYPE;
    l_hold_desc                mpstds.tds_ar_billing.hold_desc%TYPE;
    l_o_ingred_cost_paid       mpstds.tds_ap_invoice_remittance.o_ingred_cost_paid%TYPE;
    l_client_ingredient_cost   mpstds.tds_ar_billing.client_ingredient_cost%TYPE;
    l_no_cost_flag             mpstds.tds_ar_billing.no_cost_flag%TYPE; -- Added for Rev 2.7
    l_last_updated_by          NUMBER:= TO_NUMBER(fnd_global.user_id);
    l_created_by               NUMBER:= TO_NUMBER(fnd_global.user_id);
    l_last_update_login        NUMBER:= TO_NUMBER(fnd_global.login_id);
    l_high_dollar_exist        PLS_INTEGER;
    l_spread_per               NUMBER;
    l_washed_date              DATE;
    l_warn                     PLS_INTEGER :=0;
    l_hold_warn                PLS_INTEGER :=0;
    l_prog_warn                PLS_INTEGER;
    l_org_id                   PLS_INTEGER;
    l_cust_site_cnt            PLS_INTEGER;
    l_dollar_hold_cnt          PLS_INTEGER;
    l_margin_hold_cnt          PLS_INTEGER;
    l_combo_hold_cnt           PLS_INTEGER;
    l_cust_site_inactive_cnt   PLS_INTEGER;
    l_combo_hold_ind           PLS_INTEGER;
    cust_setup_err             EXCEPTION;
    prim_site_setup_err        EXCEPTION;
    site_setup_err             EXCEPTION;
    site_inactive_err          EXCEPTION;

    l_pay_flag                 ap_invoices.payment_status_flag%type; --v2.8
    l_audit_hold_cnt           PLS_INTEGER; --v2.8
    l_audit_rem_cnt            PLS_INTEGER; --v2.8
	l_audit_anc_sent_cnt       PLS_INTEGER; --v3.8
	l_business_extract_cnt     PLS_INTEGER; --v3.8
    l_creation_date            DATE; -- Added for v3.0
	l_req_id                   NUMBER;
    --------------------------------


BEGIN

    /*
    ----temp update for C2C Group Move
    update tds_ar_billing set TRACKING_GROUP_ID = '0005021A' where TRACKING_GROUP_ID = '0005021' and CLIENT_ID = 'EBM2';

    update tds_ar_billing set TRACKING_GROUP_ID = '003001A' where TRACKING_GROUP_ID = '003001' and CLIENT_ID = 'AMA';
    update tds_ar_billing set TRACKING_GROUP_ID = 'HHSA00A' where TRACKING_GROUP_ID = 'HHSA00' and CLIENT_ID = 'ANC2';
    update tds_ar_billing set TRACKING_GROUP_ID = 'HRIZ00A' where TRACKING_GROUP_ID = 'HRIZ00' and CLIENT_ID = 'ANC2';
    update tds_ar_billing set TRACKING_GROUP_ID = '000025A' where TRACKING_GROUP_ID = '000025' and CLIENT_ID = 'BCT2';
    update tds_ar_billing set TRACKING_GROUP_ID = '000208A' where TRACKING_GROUP_ID = '000208' and CLIENT_ID = 'BMS';
    update tds_ar_billing set TRACKING_GROUP_ID = '000249A' where TRACKING_GROUP_ID = '000249' and CLIENT_ID = 'BMS7';
    --update tds_ar_billing set TRACKING_GROUP_ID = 'EBM591A' where TRACKING_GROUP_ID = 'EBM591' and CLIENT_ID = 'EMC1';
    update tds_ar_billing set TRACKING_GROUP_ID = '075000A' where TRACKING_GROUP_ID = '075000' and CLIENT_ID = 'HDN';
    update tds_ar_billing set TRACKING_GROUP_ID = '000265A' where TRACKING_GROUP_ID = '000265' and CLIENT_ID = 'MCA';
    update tds_ar_billing set TRACKING_GROUP_ID = '000110A' where TRACKING_GROUP_ID = '000110' and CLIENT_ID = 'MSA';
    update tds_ar_billing set TRACKING_GROUP_ID = '000210A' where TRACKING_GROUP_ID = '000210' and CLIENT_ID = 'MSA';
    update tds_ar_billing set TRACKING_GROUP_ID = '000420B' where TRACKING_GROUP_ID = '000420' and CLIENT_ID = 'MSA';
    update tds_ar_billing set TRACKING_GROUP_ID = '000610A' where TRACKING_GROUP_ID = '000610' and CLIENT_ID = 'MSA';
    update tds_ar_billing set TRACKING_GROUP_ID = '002390A' where TRACKING_GROUP_ID = '002390' and CLIENT_ID = 'NAA1';
    update tds_ar_billing set TRACKING_GROUP_ID = '000235A' where TRACKING_GROUP_ID = '000235' and CLIENT_ID = 'NHP1';
    update tds_ar_billing set TRACKING_GROUP_ID = '002520A' where TRACKING_GROUP_ID = '002520' and CLIENT_ID = 'OBA2';
    update tds_ar_billing set TRACKING_GROUP_ID = '000500A' where TRACKING_GROUP_ID = '000500' and CLIENT_ID = 'PAD';
    update tds_ar_billing set TRACKING_GROUP_ID = '004500A' where TRACKING_GROUP_ID = '004500' and CLIENT_ID = 'PAD1';
    update tds_ar_billing set TRACKING_GROUP_ID = '000768A' where TRACKING_GROUP_ID = '000768' and CLIENT_ID = 'PAI2';
    update tds_ar_billing set TRACKING_GROUP_ID = '009000B' where TRACKING_GROUP_ID = '009000' and CLIENT_ID = 'PBI2';
    update tds_ar_billing set TRACKING_GROUP_ID = '009000A' where TRACKING_GROUP_ID = '009000' and CLIENT_ID = 'PBI4';
    update tds_ar_billing set TRACKING_GROUP_ID = '005202A' where TRACKING_GROUP_ID = '005202' and CLIENT_ID = 'SIG';
    update tds_ar_billing set TRACKING_GROUP_ID = '000409A' where TRACKING_GROUP_ID = '000409' and CLIENT_ID = 'STR';
    update tds_ar_billing set TRACKING_GROUP_ID = '001006A' where TRACKING_GROUP_ID = '001006' and CLIENT_ID = 'THP1';
    update tds_ar_billing set TRACKING_GROUP_ID = '764109A' where TRACKING_GROUP_ID = '764109' and CLIENT_ID = 'UMW2';
    update tds_ar_billing set TRACKING_GROUP_ID = '764113A' where TRACKING_GROUP_ID = '764113' and CLIENT_ID = 'UMW4';
    update tds_ar_billing set TRACKING_GROUP_ID = '000227A' where TRACKING_GROUP_ID = '000227' and CLIENT_ID = 'USC';
    update tds_ar_billing set TRACKING_GROUP_ID = '000250A' where TRACKING_GROUP_ID = '000250' and CLIENT_ID = 'USC';
    update tds_ar_billing set TRACKING_GROUP_ID = '000266A' where TRACKING_GROUP_ID = '000266' and CLIENT_ID = 'USC';
    update tds_ar_billing set TRACKING_GROUP_ID = '000269A' where TRACKING_GROUP_ID = '000269' and CLIENT_ID = 'USC';
    update tds_ar_billing set TRACKING_GROUP_ID = '000421A' where TRACKING_GROUP_ID = '000421' and CLIENT_ID = 'USC';
    update tds_ar_billing set TRACKING_GROUP_ID = '000425A' where TRACKING_GROUP_ID = '000425' and CLIENT_ID = 'USC';
    update tds_ar_billing set TRACKING_GROUP_ID = '000423A' where TRACKING_GROUP_ID = '000423' and CLIENT_ID = 'USC3';
    update tds_ar_billing set TRACKING_GROUP_ID = '000219A' where TRACKING_GROUP_ID = '000219' and CLIENT_ID = 'USC4';
    update tds_ar_billing set TRACKING_GROUP_ID = '000270A' where TRACKING_GROUP_ID = '000270' and CLIENT_ID = 'USC4';
    update tds_ar_billing set TRACKING_GROUP_ID = '000422A' where TRACKING_GROUP_ID = '000422' and CLIENT_ID = 'USC4';
    update tds_ar_billing set TRACKING_GROUP_ID = '000420A' where TRACKING_GROUP_ID = '000420' and CLIENT_ID = 'USC5';
    update tds_ar_billing set TRACKING_GROUP_ID = '2009JASA' where TRACKING_GROUP_ID = '2009JAS' and CLIENT_ID = 'WMH';

    update tds_ar_billing set TRACKING_GROUP_ID = '000401A' where TRACKING_GROUP_ID = '000401' and CLIENT_ID = 'FBA';
    update tds_ar_billing set TRACKING_GROUP_ID = '000423B' where TRACKING_GROUP_ID = '000423' and CLIENT_ID = 'FBA';
    update tds_ar_billing set TRACKING_GROUP_ID = '000266B' where TRACKING_GROUP_ID = '000266' and CLIENT_ID = 'UDC';
    update tds_ar_billing set TRACKING_GROUP_ID = '000420C' where TRACKING_GROUP_ID = '000420' and CLIENT_ID = 'UDC1';

    update tds_ar_billing set TRACKING_GROUP_ID = '010614A' where TRACKING_GROUP_ID = '010614' and CLIENT_ID = 'BRM1';
    update tds_ar_billing set TRACKING_GROUP_ID = '000400A' where TRACKING_GROUP_ID = '000400' and CLIENT_ID = 'PAD1';
    update tds_ar_billing set TRACKING_GROUP_ID = '000424A' where TRACKING_GROUP_ID = '000424' and CLIENT_ID = 'USC';
    update tds_ar_billing set TRACKING_GROUP_ID = '000428A' where TRACKING_GROUP_ID = '000428' and CLIENT_ID = 'USC';
    update tds_ar_billing set TRACKING_GROUP_ID = '000427A' where TRACKING_GROUP_ID = '000427' and CLIENT_ID = 'USC';
    update tds_ar_billing set TRACKING_GROUP_ID = 'JACK815A' where TRACKING_GROUP_ID = 'JACK815' and CLIENT_ID = 'HEZ2';
    update tds_ar_billing set TRACKING_GROUP_ID = 'MELV000A' where TRACKING_GROUP_ID = 'MELV000' and CLIENT_ID = 'ATS1';
    update tds_ar_billing set TRACKING_GROUP_ID = '000210B' where TRACKING_GROUP_ID = '000210' and CLIENT_ID = 'BNA';
    update tds_ar_billing set TRACKING_GROUP_ID = '000215A' where TRACKING_GROUP_ID = '000215' and CLIENT_ID = 'BNA';

    update tds_ar_billing set TRACKING_GROUP_ID = 'ROADWMA' where TRACKING_GROUP_ID = 'ROADWM' and CLIENT_ID = 'PEK2';
    update tds_ar_billing set TRACKING_GROUP_ID = '000426A' where TRACKING_GROUP_ID = '000426' and CLIENT_ID = 'USC';

    update tds_ar_billing set TRACKING_GROUP_ID = '000253A' where TRACKING_GROUP_ID = '000253' and CLIENT_ID = 'BNA';
    update tds_ar_billing set TRACKING_GROUP_ID = '000238A' where TRACKING_GROUP_ID = '000238' and CLIENT_ID = 'BNA';
    update tds_ar_billing set TRACKING_GROUP_ID = '000429A' where TRACKING_GROUP_ID = '000429' and CLIENT_ID = 'USC';
    update tds_ar_billing set TRACKING_GROUP_ID = '000262A' where TRACKING_GROUP_ID = '000262' and CLIENT_ID = 'BNA';*/

    l_total_count  := 0;
    l_pass_cnt     := 0;
    l_failed_cnt   := 0;
    l_invalid_invoice_amt_cnt := 0;
    l_warn       := 0;
    l_hold_warn  := 0;
    l_prog_warn  := 0;
    l_cust_id         := NULL;
    l_client_id       := NULL;
    l_billing_level   := NULL;
    l_admin_fee       := NULL;
    l_dollar_hold_cnt := 0;
    l_margin_hold_cnt := 0;
    l_combo_hold_cnt  := 0;

    l_audit_hold_cnt  := 0; --v2.8
    l_audit_rem_cnt   := 0; --v2.8

     IF p_org_id IS NULL then
       l_org_id := FND_PROFILE.VALUE('ORG_ID');
     ELSE
       l_org_id := p_org_id;
     END IF;

    --l_org_id := FND_PROFILE.VALUE('ORG_ID');
    --mo_global.set_policy_context('S', p_org_id);
    FND_FILE.PUT_LINE(FND_FILE.OUTPUT,'****************************** CLAIMS UPDATE RESULT *************************************************************************************************');

    ---- Set PROG status as SUCCESS initially
    p_errbuff   := c_errbuf_s;
    p_retcode   := c_retcode_s;

    FOR i IN C1
    LOOP
    BEGIN <<full1>>

        l_error_msg := NULL;
        l_admin_fee_applied := NULL;
        l_billing_status := NULL;
        l_high_dollar_exist := 0;
        l_spread_per := NULL;
        l_new_client_billed_amt := NULL;
        l_washed_date  := NULL;
        l_warn := 0;
        l_cust_id := NULL;
        l_client_id := NULL;
        l_billing_level := NULL;
        l_admin_fee := NULL;
        l_spread_contract := NULL;
        l_high_dollar_threshold := NULL;
        l_high_margin_threshold := NULL;
        l_total_count := l_total_count + 1;
        l_washed_status := NULL;
        l_parent_washed_status := NULL;
        l_cust_site_cnt := NULL;
        l_cust_site_inactive_cnt := NULL;
        l_cust_site_num := NULL;
        l_hold_reason_code := NULL;
        l_hold_reason := NULL;
        l_hold_desc := NULL;
        l_copay := 0;
        l_combo_hold_ind := 0;
        l_o_ingred_cost_paid := 0;
        l_client_ingredient_cost := 0;
        l_no_cost_flag := NULL; -- Added for Rev 2.7

        ---- Applying the logic for COB amount -- Added by Animesh 2/26/13
        ---- Co_Pay will include claim adjust amount as well


     -- FND_FILE.PUT_LINE(FND_FILE.OUTPUT,'Message 0001 - record selected to process for update RxNumber= '||TO_CHAR(i.rx_number) ||'. hs_id = :'||' '||TO_CHAR(i.hs_id)
                                                                                    --     ||', hs_item_no =  '||TO_CHAR(i.hs_item_no)|| ', billing_status =' || i.billing_status || ', link_hs_id = ' || i.link_hs_id);
        IF i.other_coverage_code = 2
        THEN
            --l_copay := i.amt_deducted_orig + i.claim_adjust_amt; -- Commented for Rev 2.5
            l_copay := i.amt_deducted_orig + NVL(i.client_other_payer_amount,i.claim_adjust_amt); -- Added for Rev 2.5
        ELSE
            l_copay := i.amt_deducted_orig;
        END IF;
        ---- end Added by Animesh 2/26/13

        ---- Applying the logic for Compound prep cost -- Added by Animesh for compound change, 04-APR-2013
        ---- New Invoice Amt will include other amount paid as well
        IF i.other_payment_qualifier = '09'
        THEN
            l_o_ingred_cost_paid := i.o_ingred_cost_paid_orig + i.other_amount_paid;
            l_client_ingredient_cost := i.client_ingredient_cost_orig + i.other_amount_paid;
        ELSE
            l_o_ingred_cost_paid := i.o_ingred_cost_paid_orig;
            l_client_ingredient_cost := i.client_ingredient_cost_orig;
        END IF;
        ---- end Added by Animesh 04-APR-2013

        ---- check if the customer exists
        BEGIN
            SELECT customer_id, client_id, billing_level, spread_contract, high_dollar_threshold, high_margin_threshold
              INTO l_cust_id, l_client_id, l_billing_level, l_spread_contract, l_high_dollar_threshold, l_high_margin_threshold
              FROM mpstds.tds_ar_cust_header
             WHERE client_id = i.client_id
               AND customer_status IN ( 'A', 'H') -- Active OR Hold
               AND org_id = l_org_id;

        EXCEPTION
            WHEN OTHERS THEN
            RAISE cust_setup_err;
        END;

        BEGIN
            -- Check if Customer is setup with proper Primary Site
            SELECT customer_site_id
              INTO l_cust_site_id
              FROM mpstds.tds_ar_cust_site
             WHERE customer_id = l_cust_id
               AND site_billing_level = 'C'
               AND org_id = l_org_id
               AND primary_site_flag = 'Y';

        EXCEPTION
            WHEN OTHERS THEN
            RAISE prim_site_setup_err;
        END;

        BEGIN
            -- Check if the customer is setup with proper Sites
            SELECT count(customer_site_id)
              INTO l_cust_site_cnt
              FROM mpstds.tds_ar_cust_site
             WHERE customer_id = l_cust_id
               AND site_billing_level = l_billing_level
               AND org_id = l_org_id;

            IF l_cust_site_cnt = 0 THEN
                RAISE site_setup_err;
            END IF;

        EXCEPTION
            WHEN OTHERS THEN
            RAISE site_setup_err;
        END;

        BEGIN

            SELECT DECODE(l_billing_level, 'C', i.client_id, 'A', i.adj_group_id, 'T', i.tracking_group_id, NULL) INTO l_cust_site_num FROM dual;

            -- Check if the customer is setup with proper Sites
            SELECT count(customer_site_id)
              INTO l_cust_site_inactive_cnt
              FROM mpstds.tds_ar_cust_site
             WHERE customer_id = l_cust_id
               AND site_billing_level = l_billing_level
               AND org_id = l_org_id
               --AND customer_site_num = l_cust_site_num -- commented out for the change for customer site num being null for billing level C
               AND decode(l_billing_level, 'C', 'XXXXX', customer_site_num) = decode(l_billing_level, 'C', 'XXXXX', l_cust_site_num)
               AND inactive_date > SYSDATE; -- Updated for Rev 3.2

            IF l_cust_site_inactive_cnt = 0 THEN
                RAISE site_inactive_err;
            END IF;

        EXCEPTION
            WHEN OTHERS THEN
            RAISE site_inactive_err;
        END;

        -- Added for Rev 2.7
        SELECT DECODE(COUNT (1), 0, NULL, 'Y')
          INTO l_no_cost_flag
          FROM (SELECT tag client_id, description nabp, 'O' if_claim_type_code -- Added for Rev 2.9
                 FROM fnd_lookup_values
                WHERE lookup_type = 'MPS_NO_COST_PHARMACIES'
                  AND SYSDATE BETWEEN start_date_active AND NVL (end_date_active, SYSDATE)
                  AND enabled_flag = 'Y')
        WHERE (    client_id = i.client_id
               AND nabp = i.nabp
               AND if_claim_type_code = i.if_claim_type_code -- Added for Rev 2.9
               );
        -- End of addition for Rev 2.7

        ---------------------------------------------------- 
		IF NVL(i.mass_adj_indicator,'N') = 'Y' THEN --Added for Rev 3.8
		 l_admin_fee_applied:=0;
		 FND_FILE.PUT_LINE(FND_FILE.OUTPUT, ' l_admin_fee_applied = 0 as i.mass_adj_indicator = Y ');
		ELSE
		FND_FILE.PUT_LINE(FND_FILE.OUTPUT, ' l_admin_fee_applied = i.client_admin_fee as i.mass_adj_indicator <> Y ');
        l_admin_fee_applied := i.client_admin_fee;
		END IF;
		
		
        l_new_client_billed_amt := i.client_billed_amt;
        -----------------------------------------------------

        ---- Check if the Claim amt is negative
        IF (i.client_ingredient_cost < 0) OR (i.client_billed_amt < 0) ---- If claim amt is negative then
        THEN
            ----Check if Parent Claim already exist
            -- start for Rev 3.5 changes
            if p_source = 'AUDIT' then  -- addded for audit calim to find parent claim without source v 3.5

            SELECT COUNT(1)
              INTO l_claim_exists
              FROM dual
             WHERE EXISTS (
                            SELECT 1 FROM mpstds.tds_ar_billing
                            WHERE hs_id          = i.link_hs_id
                            AND   hs_item_no = i.link_hs_item_no
                            AND   org_id         = p_org_id
                            AND client_id = i.client_id  -- added Rev 3.5
                           --- AND   source_data = p_source -- remove  rev 3.5
                            );
            else

              SELECT COUNT(1)
              INTO l_claim_exists
              FROM dual
             WHERE EXISTS (
                            SELECT 1 FROM mpstds.tds_ar_billing
                            WHERE hs_id          = i.link_hs_id
                            AND   hs_item_no = i.link_hs_item_no
                            AND   org_id         = p_org_id
                            AND   source_data = p_source -- added for rev 3.4
                            );
            end if;  -- end for v3.5


             IF l_claim_exists = 0  ---- If Parent Claim does not exists in base table then
             THEN

                    l_washed_status := 'REVERSED_NB';
                    l_billing_status := 'BILLING';
                    --l_error_msg := 'No Error; Message - Parent not in system for this VOIDED Claim';

                    -- no Admin fee is stored if Admin fee is not applied
                    l_admin_fee_applied := 0.00;

                    FND_FILE.PUT_LINE(FND_FILE.OUTPUT,'Message 01 - No Parent Claim found for RxNumber= '||TO_CHAR(i.rx_number)
                                                                                         ||'. hs_id = :'||' '||TO_CHAR(i.hs_id)
                                                                                         ||', hs_item_no =  '||TO_CHAR(i.hs_item_no));

             ELSIF l_claim_exists > 0 ---- If Parent Claim exists in the base table then
             THEN
                    ---- Check the BILLED status of the Parent Claim and current WASHED status of Parent Claim
                   -- start for Rev 3.5 changes
                   if p_source = 'AUDIT' then  -- addded for audit calim to find parent claim without source v 3.5
                        SELECT billing_status, washed_status, client_admin_fee
                              ,creation_date -- Added for v3.0
                          INTO l_parent_billing_status, l_parent_washed_status, l_admin_fee
                              ,l_creation_date -- Added for v3.0
                          FROM mpstds.tds_ar_billing
                         WHERE hs_id = i.link_hs_id
                           AND hs_item_no = i.link_hs_item_no
                           AND client_id = i.client_id  -- added Rev 3.5
                           --AND source_data = p_source -- added for rev 3.4   -- Remove for Audit claim  Rev 3.5
                           AND org_id = p_org_id;
                   else
                      SELECT billing_status, washed_status, client_admin_fee
                              ,creation_date -- Added for v3.0
                          INTO l_parent_billing_status, l_parent_washed_status, l_admin_fee
                              ,l_creation_date -- Added for v3.0
                          FROM mpstds.tds_ar_billing
                         WHERE hs_id = i.link_hs_id
                           AND hs_item_no = i.link_hs_item_no
                           AND source_data = p_source -- added for rev 3.4
                           AND org_id = p_org_id;
                   end if;
                    -- end chnages for Rev 3.5
					
					--Rev 3.8 - Added below Click fee calculation for NVL(i.mass_adj_indicator,'N') = 'Y'
					
					IF NVL(i.mass_adj_indicator,'N') = 'Y' AND l_admin_fee IS NOT NULL THEN
						l_admin_fee:=0;
					END IF;
					
					----Rev 3.8

                    IF l_parent_billing_status = 'BILLED' ---- If Parent Claim is BILLED then Create a CM with wash status as REVERSED
                    THEN
                            ---- Check the wash status of parent Claim -- picked in above query

                        IF (l_parent_washed_status = 'REVERSED') THEN

                            l_error_msg := 'LINE ALREADY REVERSED';
                            l_washed_status := 'ALREADY REVERSED';

                            FND_FILE.PUT_LINE(FND_FILE.OUTPUT,'ERROR 1014 - This Parent Claim is already REVERSED. RxNumber= '||TO_CHAR(i.rx_number)
                                                                                                             ||'. hs_id = :'||' '||TO_CHAR(i.hs_id)
                                                                                                             ||', hs_item_no =  '||TO_CHAR(i.hs_item_no));
                            l_warn := 1;
                            l_admin_fee_applied := NULL;
                            l_new_client_billed_amt := NULL;

                        ELSIF (l_parent_washed_status = 'WASHED') THEN

                            l_error_msg := 'LINE ALREADY WASHED';
                            l_washed_status := 'ALREADY WASHED';

                             FND_FILE.PUT_LINE(FND_FILE.OUTPUT,'ERROR 1015 - This Parent Claim is already WASHED. RxNumber= '||TO_CHAR(i.rx_number)
                                                                                                             ||'. hs_id = :'||' '||TO_CHAR(i.hs_id)
                                                                                                             ||', hs_item_no =  '||TO_CHAR(i.hs_item_no));
                            l_warn := 1;
                            l_admin_fee_applied := NULL;
                            l_new_client_billed_amt := NULL;

                        ELSIF (l_parent_washed_status is NULL) THEN
                            ---- REVERSAL logic

                            -- Added for Rev 3.0
                            IF i.client_id = 'NPS' THEN
                              IF TRUNC(l_creation_date) <= '01-JAN-16' THEN
							     IF NVL(i.mass_adj_indicator,'N') = 'Y' THEN --Added for Rev 3.8
									l_admin_fee_applied := 0; --Added for Rev 3.8
								ELSE --Added for Rev 3.8
								    l_admin_fee_applied := i.client_admin_fee;
								END IF; --Added for Rev 3.8
                              ELSE
                                l_admin_fee_applied := -l_admin_fee;
                              END IF;
                            ELSE
                            -- End of addition for Rev 3.0
                              l_admin_fee_applied := 0.00; -- admin fee should be stored as zero in case of reversal but deducted as per parent
                              l_new_client_billed_amt := l_new_client_billed_amt + l_admin_fee; -- added as admin fee is deducted as per parent -- calculate new billed amt for holding the Admin fee
                            END IF; -- Added for Rev 3.0

                           -- Do not update the parent status in case of Reversal
                            l_washed_status := 'REVERSED';
                            l_billing_status := 'BILLING';

                        END IF;

                    ELSIF l_parent_billing_status <> 'BILLED' ---- If parent Claim is not PAID then also create a CM with remit_status as WASHED
                      THEN
                        ---- WASH Logic

                        l_admin_fee_applied := -l_admin_fee; -- should be negative of admin fee.

                        ---- DO NOT calculate new billed amt in case of wash as it is already taken care from POS

                      l_parent_washed_status := 'WASHED';
                      l_washed_status := 'WASHED';
                      l_washed_date   := SYSDATE;
                      l_billing_status := 'BILLING';

                    END IF;

             END IF;

        ELSE -- if the amount is not negative then this is a new Claim

            ---- DO NOT calculate new billed amt as it is already taken care from POS
            ---- DO NOT calculate admin_fee_applied as it is already aken care from POS
           l_billing_status := 'BILLING';
           l_washed_status := NULL;
          -- IF l_admin_fee_applied IS NOT NULL THEN
           --      l_new_client_billed_amt := l_new_client_billed_amt + l_admin_fee_applied;
          -- END IF;

        END IF;

        ---- Hold Logic
        BEGIN

            ---- Apply the pass thru hold logic
            IF i.client_billed_amt > l_high_dollar_threshold THEN

                SELECT COUNT(1) INTO l_high_dollar_exist
                 FROM dual
                WHERE EXISTS
                (
                    SELECT 1 FROM tds_fnd_lookup_values  -- added for 3.7
                     WHERE lookup_type = 'MPS_HIGH_DOLLAR_FILE' -- added for 3.7
                       AND lookup_code = i.drug_code
                       AND client_id = i.client_id  -- added for 3.7
                       AND enabled_flag = 'Y'
                       AND NVL(start_date_active, SYSDATE) <= SYSDATE
                       AND NVL(end_date_active, SYSDATE) >= SYSDATE
                );

                IF l_high_dollar_exist <> 1 THEN

                    l_billing_status := 'HOLD';

                     ---- high Dollar hold
                    SELECT lookup_code, meaning, description INTO l_hold_reason_code, l_hold_reason, l_hold_desc
                      FROM fnd_lookup_values
                     WHERE lookup_type = 'MPS_HOLD_REASON_CODES'
                       AND lookup_code = 'D';

                    l_hold_warn := 1;
                    l_dollar_hold_cnt := l_dollar_hold_cnt + 1;
                    l_combo_hold_ind := l_combo_hold_ind + 1;

                END IF;

            END IF;

            ---- Apply the spread hold logic
            IF l_spread_contract = 'Y' THEN

                IF ((i.client_ingredient_cost + i.client_dispensing_fee) <> 0) THEN --Added IF Condition for v2.6

                    ---- Calculate the spread from formula
                    --l_spread_per := (((i.client_ingredient_cost + i.client_dispensing_fee - i.o_ingred_cost_paid - i.o_contract_fee_paid)*100)/ -- Commented for Rev 3.1
                    l_spread_per := (((i.client_ingredient_cost + i.client_dispensing_fee - i.o_ingred_cost_paid - i.o_contract_fee_paid - i.prof_service_fee)*100)/ -- Added for Rev 3.1
                                                             (i.client_ingredient_cost + i.client_dispensing_fee));

                    IF l_spread_per > l_high_margin_threshold AND i.source_data <> 'BIDRX' THEN -- Updated for Rev 3.3

                        l_billing_status := 'HOLD';

                        ----high_margin_hold
                        SELECT lookup_code, meaning, description INTO l_hold_reason_code, l_hold_reason, l_hold_desc
                          FROM fnd_lookup_values
                         WHERE lookup_type = 'MPS_HOLD_REASON_CODES'
                           AND lookup_code = 'M';

                        l_hold_warn := 1;
                        l_margin_hold_cnt := l_margin_hold_cnt + 1;
                        l_combo_hold_ind := l_combo_hold_ind + 1;

                    END IF; --Added IF Condition for v2.6
                END IF;
            ELSIF l_spread_contract = 'N' THEN
                     ---- do nothing
                     NULL;

            ELSE
                ---- error out if no contract type is set
                 FND_FILE.PUT_LINE(FND_FILE.OUTPUT,'ERROR 1007 - Contact Type NOT set. RxNumber= '||TO_CHAR(i.rx_number)
                                                                                  || ', hs_id = :'||' '||TO_CHAR(i.hs_id)
                                                                                  || ', hs_item_no =  '||TO_CHAR(i.hs_item_no));
                 l_warn := 1;
                 l_error_msg := 'ERROR 1007 - Spread Contract NOT set';

            END IF;

            --Added below for v2.8
            --Apply Audit Recoupement Hold, Audit hold is applied for claims that are not paid yet, the audit recoupments are billed to customer only after recouping completely
            --no refund till recoupment is complete
            --The audit hold will be applied only if other 2 basic holds are not applied
            IF i.source_data = 'AUDIT' AND (l_dollar_hold_cnt = 0 AND l_margin_hold_cnt = 0) THEN

                BEGIN

                    SELECT payment_status_flag
                      INTO l_pay_flag
                      FROM ap_invoices
                     WHERE global_attribute2= i.hs_id
                       AND global_attribute3 = i.hs_item_no
                       AND global_attribute13 = i.source_data;-- added for rev 3.4

                EXCEPTION
                    WHEN OTHERS THEN
                        l_warn := 1;
                        l_error_msg := 'ERROR 1007.1 - Error in Audit Hold Logic, while finding claim on Remittance side'||substr(' ERROR: '|| sqlcode ||' - '|| sqlerrm,1, 140);
                        fnd_file.put_line(fnd_file.output,'ERROR 1007.1 - Error in Audit Hold Logic. Client_Id: '||TO_CHAR(i.client_id)
                                                                                 ||', RxNumber:'||' '||TO_CHAR(i.rx_number)
                                                                                 ||', hs_id:'||' '||TO_CHAR(i.hs_id)
                                                                                 ||', hs_item_no: '||TO_CHAR(i.hs_item_no)
                                                                                 ||substr(' ERROR: '|| sqlcode ||' - '|| sqlerrm,1, 140));
                END;

                IF l_pay_flag <> 'Y' THEN

                    l_billing_status := 'HOLD';

                        --Audit hold
                        SELECT lookup_code, meaning, description INTO l_hold_reason_code, l_hold_reason, l_hold_desc
                        FROM fnd_lookup_values
                        WHERE lookup_type = 'MPS_HOLD_REASON_CODES'
                        AND lookup_code = 'A';

                        l_hold_warn := 1;
                        l_audit_hold_cnt := l_audit_hold_cnt + 1;
                END IF;

            END IF;

            --Added above for v2.8

            ---- Apply the combo hold logic
            IF l_combo_hold_ind = 2 THEN

                l_billing_status := 'HOLD';

                ----combo hold
                SELECT lookup_code, meaning, description INTO l_hold_reason_code, l_hold_reason, l_hold_desc
                  FROM fnd_lookup_values
                 WHERE lookup_type = 'MPS_HOLD_REASON_CODES'
                   AND lookup_code = 'C';

                l_hold_warn := 1;
                l_combo_hold_cnt  := l_combo_hold_cnt + 1;
                l_dollar_hold_cnt := l_dollar_hold_cnt - 1;      ---- reducing the count in case of combo
                l_margin_hold_cnt := l_margin_hold_cnt - 1;  ---- reducing the count in case of combo
                l_audit_hold_cnt  := l_audit_hold_cnt - 1;--added for v2.8

            END IF;

        EXCEPTION
            WHEN OTHERS THEN
                 l_warn := 1;
                 l_error_msg := 'ERROR 1008 - Error in Hold Logic'||SUBSTR(' ERROR: '|| SQLCODE ||' - '|| SQLERRM,1, 140);
                 FND_FILE.PUT_LINE(FND_FILE.OUTPUT,'ERROR 1008 - Error in Hold Logic. Client_Id: '||TO_CHAR(i.client_id)
                                                                                 ||', RxNumber:'||' '||TO_CHAR(i.rx_number)
                                                                                 ||', hs_id:'||' '||TO_CHAR(i.hs_id)
                                                                                 ||', hs_item_no: '||TO_CHAR(i.hs_item_no)
                                                                                 ||SUBSTR(' ERROR: '|| SQLCODE ||' - '|| SQLERRM,1, 140));
        END;
         -- footer logic - Added to Validate the Calculation of Invoice Amount, Error out if calculation does not match
        BEGIN
		    IF NVL(i.mass_adj_indicator,'N') <> 'Y' THEN --ADDED for Rev 3.8
            IF ((l_client_ingredient_cost + i.client_dispensing_fee + i.o_sales_tax_paid - l_copay + l_admin_fee_applied + i.processor_fee) != l_new_client_billed_amt) THEN -- Animesh -- added processfor_fee as per 3.6 rev
            --IF ((l_client_ingredient_cost + i.client_dispensing_fee + i.o_sales_tax_paid - l_copay + i.client_admin_fee) != i.client_billed_amt) THEN -- komal
            --IF ((l_o_ingred_cost_paid + i.o_contract_fee_paid + i.o_sales_tax_paid - l_copay) != i.invoice_amount) THEN
            --IF ((i.o_ingred_cost_paid + i.o_contract_fee_paid + i.o_sales_tax_paid - i.amt_deducted_orig - i.claim_adjust_amt) != i.invoice_amount) THEN

                --FND_FILE.PUT_LINE(FND_FILE.OUTPUT,'ERROR 1010 - Invalid Invoice Amount for hs_id= '||TO_CHAR(i.hs_id)
                FND_FILE.PUT_LINE(FND_FILE.OUTPUT,'ERROR 1010 - Invalid Client Billed Amount for hs_id= '||TO_CHAR(i.hs_id)
                                                    ||', hs_item_no= '||TO_CHAR(i.hs_item_no)||',rx_number= '||TO_CHAR(i.rx_number));
													
				FND_FILE.PUT_LINE(FND_FILE.OUTPUT,'l_client_ingredient_cost ' || l_client_ingredient_cost || 'i.client_dispensing_fee :' || i.client_dispensing_fee
                                                    ||'i.o_sales_tax_paid '||i.o_sales_tax_paid||'l_copay '||l_copay
													|| 'l_admin_fee_applied ' || l_admin_fee_applied || ' processor_fee ' || i.processor_fee ||  ' === l_new_client_billed_amt ' || l_new_client_billed_amt );

                l_warn := 1;
                l_error_msg := 'ERROR 1010 - Invalid Client Billed Amount';
                l_invalid_invoice_amt_cnt := l_invalid_invoice_amt_cnt + 1;

                -- Reduce the count if failed due to invalid invoice amount
                l_pass_cnt := l_pass_cnt - 1;

            END IF;
			END IF;
        END;

    EXCEPTION
        WHEN cust_setup_err THEN
            FND_FILE.PUT_LINE(FND_FILE.OUTPUT,'ERROR 1001 - Customer Not Setup in the system for ClientID:'||i.client_id ||' - Please Contact Finance Administrator'
                                                            ||SUBSTR(' ERROR - '|| SQLCODE ||' - '|| SQLERRM,1, 140));
            l_warn := 1;
            l_error_msg := 'ERROR 1001 - Customer Not Setup - '||SUBSTR(' ERROR - '|| SQLCODE ||' - '|| SQLERRM,1, 140);

        WHEN prim_site_setup_err THEN
            FND_FILE.PUT_LINE(FND_FILE.OUTPUT,'ERROR 1002 - Primary Site Not Setup in the system for ClientID:'||i.client_id||' - Please Contact Finance Administrator'
                                                            ||SUBSTR(' ERROR - '|| SQLCODE ||' - '|| SQLERRM,1, 140));
            l_warn := 1;
            l_error_msg := 'ERROR 1002 - Primary Site Not Setup - '||SUBSTR(' ERROR - '|| SQLCODE ||' - '|| SQLERRM,1, 140);

        WHEN site_setup_err THEN
            FND_FILE.PUT_LINE(FND_FILE.OUTPUT,'ERROR 1004 - Proper Customer Site Not Setup in the system for Client ID:'||i.client_id
                                                                                                                                    ||' Billing Level: '||l_billing_level
                                                                                                                                    ||' - Please Contact Finance Administrator'
                                                                                                                                    ||SUBSTR(' ERROR - '|| SQLCODE ||' - '|| SQLERRM,1, 140));
            l_warn := 1;
            l_error_msg := 'ERROR 1004 - Proper Customer Site Not Setup - '||SUBSTR(' ERROR - '|| SQLCODE ||' - '|| SQLERRM,1, 140);

        WHEN site_inactive_err THEN
            FND_FILE.PUT_LINE(FND_FILE.OUTPUT,'ERROR 1005 - Customer Site is Inactive for Client ID:'||i.client_id ||' Billing Level: '||l_billing_level
                                                                                                                                        ||' Customer Site Num: '||l_cust_site_num
                                                                                                                                        ||' - Please Contact Finance Administrator'
                                                                                                                                        ||SUBSTR(' ERROR - '|| SQLCODE ||' - '|| SQLERRM,1, 140));
            l_warn := 1;
            l_error_msg := ' ERROR 1005 - Customer Site is Inactive - '||SUBSTR('ERROR - '|| SQLCODE ||' - '|| SQLERRM,1, 140);


        WHEN OTHERS THEN
            l_error_msg := SUBSTR(' ERROR 1006 - Error in Customer/Site/Hold/Wash logic. Error -'|| SQLCODE || ' - '|| SQLERRM, 1, 240);
            FND_FILE.PUT_LINE(FND_FILE.OUTPUT,'ERROR 1006 - Error in Customer/Site/Hold/Wash logic for RxNumber= '||TO_CHAR(i.rx_number)
                                                                                                            || '. hs_id = :'||' '||TO_CHAR(i.hs_id)
                                                                                                            || ', hs_item_no =  '||TO_CHAR(i.hs_item_no)
                                                                                                            || l_error_msg);
            l_warn := 1;
    END full1;

    BEGIN <<update1>>

       IF l_warn = 1 THEN
            l_billing_status := NULL;
       END IF;

        -- Updating the new record with updated status and primary fields in the staging table
        --FND_FILE.PUT_LINE(FND_FILE.OUTPUT,'Message 0002 - record selected for update RxNumber= '||TO_CHAR(i.rx_number) ||'. hs_id = :'||' '||TO_CHAR(i.hs_id)
                                                                                         --||', hs_item_no =  '||TO_CHAR(i.hs_item_no)|| ', billing_status =' || l_billing_status || ', washed_status = ' || l_washed_status);
        UPDATE mpstds.tds_ar_billing
           SET new_client_billed_amt    = l_new_client_billed_amt,
               client_admin_fee_applied = l_admin_fee_applied,
               billing_status           = l_billing_status,
               washed_status            = l_washed_status,
               washed_date              = l_washed_date,
               hold_reason_code         = l_hold_reason_code,
               hold_reason              = l_hold_reason,
               hold_desc                = l_hold_desc,
               amt_deducted             = l_copay,
               o_ingred_cost_paid       = l_o_ingred_cost_paid, -- updating for compound cost change
               client_ingredient_cost   = l_client_ingredient_cost, -- updating for compound cost change
               no_cost_flag             = l_no_cost_flag, -- Added for Rev 1.7
               error_msg                = l_error_msg,
               last_update_date         = SYSDATE,
               last_updated_by          = l_last_updated_by,
               last_update_login        = l_last_update_login
         WHERE ROWID                    = i.rowid;

        IF l_parent_washed_status = 'WASHED'
        THEN
            -- Updating the parent with WASHED Status
             -- Updating the new record with updated status and primary fields in the staging table
        --FND_FILE.PUT_LINE(FND_FILE.OUTPUT,'Message 0003 - record selected for update l_parent_washed_status = '|| l_parent_washed_status||',rx_number= '||TO_CHAR(i.rx_number) ||'. hs_id = :'||' '||TO_CHAR(i.hs_id)
                                                                                         --||', hs_item_no =  '||TO_CHAR(i.hs_item_no)|| ', washed_date =' || l_washed_date );
            UPDATE mpstds.tds_ar_billing
               SET washed_status     = l_parent_washed_status,
                   washed_date       = l_washed_date,
                   last_update_date  = SYSDATE,
                   last_updated_by   = l_last_updated_by,
                   last_update_login = l_last_update_login
             WHERE hs_id             = i.link_hs_id
               AND hs_item_no        = i.link_hs_item_no
               AND source_data       = p_source -- added for rev 3.4
               AND org_id            = p_org_id;

        END IF;

    EXCEPTION
       WHEN OTHERS THEN
          l_error_msg := SUBSTR(' ERROR 1009 - '|| SQLCODE ||' - '|| SQLERRM, 1, 240);
          FND_FILE.PUT_LINE(FND_FILE.OUTPUT, 'ERROR 1009 - In updating Billing Status OR Parent Status in Billing table for RxNumber= '|| TO_CHAR(i.rx_number)
                                                                                                                || '. hs_id = :'||' '|| TO_CHAR(i.hs_id)
                                                                                                                || ', hs_item_no =  '|| TO_CHAR(i.hs_item_no)
                                                                                                                || l_error_msg);

          l_warn := 1;
    END update1;

    IF l_warn = 1 THEN
        l_prog_warn  := 1;
        l_failed_cnt := l_failed_cnt + 1;
    END IF;

  END LOOP;

   COMMIT;
    --added below for v2.8
    --remove audit hold logic
    FOR rec_audit IN cur_audit
    LOOP

         BEGIN

            SELECT payment_status_flag
              INTO l_pay_flag
              FROM ap_invoices
             WHERE global_attribute2= rec_audit.hs_id
               AND global_attribute3 = rec_audit.hs_item_no
               AND global_attribute13 = rec_audit.source_data ; --added for rev 3.4


            IF l_pay_flag = 'Y' THEN
			
			     IF rec_audit.prx_client = 'N' THEN
				 fnd_file.put_line(fnd_file.log, 'AUDIT record  - Client ID : ' || rec_audit.client_id ||  ' prx_client : ' || rec_audit.prx_client);
				
				
					IF rec_audit.tds_billing_flag = 'Y' THEN --For CAT1/CAT2
						UPDATE mpstds.tds_ar_billing
						SET
							billing_status            = 'BILLING',
							hold_reason_code          = NULL,
							hold_reason               = NULL,
							hold_desc                 = NULL,
							error_msg                 = NULL,
							last_update_date          = sysdate,
							last_updated_by           = l_last_updated_by,
							last_update_login         = l_last_update_login
						WHERE
						ROWID                      = rec_audit.rowid;
				  
						l_audit_rem_cnt := l_audit_rem_cnt+1;
				
					ELSE
				
						IF rec_audit.business_extract_flag = 'Y' THEN --ADP Clients for business extracts
								UPDATE mpstds.tds_ar_billing
								SET
							billing_status            = 'BUSINESS-EXTRACT' , --'BILLING',
							hold_reason_code          = NULL,
							hold_reason               = NULL,
							hold_desc                 = NULL,
							error_msg                 = NULL,
							last_update_date          = sysdate,
							billing_schedule_date     = TRUNC(SYSDATE), --Added to facilitate reporting
							last_updated_by           = l_last_updated_by,
							last_update_login         = l_last_update_login
						WHERE
						ROWID                      = rec_audit.rowid;
				  
						fnd_file.put_line(fnd_file.log,'Business Extract eligible for hs_id= '||TO_CHAR(rec_audit.hs_id)
                                                    ||', hs_item_no= '||TO_CHAR(rec_audit.hs_item_no)||',rx_number= '||TO_CHAR(rec_audit.rx_number));
						l_business_extract_cnt := l_business_extract_cnt+1;
						ELSE
						
						  UPDATE mpstds.tds_ar_billing
								SET
							billing_status            = 'BILLING',
							hold_reason_code          = NULL,
							hold_reason               = NULL,
							hold_desc                 = NULL,
							error_msg                 = NULL,
							last_update_date          = sysdate,
							last_updated_by           = l_last_updated_by,
							last_update_login         = l_last_update_login
						WHERE
						ROWID                      = rec_audit.rowid;
						
						END IF; --ADP Clients for Business extracts
						l_audit_rem_cnt := l_audit_rem_cnt+1;
						fnd_file.put_line(fnd_file.log,'Audit Hold Removed for hs_id= '||TO_CHAR(rec_audit.hs_id)
                                                    ||', hs_item_no= '||TO_CHAR(rec_audit.hs_item_no)||',rx_number= '||TO_CHAR(rec_audit.rx_number));
					END IF; --For CAT1/CAT2									
				ELSE --Added for --v3.8
				fnd_file.put_line(fnd_file.log, 'AUDIT record  - Client ID : ' || rec_audit.client_id ||  ' prx_client : '|| rec_audit.prx_client  || 'tds_billing_flag: ' ||rec_audit.tds_billing_flag ||  ' send_ancillary_flag: ' || rec_audit.send_ancillary_flag || ' bill_ancillary_flag: ' || rec_audit.bill_ancillary_flag || ' business_extract_flag : ' || rec_audit.business_extract_flag );
				-- ffv.value_category , rec_audit.tds_billing_flag, rec_audit.send_ancillary_flag , rec_audit.bill_ancillary_flag , rec_audit.business_extract_flag
				
				
				
				 
				 UPDATE mpstds.tds_ar_billing
                   SET
                   billing_status            = 'AUDIT-ANC-PENDING',
                   hold_reason_code          = NULL,
                   hold_reason               = NULL,
                   hold_desc                 = NULL,
                   error_msg                 = NULL,
                   last_update_date          = sysdate,
                   last_updated_by           = l_last_updated_by,
                   last_update_login         = l_last_update_login
                WHERE
                  ROWID                      = rec_audit.rowid;
				  
				l_audit_anc_sent_cnt := l_audit_anc_sent_cnt+1;

                fnd_file.put_line(fnd_file.log,'Sent to Ancillary Billing - Audit Hold Removed for hs_id= '||TO_CHAR(rec_audit.hs_id)
                                                    ||', hs_item_no= '||TO_CHAR(rec_audit.hs_item_no)||',rx_number= '||TO_CHAR(rec_audit.rx_number));
				
				
				
				END IF;-- Addition end --v3.8

            END IF;
			
			--Submit concurrent Program to send Business Extract records
			
			

        EXCEPTION
        WHEN OTHERS THEN
            l_warn := 1;
            l_error_msg := 'ERROR 1007.2 - Error in removing Audit Hold Logic, while finding claim on Remittance side'||substr(' ERROR: '|| sqlcode ||' - '|| sqlerrm,1, 140);
            fnd_file.put_line(fnd_file.output,'ERROR 1007.2 - Error in removing Audit Hold Logic. Client_Id: '||TO_CHAR(rec_audit.client_id)
                                                                     ||', RxNumber:'||' '||TO_CHAR(rec_audit.rx_number)
                                                                     ||', hs_id:'||' '||TO_CHAR(rec_audit.hs_id)
                                                                     ||', hs_item_no: '||TO_CHAR(rec_audit.hs_item_no)
                                                                     ||substr(' ERROR: '|| sqlcode ||' - '|| sqlerrm,1, 140));
        END;

    END LOOP;

    COMMIT;
    --added above for v2.8


			IF p_source = 'AUDIT' THEN --Added for Rev 3.8
			     l_req_id := fnd_request.submit_request ('MPSTDS',
                                          'TDS_BILL_AUDIT_RECOUP',
                                          'TDS Billing Prescription File - Audit Recoupments',
                                          SYSDATE,
                                          FALSE,
                                          'ALL',
										  NULL,
										  to_char(trunc(SYSDATE),'YYYY/MM/DD HH24:MI:SS'),
										  to_char(trunc(SYSDATE+1),'YYYY/MM/DD HH24:MI:SS'),
										  NULL,
										  NULL,
										  p_org_id
										  );
				commit;

				IF l_req_id = 0
				THEN
					FND_FILE.PUT_LINE (FND_FILE.LOG, 'TDS Billing Prescription File - Audit Recoupments Conc Req not submitted  ');
				ELSE
					FND_FILE.PUT_LINE (FND_FILE.LOG, 'TDS Billing Prescription File - Audit Recoupments Concurrent Request Id: ' || l_req_id);
				END IF;
				
			     
			 END IF; -- IF p_source = 'AUDIT' THEN
			




   IF (l_prog_warn = 1 OR l_hold_warn = 1)
   THEN
       ---- Set PROG status as WARNING
       p_errbuff  := c_errbuf_w;
       p_retcode  := c_retcode_w;
   END IF;

   FND_FILE.PUT_LINE(FND_FILE.OUTPUT,'********************************** SUMMARY *************************************************************************************************************');
   FND_FILE.PUT_LINE(FND_FILE.OUTPUT,'  ');
   FND_FILE.PUT_LINE(FND_FILE.OUTPUT,'                       Total Number Of Claims : '||TO_CHAR(l_total_count));
   FND_FILE.PUT_LINE(FND_FILE.OUTPUT,'                Total Number Of Claims Passed : '||TO_CHAR(l_total_count - l_failed_cnt));
   FND_FILE.PUT_LINE(FND_FILE.OUTPUT,'                Total Number Of Claims FAILED : '||TO_CHAR(l_failed_cnt - l_invalid_invoice_amt_cnt));
   FND_FILE.PUT_LINE(FND_FILE.OUTPUT,' Total Claims FAILED for Invalid Claim Amount : '||TO_CHAR(l_invalid_invoice_amt_cnt));
   FND_FILE.PUT_LINE(FND_FILE.OUTPUT,'  ');
   FND_FILE.PUT_LINE(FND_FILE.OUTPUT,'******************************** Hold Summary ********************************');
   FND_FILE.PUT_LINE(FND_FILE.OUTPUT,'  ');
   FND_FILE.PUT_LINE(FND_FILE.OUTPUT,'     Total Claims Marked for High Dollar Hold : '||TO_CHAR(l_dollar_hold_cnt));
   FND_FILE.PUT_LINE(FND_FILE.OUTPUT,'Total Claims Marked for Excessive Margin Hold : '||TO_CHAR(l_margin_hold_cnt));
   fnd_file.put_line(fnd_file.output,'           Total Claims Marked for Audit Hold : '||TO_CHAR(l_audit_hold_cnt)); --added for v2.8
   FND_FILE.PUT_LINE(FND_FILE.OUTPUT,'           Total Claims Marked for Combo Hold : '||TO_CHAR(l_combo_hold_cnt));
   fnd_file.put_line(fnd_file.output,'   Total Claims Marked for Audit Hold Removed : '||TO_CHAR(l_audit_rem_cnt)); --added for v2.8
   fnd_file.put_line(fnd_file.output,'   Total Prx Claims Sent to Ancillary Billing : '||TO_CHAR(l_audit_anc_sent_cnt)); --added for v3.8
   fnd_file.put_line(fnd_file.output,'   Total Prx Claims Marked as Business Extract: '||TO_CHAR(l_business_extract_cnt)); --added for v3.8
   FND_FILE.PUT_LINE(FND_FILE.OUTPUT,'  ');
   FND_FILE.PUT_LINE(FND_FILE.OUTPUT,'******************************* END OF MESSAGE ********************************************************************************************************');

EXCEPTION
    WHEN OTHERS THEN
        FND_FILE.PUT_LINE(FND_FILE.OUTPUT,'Other ERROR 1011 -'||' '||SQLCODE ||' - '||SQLERRM);
        FND_FILE.PUT_LINE(FND_FILE.OUTPUT,'******************************* END OF MESSAGE *****************************************************************************************************');
        ROLLBACK;
        ---- Set PROG status as ERROR
        p_errbuff  := c_errbuf_e;
        p_retcode  := c_retcode_e;
END billing_claims_update;


PROCEDURE unlock_schedule_claim
(
    p_errbuff  OUT VARCHAR2,
    p_retcode  OUT NUMBER,
    p_client_id IN VARCHAR2
)
IS

    l_user_id            NUMBER        := TO_NUMBER(fnd_global.user_id);
    l_resp_name          VARCHAR2(100) := FND_PROFILE.VALUE('RESP_NAME');
    l_last_update_login  NUMBER        := TO_NUMBER(fnd_global.login_id);

BEGIN

    ---- Set PROG status as SUCCESS initially
    p_errbuff  := c_errbuf_s;
    p_retcode  := c_retcode_s;

    FND_FILE.PUT_LINE(FND_FILE.OUTPUT, '****************************** UNLOCK SCHEDULE RESULT ******************************************');

    FND_FILE.PUT_LINE(FND_FILE.OUTPUT, l_user_id || ' - ' || l_resp_name);

    IF l_resp_name = 'System Administrator'
    THEN

        UPDATE mpstds.tds_ar_billing
           SET user_batch_id         = NULL
              ,processing_flag       = NULL
              ,billing_invoice_id    = NULL
              ,billing_invoice_num   = NULL
              ,billing_status        = 'BILLING'
              ,billed_date           = NULL
              ,billing_schedule_date = NULL
              ,last_update_date      = SYSDATE
              ,last_updated_by       = l_user_id
              ,last_update_login     = l_last_update_login
        WHERE  processing_flag       = 'P';

        UPDATE mpstds.tds_ar_billing_sch_lines
           SET user_batch_id       = NULL
              ,processing_flag     = NULL
              ,schedule_group_type = NULL
              ,last_update_date    = SYSDATE
              ,last_update_by      = l_user_id
              ,last_update_login   = l_last_update_login
        WHERE  processing_flag     = 'P';

        FND_FILE.PUT_LINE(FND_FILE.OUTPUT, 'Schedule and Claims Unlocked successfully for All Users');

    ELSE

        UPDATE mpstds.tds_ar_billing
           SET user_batch_id         = NULL
              ,processing_flag       = NULL
              ,billing_invoice_id    = NULL
              ,billing_invoice_num   = NULL
              ,billing_status        = 'BILLING'
              ,billed_date           = NULL
              ,billing_schedule_date = NULL
              ,last_update_date      = SYSDATE
              ,last_updated_by       = l_user_id
              ,last_update_login     = l_last_update_login
        WHERE  processing_flag       = 'P'
          AND  last_updated_by       = l_user_id;

        UPDATE mpstds.tds_ar_billing_sch_lines
           SET user_batch_id       = NULL
              ,processing_flag     = NULL
              ,schedule_group_type = NULL
              ,last_update_date    = SYSDATE
              ,last_update_by      = l_user_id
              ,last_update_login   = l_last_update_login
         WHERE processing_flag     = 'P'
           AND last_update_by      = l_user_id;

        FND_FILE.PUT_LINE(FND_FILE.OUTPUT, 'Schedule and Claims Unlocked successfully for for user - '||l_user_id);

    END IF;

    FND_FILE.PUT_LINE(FND_FILE.OUTPUT, '**************************** END OF MESSAGE *************************************************');
    COMMIT;

EXCEPTION
    WHEN OTHERS THEN
        FND_FILE.PUT_LINE(FND_FILE.OUTPUT, 'ERROR 1012 - Unable to Unlock Schedule and Claims All users OR for user - '||l_user_id ||'Error Detail - ' || SQLCODE ||' - '||SQLERRM);
        FND_FILE.PUT_LINE(FND_FILE.OUTPUT, '**************************** END OF MESSAGE *************************************************');
        ROLLBACK;
        ---- Set PROG status as ERROR
        p_errbuff  := c_errbuf_e;
        p_retcode  := c_retcode_e;

END unlock_schedule_claim;

END tds_ar_billing_interface_pkg;
/
