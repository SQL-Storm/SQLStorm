SELECT 
    a.name AS actor_name, 
    t.title AS movie_title, 
    t.production_year
FROM 
    cast_info ci
JOIN 
    aka_name a ON ci.person_id = a.person_id
JOIN 
    aka_title t ON ci.movie_id = t.movie_id
WHERE 
    ci.nr_order = 1
ORDER BY 
    t.production_year DESC;
