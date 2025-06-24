-- Performance Benchmarking Query
SELECT 
    t.title AS movie_title,
    c.name AS actor_name,
    r.role AS role_name,
    m.production_year,
    k.keyword AS movie_keyword,
    comp.name AS company_name,
    a.name AS aka_name
FROM 
    title t
JOIN 
    movie_keyword mk ON t.id = mk.movie_id
JOIN 
    keyword k ON mk.keyword_id = k.id
JOIN 
    complete_cast cc ON t.id = cc.movie_id
JOIN 
    cast_info ci ON cc.subject_id = ci.id
JOIN 
    aka_name a ON ci.person_id = a.person_id
JOIN 
    name n ON a.person_id = n.imdb_id
JOIN 
    role_type r ON ci.role_id = r.id
JOIN 
    movie_companies mc ON t.id = mc.movie_id
JOIN 
    company_name comp ON mc.company_id = comp.id
WHERE 
    t.production_year >= 2000
ORDER BY 
    t.production_year DESC, 
    t.title, 
    actor_name;
