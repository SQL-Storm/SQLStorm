SELECT 
    a.name AS aka_name, 
    t.title AS movie_title, 
    c.nr_order AS cast_order, 
    p.gender AS person_gender, 
    cn.name AS company_name, 
    k.keyword AS movie_keyword 
FROM 
    aka_name a 
JOIN 
    cast_info c ON a.person_id = c.person_id 
JOIN 
    title t ON c.movie_id = t.id 
JOIN 
    movie_companies mc ON t.id = mc.movie_id 
JOIN 
    company_name cn ON mc.company_id = cn.id 
JOIN 
    movie_keyword mk ON t.id = mk.movie_id 
JOIN 
    keyword k ON mk.keyword_id = k.id 
JOIN 
    name p ON a.person_id = p.imdb_id 
WHERE 
    t.production_year > 2000 
AND 
    cn.country_code = 'USA' 
ORDER BY 
    t.production_year DESC, 
    c.nr_order ASC 
LIMIT 100;
