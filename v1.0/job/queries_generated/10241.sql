SELECT 
    a.name AS aka_name,
    t.title AS movie_title,
    r.role AS person_role,
    c.note AS cast_note,
    m.name AS company_name,
    k.keyword AS movie_keyword
FROM 
    aka_name a
JOIN 
    cast_info c ON a.person_id = c.person_id
JOIN 
    title t ON c.movie_id = t.id
JOIN 
    movie_companies mc ON t.id = mc.movie_id
JOIN 
    company_name m ON mc.company_id = m.id
JOIN 
    movie_keyword mk ON t.id = mk.movie_id
JOIN 
    keyword k ON mk.keyword_id = k.id
JOIN 
    role_type r ON c.role_id = r.id
WHERE 
    a.name IS NOT NULL 
AND 
    t.production_year >= 2000
ORDER BY 
    t.production_year DESC, a.name;
