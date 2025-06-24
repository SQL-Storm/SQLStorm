SELECT 
    a.name AS actor_name,
    t.title AS movie_title,
    t.production_year
FROM 
    aka_name a
JOIN 
    cast_info ci ON a.person_id = ci.person_id
JOIN 
    aka_title t ON ci.movie_id = t.movie_id
WHERE 
    t.kind_id = (SELECT id FROM kind_type WHERE kind = 'movie')
ORDER BY 
    t.production_year DESC;
