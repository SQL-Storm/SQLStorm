SELECT 
    a.name AS actor_name, 
    t.title AS movie_title, 
    t.production_year, 
    r.role AS role_type, 
    c.kind AS company_type,
    COUNT(DISTINCT m.id) AS movie_count
FROM 
    aka_name a
JOIN 
    cast_info ci ON a.person_id = ci.person_id
JOIN 
    title t ON ci.movie_id = t.id
JOIN 
    movie_companies mc ON t.id = mc.movie_id
JOIN 
    company_name cn ON mc.company_id = cn.id
JOIN 
    company_type c ON mc.company_type_id = c.id
JOIN 
    role_type r ON ci.role_id = r.id
LEFT JOIN 
    movie_keyword mk ON t.id = mk.movie_id
LEFT JOIN 
    keyword k ON mk.keyword_id = k.id
WHERE 
    a.name IS NOT NULL 
    AND t.production_year >= 2000 
    AND c.kind IS NOT NULL 
GROUP BY 
    a.name, t.title, t.production_year, r.role, c.kind
ORDER BY 
    movie_count DESC, actor_name ASC
LIMIT 100;
