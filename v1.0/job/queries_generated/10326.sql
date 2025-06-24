SELECT 
    a.name AS aka_name,
    t.title AS movie_title,
    c.nr_order AS cast_order,
    n.name AS person_name,
    r.role AS role_type,
    cc.kind AS company_kind,
    m.info AS movie_info
FROM 
    aka_name a
JOIN 
    cast_info c ON a.person_id = c.person_id
JOIN 
    title t ON c.movie_id = t.id
JOIN 
    name n ON a.person_id = n.imdb_id
JOIN 
    role_type r ON c.role_id = r.id
JOIN 
    movie_companies mc ON t.id = mc.movie_id
JOIN 
    company_name cc ON mc.company_id = cc.id
JOIN 
    movie_info m ON t.id = m.movie_id
WHERE 
    t.production_year BETWEEN 2000 AND 2023 
ORDER BY 
    t.production_year DESC, 
    c.nr_order;
