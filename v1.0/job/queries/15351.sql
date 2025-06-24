SELECT 
    a.name AS aka_name, 
    t.title AS movie_title, 
    p.info AS person_info 
FROM 
    aka_name a 
JOIN 
    cast_info ci ON a.person_id = ci.person_id 
JOIN 
    title t ON ci.movie_id = t.id 
JOIN 
    person_info p ON a.person_id = p.person_id 
WHERE 
    t.production_year >= 2000;
