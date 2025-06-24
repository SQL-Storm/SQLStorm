SELECT 
    a.name AS actor_name, 
    t.title AS movie_title, 
    c.kind AS company_type, 
    COUNT(DISTINCT kw.keyword) AS keyword_count, 
    COUNT(DISTINCT pi.info) AS personal_info_count
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
    keyword kw ON mk.keyword_id = kw.id
LEFT JOIN 
    person_info pi ON a.person_id = pi.person_id
GROUP BY 
    a.name, t.title, c.kind
HAVING 
    COUNT(DISTINCT kw.keyword) > 3 AND COUNT(DISTINCT pi.info) > 2
ORDER BY 
    actor_name, movie_title;
