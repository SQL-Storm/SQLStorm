SELECT 
    t.title AS movie_title, 
    a.name AS actor_name, 
    r.role AS role, 
    c.kind AS company_type,
    m.production_year AS production_year
FROM 
    title t
JOIN 
    cast_info ci ON t.id = ci.movie_id
JOIN 
    aka_name a ON ci.person_id = a.person_id
JOIN 
    role_type r ON ci.role_id = r.id
JOIN 
    movie_companies mc ON t.id = mc.movie_id
JOIN 
    company_type c ON mc.company_type_id = c.id
JOIN 
    movie_info mi ON t.id = mi.movie_id
WHERE 
    m.production_year > 2000
ORDER BY 
    t.production_year DESC;
