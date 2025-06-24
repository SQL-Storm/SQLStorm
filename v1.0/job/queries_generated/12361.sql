SELECT 
    a.name AS aka_name,
    t.title AS movie_title,
    p.name AS person_name,
    r.role AS person_role,
    c.note AS cast_note
FROM 
    aka_name a
JOIN 
    cast_info c ON a.person_id = c.person_id
JOIN 
    title t ON c.movie_id = t.id
JOIN 
    role_type r ON c.role_id = r.id
JOIN 
    company_name cn ON c.movie_id = cn.imdb_id
WHERE 
    t.production_year > 2000
ORDER BY 
    t.production_year DESC;
