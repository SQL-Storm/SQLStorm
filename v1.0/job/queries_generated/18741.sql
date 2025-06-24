SELECT 
    t.title AS movie_title,
    a.name AS actor_name,
    c.role_id,
    c.nr_order
FROM 
    title t
JOIN 
    movie_companies mc ON t.id = mc.movie_id
JOIN 
    company_name cn ON mc.company_id = cn.id
JOIN 
    cast_info c ON t.id = c.movie_id
JOIN 
    aka_name a ON c.person_id = a.person_id
WHERE 
    t.production_year > 2000
ORDER BY 
    t.title, c.nr_order;
