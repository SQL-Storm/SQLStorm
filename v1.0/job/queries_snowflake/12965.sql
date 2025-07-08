SELECT 
    a.name AS aka_name,
    t.title AS movie_title,
    c.note AS cast_note,
    cr.role AS role_description
FROM 
    aka_name a
JOIN 
    cast_info c ON a.person_id = c.person_id
JOIN 
    title t ON c.movie_id = t.id
JOIN 
    role_type cr ON c.role_id = cr.id
WHERE 
    t.production_year >= 2000
ORDER BY 
    t.production_year DESC, a.name;
