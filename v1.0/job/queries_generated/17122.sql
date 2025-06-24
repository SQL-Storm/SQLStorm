SELECT 
    t.title,
    a.name AS actor_name,
    c.kind AS role
FROM 
    title t
JOIN 
    complete_cast cc ON t.id = cc.movie_id
JOIN 
    cast_info ci ON cc.subject_id = ci.id
JOIN 
    aka_name a ON ci.person_id = a.person_id
JOIN 
    role_type c ON ci.role_id = c.id
WHERE 
    t.production_year > 2000
ORDER BY 
    t.production_year DESC, a.name;
