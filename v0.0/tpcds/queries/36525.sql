
-- end query 61 in stream 0 using template query42.tpl
-- start query 62 in stream 0 using template query41.tpl
select  distinct(i_product_name)
 from item i1
 where i_manufact_id between 988 and 988+40 
   and (select count(*) as item_cnt
        from item
        where (i_manufact = i1.i_manufact and
        ((i_category = 'Women' and 
        (i_color = 'chiffon' or i_color = 'magenta') and 
        (i_units = 'Oz' or i_units = 'Bunch') and
        (i_size = 'small' or i_size = 'N/A')
        ) or
        (i_category = 'Women' and
        (i_color = 'burlywood' or i_color = 'plum') and
        (i_units = 'Pound' or i_units = 'Tbl') and
        (i_size = 'extra large' or i_size = 'medium')
        ) or
        (i_category = 'Men' and
        (i_color = 'blush' or i_color = 'khaki') and
        (i_units = 'N/A' or i_units = 'Dozen') and
        (i_size = 'economy' or i_size = 'petite')
        ) or
        (i_category = 'Men' and
        (i_color = 'bisque' or i_color = 'mint') and
        (i_units = 'Gram' or i_units = 'Bundle') and
        (i_size = 'small' or i_size = 'N/A')
        ))) or
       (i_manufact = i1.i_manufact and
        ((i_category = 'Women' and 
        (i_color = 'thistle' or i_color = 'orange') and 
        (i_units = 'Ton' or i_units = 'Each') and
        (i_size = 'small' or i_size = 'N/A')
        ) or
        (i_category = 'Women' and
        (i_color = 'goldenrod' or i_color = 'antique') and
        (i_units = 'Case' or i_units = 'Ounce') and
        (i_size = 'extra large' or i_size = 'medium')
        ) or
        (i_category = 'Men' and
        (i_color = 'lemon' or i_color = 'spring') and
        (i_units = 'Cup' or i_units = 'Unknown') and
        (i_size = 'economy' or i_size = 'petite')
        ) or
        (i_category = 'Men' and
        (i_color = 'lawn' or i_color = 'hot') and
        (i_units = 'Gross' or i_units = 'Tsp') and
        (i_size = 'small' or i_size = 'N/A')
        )))) > 0
 order by i_product_name
 limit 100;
