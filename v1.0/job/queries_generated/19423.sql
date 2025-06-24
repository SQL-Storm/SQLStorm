SELECT 
    t.title, 
    a.name AS actor_name, 
    r.role AS actor_role
FROM 
    title t
JOIN 
    cast_info ci ON t.id = ci.movie_id
JOIN 
    aka_name a ON ci.person_id = a.person_id
JOIN 
    role_type r ON ci.role_id = r.id
WHERE 
    t.production_year = 2020
ORDER BY 
    t.title;
