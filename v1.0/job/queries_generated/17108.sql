SELECT 
    t.title, 
    a.name AS actor_name, 
    c.nr_order 
FROM 
    title t 
JOIN 
    complete_cast cc ON t.id = cc.movie_id 
JOIN 
    cast_info ci ON cc.subject_id = ci.id 
JOIN 
    aka_name a ON ci.person_id = a.person_id 
WHERE 
    t.production_year = 2023 
ORDER BY 
    t.title, 
    c.nr_order;
