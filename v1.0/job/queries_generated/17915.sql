SELECT a.name AS aka_name, t.title AS movie_title, ci.nr_order AS cast_order
FROM aka_name a
JOIN cast_info ci ON a.person_id = ci.person_id
JOIN aka_title t ON ci.movie_id = t.movie_id
WHERE t.production_year = 2020
ORDER BY ci.nr_order;
