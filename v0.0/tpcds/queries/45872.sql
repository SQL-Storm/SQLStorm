
-- end query 35 in stream 0 using template query67.tpl
-- start query 36 in stream 0 using template query28.tpl
select  *
from (select avg(ss_list_price) B1_LP
            ,count(ss_list_price) B1_CNT
            ,count(distinct ss_list_price) B1_CNTD
      from store_sales
      where ss_quantity between 0 and 5
        and (ss_list_price between 75 and 75+10 
             or ss_coupon_amt between 3811 and 3811+1000
             or ss_wholesale_cost between 4 and 4+20)) B1,
     (select avg(ss_list_price) B2_LP
            ,count(ss_list_price) B2_CNT
            ,count(distinct ss_list_price) B2_CNTD
      from store_sales
      where ss_quantity between 6 and 10
        and (ss_list_price between 53 and 53+10
          or ss_coupon_amt between 17471 and 17471+1000
          or ss_wholesale_cost between 33 and 33+20)) B2,
     (select avg(ss_list_price) B3_LP
            ,count(ss_list_price) B3_CNT
            ,count(distinct ss_list_price) B3_CNTD
      from store_sales
      where ss_quantity between 11 and 15
        and (ss_list_price between 2 and 2+10
          or ss_coupon_amt between 12428 and 12428+1000
          or ss_wholesale_cost between 45 and 45+20)) B3,
     (select avg(ss_list_price) B4_LP
            ,count(ss_list_price) B4_CNT
            ,count(distinct ss_list_price) B4_CNTD
      from store_sales
      where ss_quantity between 16 and 20
        and (ss_list_price between 84 and 84+10
          or ss_coupon_amt between 5549 and 5549+1000
          or ss_wholesale_cost between 32 and 32+20)) B4,
     (select avg(ss_list_price) B5_LP
            ,count(ss_list_price) B5_CNT
            ,count(distinct ss_list_price) B5_CNTD
      from store_sales
      where ss_quantity between 21 and 25
        and (ss_list_price between 77 and 77+10
          or ss_coupon_amt between 6284 and 6284+1000
          or ss_wholesale_cost between 73 and 73+20)) B5,
     (select avg(ss_list_price) B6_LP
            ,count(ss_list_price) B6_CNT
            ,count(distinct ss_list_price) B6_CNTD
      from store_sales
      where ss_quantity between 26 and 30
        and (ss_list_price between 27 and 27+10
          or ss_coupon_amt between 2950 and 2950+1000
          or ss_wholesale_cost between 36 and 36+20)) B6
limit 100;
