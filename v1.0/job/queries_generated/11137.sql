SELECT 
    t.title,
    a.name AS actor_name, 
    k.keyword, 
    c.kind AS company_type, 
    mt.info AS movie_info
FROM 
    title t
JOIN 
    movie_keyword mk ON t.id = mk.movie_id
JOIN 
    keyword k ON mk.keyword_id = k.id
JOIN 
    movie_companies mc ON t.id = mc.movie_id
JOIN 
    company_type c ON mc.company_type_id = c.id
JOIN 
    complete_cast cc ON t.id = cc.movie_id
JOIN 
    aka_name a ON cc.subject_id = a.person_id
JOIN 
    movie_info mt ON t.id = mt.movie_id
WHERE 
    t.production_year >= 2000
ORDER BY 
    t.title;
