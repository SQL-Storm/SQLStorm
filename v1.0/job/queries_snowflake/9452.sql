SELECT 
    a.name AS actor_name, 
    t.title AS movie_title, 
    c.kind AS company_type, 
    k.keyword AS movie_keyword, 
    pi.info AS person_info 
FROM 
    title t 
JOIN 
    complete_cast cc ON t.id = cc.movie_id 
JOIN 
    cast_info ci ON cc.subject_id = ci.id 
JOIN 
    aka_name a ON ci.person_id = a.person_id 
JOIN 
    movie_companies mc ON t.id = mc.movie_id 
JOIN 
    company_type c ON mc.company_type_id = c.id 
LEFT JOIN 
    movie_keyword mk ON t.id = mk.movie_id 
LEFT JOIN 
    keyword k ON mk.keyword_id = k.id 
LEFT JOIN 
    person_info pi ON ci.person_id = pi.person_id 
WHERE 
    t.production_year > 2000 
    AND c.kind LIKE 'Production%' 
    AND pi.info_type_id IN (SELECT id FROM info_type WHERE info LIKE '%award%') 
ORDER BY 
    t.production_year DESC, 
    a.name;
