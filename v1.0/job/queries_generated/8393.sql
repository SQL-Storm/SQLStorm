SELECT 
    a.name AS actor_name,
    t.title AS movie_title,
    c.kind AS company_type,
    m.info AS movie_info,
    k.keyword AS movie_keyword,
    COUNT(*) AS total_roles 
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
    company_type ct ON mc.company_type_id = ct.id
JOIN 
    movie_info m ON t.id = m.movie_id
JOIN 
    movie_keyword mk ON t.id = mk.movie_id
JOIN 
    keyword k ON mk.keyword_id = k.id
WHERE 
    t.production_year BETWEEN 2000 AND 2023
    AND ct.kind = 'Producer'
GROUP BY 
    a.name, t.title, c.kind, m.info, k.keyword
ORDER BY 
    total_roles DESC
LIMIT 10;
