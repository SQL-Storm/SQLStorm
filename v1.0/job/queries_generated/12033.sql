SELECT 
    a.name AS aka_name,
    t.title AS movie_title,
    c.note AS cast_note,
    ct.kind AS company_type,
    k.keyword AS movie_keyword,
    i.info AS info_type,
    r.role AS role_name
FROM 
    aka_name a
JOIN 
    cast_info c ON a.person_id = c.person_id
JOIN 
    aka_title t ON c.movie_id = t.movie_id
JOIN 
    movie_companies mc ON t.id = mc.movie_id
JOIN 
    company_type ct ON mc.company_type_id = ct.id
JOIN 
    movie_keyword mk ON t.id = mk.movie_id
JOIN 
    keyword k ON mk.keyword_id = k.id
JOIN 
    movie_info mi ON t.id = mi.movie_id
JOIN 
    info_type i ON mi.info_type_id = i.id
JOIN 
    role_type r ON c.role_id = r.id
WHERE 
    t.production_year >= 2000
ORDER BY 
    t.production_year DESC, a.name;
