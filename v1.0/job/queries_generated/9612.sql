SELECT 
    a.name AS actor_name,
    t.title AS movie_title,
    ci.nr_order AS role_order,
    r.role AS role_type,
    c.name AS company_name,
    m.info AS movie_info,
    kw.keyword AS movie_keyword
FROM 
    aka_name a
JOIN 
    cast_info ci ON a.person_id = ci.person_id
JOIN 
    title t ON ci.movie_id = t.id
JOIN 
    role_type r ON ci.role_id = r.id
JOIN 
    movie_companies mc ON t.id = mc.movie_id
JOIN 
    company_name c ON mc.company_id = c.id
LEFT JOIN 
    movie_info m ON t.id = m.movie_id
LEFT JOIN 
    movie_keyword mk ON t.id = mk.movie_id
LEFT JOIN 
    keyword kw ON mk.keyword_id = kw.id
WHERE 
    a.name LIKE '%Doe%'
    AND t.production_year BETWEEN 2000 AND 2023
ORDER BY 
    t.production_year DESC, a.name;
