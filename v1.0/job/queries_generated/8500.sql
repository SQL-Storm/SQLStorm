EXPLAIN ANALYZE
SELECT 
    ak.name AS aka_name,
    t.title AS movie_title,
    c.nr_order AS cast_order,
    p.info AS person_info,
    comp.name AS company_name,
    k.keyword AS movie_keyword
FROM 
    aka_name ak
JOIN 
    cast_info c ON ak.person_id = c.person_id
JOIN 
    title t ON c.movie_id = t.id
JOIN 
    person_info p ON ak.person_id = p.person_id
JOIN 
    movie_companies m ON t.id = m.movie_id
JOIN 
    company_name comp ON m.company_id = comp.id
JOIN 
    movie_keyword mk ON t.id = mk.movie_id
JOIN 
    keyword k ON mk.keyword_id = k.id
WHERE 
    t.production_year > 2000
    AND ak.name IS NOT NULL
    AND p.info_type_id IN (SELECT id FROM info_type WHERE info = 'biography')
ORDER BY 
    t.production_year DESC, c.nr_order ASC
LIMIT 50;
