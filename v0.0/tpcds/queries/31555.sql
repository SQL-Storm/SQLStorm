
-- end query 35 in stream 0 using template query67.tpl
-- start query 36 in stream 0 using template query28.tpl
select  *
from (select avg(ss_list_price) B1_LP
            ,count(ss_list_price) B1_CNT
            ,count(distinct ss_list_price) B1_CNTD
      from store_sales
      where ss_quantity between 0 and 5
        and (ss_list_price between 114 and 114+10 
             or ss_coupon_amt between 3442 and 3442+1000
             or ss_wholesale_cost between 66 and 66+20)) B1,
     (select avg(ss_list_price) B2_LP
            ,count(ss_list_price) B2_CNT
            ,count(distinct ss_list_price) B2_CNTD
      from store_sales
      where ss_quantity between 6 and 10
        and (ss_list_price between 26 and 26+10
          or ss_coupon_amt between 8493 and 8493+1000
          or ss_wholesale_cost between 7 and 7+20)) B2,
     (select avg(ss_list_price) B3_LP
            ,count(ss_list_price) B3_CNT
            ,count(distinct ss_list_price) B3_CNTD
      from store_sales
      where ss_quantity between 11 and 15
        and (ss_list_price between 14 and 14+10
          or ss_coupon_amt between 7908 and 7908+1000
          or ss_wholesale_cost between 17 and 17+20)) B3,
     (select avg(ss_list_price) B4_LP
            ,count(ss_list_price) B4_CNT
            ,count(distinct ss_list_price) B4_CNTD
      from store_sales
      where ss_quantity between 16 and 20
        and (ss_list_price between 127 and 127+10
          or ss_coupon_amt between 17524 and 17524+1000
          or ss_wholesale_cost between 26 and 26+20)) B4,
     (select avg(ss_list_price) B5_LP
            ,count(ss_list_price) B5_CNT
            ,count(distinct ss_list_price) B5_CNTD
      from store_sales
      where ss_quantity between 21 and 25
        and (ss_list_price between 88 and 88+10
          or ss_coupon_amt between 1639 and 1639+1000
          or ss_wholesale_cost between 2 and 2+20)) B5,
     (select avg(ss_list_price) B6_LP
            ,count(ss_list_price) B6_CNT
            ,count(distinct ss_list_price) B6_CNTD
      from store_sales
      where ss_quantity between 26 and 30
        and (ss_list_price between 25 and 25+10
          or ss_coupon_amt between 2170 and 2170+1000
          or ss_wholesale_cost between 27 and 27+20)) B6
limit 100;
