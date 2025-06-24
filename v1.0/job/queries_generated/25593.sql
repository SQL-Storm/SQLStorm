SELECT 
    a.name AS actor_name,
    t.title AS movie_title,
    t.production_year,
    r.role AS role_name,
    c.kind AS company_type,
    STRING_AGG(DISTINCT k.keyword, ', ') AS keywords,
    COUNT(DISTINCT m.id) AS movie_count
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
    company_type c ON mc.company_type_id = c.id
LEFT JOIN 
    movie_keyword mk ON t.id = mk.movie_id
LEFT JOIN 
    keyword k ON mk.keyword_id = k.id
LEFT JOIN 
    movie_info mi ON t.id = mi.movie_id 
WHERE 
    a.name IS NOT NULL
    AND t.production_year >= 2000
    AND (mi.info_type_id IS NULL OR mi.info_type_id IN 
        (SELECT id FROM info_type WHERE info LIKE '%director%'))
GROUP BY 
    actor_name, movie_title, t.production_year, role_name, company_type
ORDER BY 
    movie_count DESC, actor_name
LIMIT 100;
