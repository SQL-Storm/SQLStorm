SELECT 
    a.name AS actor_name, 
    t.title AS movie_title, 
    t.production_year, 
    GROUP_CONCAT(DISTINCT c.kind ORDER BY c.kind) AS company_types,
    COUNT(k.keyword) AS keyword_count
FROM 
    aka_name a
JOIN 
    cast_info ci ON a.person_id = ci.person_id
JOIN 
    title t ON ci.movie_id = t.id
JOIN 
    movie_companies mc ON t.id = mc.movie_id
JOIN 
    company_type c ON mc.company_type_id = c.id
LEFT JOIN 
    movie_keyword mk ON t.id = mk.movie_id
LEFT JOIN 
    keyword k ON mk.keyword_id = k.id
WHERE 
    a.name IS NOT NULL 
    AND t.production_year >= 2000
GROUP BY 
    a.id, t.id
HAVING 
    COUNT(DISTINCT k.id) > 2
ORDER BY 
    a.name, t.production_year DESC;
