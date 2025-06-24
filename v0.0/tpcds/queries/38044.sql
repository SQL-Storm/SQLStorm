
-- end query 35 in stream 0 using template query67.tpl
-- start query 36 in stream 0 using template query28.tpl
select  *
from (select avg(ss_list_price) B1_LP
            ,count(ss_list_price) B1_CNT
            ,count(distinct ss_list_price) B1_CNTD
      from store_sales
      where ss_quantity between 0 and 5
        and (ss_list_price between 36 and 36+10 
             or ss_coupon_amt between 10763 and 10763+1000
             or ss_wholesale_cost between 11 and 11+20)) B1,
     (select avg(ss_list_price) B2_LP
            ,count(ss_list_price) B2_CNT
            ,count(distinct ss_list_price) B2_CNTD
      from store_sales
      where ss_quantity between 6 and 10
        and (ss_list_price between 17 and 17+10
          or ss_coupon_amt between 1769 and 1769+1000
          or ss_wholesale_cost between 44 and 44+20)) B2,
     (select avg(ss_list_price) B3_LP
            ,count(ss_list_price) B3_CNT
            ,count(distinct ss_list_price) B3_CNTD
      from store_sales
      where ss_quantity between 11 and 15
        and (ss_list_price between 176 and 176+10
          or ss_coupon_amt between 11341 and 11341+1000
          or ss_wholesale_cost between 54 and 54+20)) B3,
     (select avg(ss_list_price) B4_LP
            ,count(ss_list_price) B4_CNT
            ,count(distinct ss_list_price) B4_CNTD
      from store_sales
      where ss_quantity between 16 and 20
        and (ss_list_price between 89 and 89+10
          or ss_coupon_amt between 16333 and 16333+1000
          or ss_wholesale_cost between 75 and 75+20)) B4,
     (select avg(ss_list_price) B5_LP
            ,count(ss_list_price) B5_CNT
            ,count(distinct ss_list_price) B5_CNTD
      from store_sales
      where ss_quantity between 21 and 25
        and (ss_list_price between 38 and 38+10
          or ss_coupon_amt between 7903 and 7903+1000
          or ss_wholesale_cost between 34 and 34+20)) B5,
     (select avg(ss_list_price) B6_LP
            ,count(ss_list_price) B6_CNT
            ,count(distinct ss_list_price) B6_CNTD
      from store_sales
      where ss_quantity between 26 and 30
        and (ss_list_price between 21 and 21+10
          or ss_coupon_amt between 6979 and 6979+1000
          or ss_wholesale_cost between 76 and 76+20)) B6
limit 100;
