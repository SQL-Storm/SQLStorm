SELECT 
    t.title,
    a.name AS actor_name,
    c.note AS role_note,
    m.name AS company_name,
    i.info AS movie_info
FROM 
    title t
JOIN 
    cast_info c ON t.id = c.movie_id
JOIN 
    aka_name a ON c.person_id = a.person_id
JOIN 
    movie_companies mc ON t.id = mc.movie_id
JOIN 
    company_name m ON mc.company_id = m.id
JOIN 
    movie_info i ON t.id = i.movie_id
WHERE 
    t.production_year > 2000
ORDER BY 
    t.title;
