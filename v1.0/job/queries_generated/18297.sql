SELECT 
    t.title,
    a.name AS actor_name,
    c.kind AS character_name,
    m.production_year
FROM 
    title t
JOIN 
    movie_companies mc ON t.id = mc.movie_id
JOIN 
    company_name cn ON mc.company_id = cn.id
JOIN 
    complete_cast cc ON t.id = cc.movie_id
JOIN 
    cast_info ci ON cc.subject_id = ci.person_id
JOIN 
    aka_name a ON ci.person_id = a.person_id
JOIN 
    char_name c ON a.id = c.id
WHERE 
    t.production_year >= 2000
ORDER BY 
    t.production_year DESC;
