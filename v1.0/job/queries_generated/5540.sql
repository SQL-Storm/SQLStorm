SELECT a.id AS aka_id, a.name AS aka_name, t.title AS movie_title, c.note AS cast_note, p.info AS person_info, k.keyword AS movie_keyword, co.name AS company_name 
FROM aka_name a 
JOIN cast_info c ON a.person_id = c.person_id 
JOIN title t ON c.movie_id = t.id 
JOIN movie_keyword mk ON t.id = mk.movie_id 
JOIN keyword k ON mk.keyword_id = k.id 
JOIN complete_cast cc ON t.id = cc.movie_id 
JOIN person_info p ON a.person_id = p.person_id 
JOIN movie_companies mc ON t.id = mc.movie_id 
JOIN company_name co ON mc.company_id = co.id 
WHERE t.production_year > 2000 
AND c.nr_order < 5 
AND k.keyword LIKE '%action%' 
ORDER BY t.production_year DESC, a.name ASC;
