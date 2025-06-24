SELECT 
    a.name AS aka_name,
    t.title AS movie_title,
    p.name AS person_name,
    r.role AS role_type,
    c.kind AS comp_cast
FROM 
    aka_name a
JOIN 
    cast_info ci ON a.person_id = ci.person_id
JOIN 
    title t ON ci.movie_id = t.id
JOIN 
    role_type r ON ci.role_id = r.id
JOIN 
    complete_cast cc ON t.id = cc.movie_id
JOIN 
    company_name c ON cc.subject_id = c.imdb_id
WHERE 
    t.production_year >= 2000
ORDER BY 
    t.production_year DESC, a.name;
