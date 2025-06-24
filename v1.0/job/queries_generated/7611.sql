SELECT 
    a.name AS actor_name,
    t.title AS movie_title,
    t.production_year AS year,
    GROUP_CONCAT(DISTINCT k.keyword) AS keywords,
    c.kind AS company_type,
    pi.info AS personal_info
FROM 
    aka_name a 
JOIN 
    cast_info ci ON a.person_id = ci.person_id 
JOIN 
    title t ON ci.movie_id = t.id 
JOIN 
    movie_keyword mk ON t.id = mk.movie_id 
JOIN 
    keyword k ON mk.keyword_id = k.id 
JOIN 
    movie_companies mc ON t.id = mc.movie_id 
JOIN 
    company_type c ON mc.company_type_id = c.id 
LEFT JOIN 
    person_info pi ON a.person_id = pi.person_id 
WHERE 
    c.kind LIKE '%Production%'
    AND t.production_year >= 2000 
    AND pi.info_type_id IN (SELECT id FROM info_type WHERE info LIKE '%biography%')
GROUP BY 
    a.name, t.title, t.production_year, c.kind, pi.info 
ORDER BY 
    t.production_year DESC, a.name;
