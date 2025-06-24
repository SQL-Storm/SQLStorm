SELECT 
    a.name AS actor_name,
    t.title AS movie_title,
    t.production_year,
    c.kind AS cast_role
FROM 
    aka_name a
JOIN 
    cast_info ci ON a.person_id = ci.person_id
JOIN 
    aka_title t ON ci.movie_id = t.movie_id
JOIN 
    comp_cast_type c ON ci.person_role_id = c.id
WHERE 
    t.production_year > 2000;
