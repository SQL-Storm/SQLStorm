SELECT 
    n.name AS person_name,
    a.name AS aka_name,
    t.title AS movie_title,
    ci.note AS role_note,
    c.kind AS company_type,
    k.keyword AS movie_keyword,
    mi.info AS movie_info
FROM 
    cast_info ci
JOIN 
    aka_name a ON ci.person_id = a.person_id
JOIN 
    title t ON ci.movie_id = t.id
JOIN 
    movie_companies mc ON t.id = mc.movie_id
JOIN 
    company_name c ON mc.company_id = c.id
JOIN 
    movie_keyword mk ON t.id = mk.movie_id
JOIN 
    keyword k ON mk.keyword_id = k.id
JOIN 
    movie_info mi ON t.id = mi.movie_id
JOIN 
    role_type r ON ci.role_id = r.id
JOIN 
    name n ON ci.person_id = n.imdb_id
WHERE 
    t.production_year >= 2000
ORDER BY 
    t.production_year DESC, n.name;
