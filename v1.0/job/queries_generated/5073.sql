SELECT 
    t.title AS movie_title, 
    a.name AS actor_name, 
    ct.kind AS cast_type, 
    c.name AS company_name, 
    k.keyword AS movie_keyword, 
    mi.info AS movie_info 
FROM 
    title t 
JOIN 
    complete_cast cc ON t.id = cc.movie_id 
JOIN 
    cast_info ci ON ci.movie_id = cc.movie_id 
JOIN 
    aka_name a ON a.person_id = ci.person_id 
JOIN 
    comp_cast_type ct ON ci.person_role_id = ct.id 
JOIN 
    movie_companies mc ON mc.movie_id = t.id 
JOIN 
    company_name c ON mc.company_id = c.id 
JOIN 
    movie_keyword mk ON mk.movie_id = t.id 
JOIN 
    keyword k ON mk.keyword_id = k.id 
JOIN 
    movie_info mi ON mi.movie_id = t.id 
WHERE 
    t.production_year BETWEEN 2000 AND 2023 
AND 
    a.name IS NOT NULL 
AND 
    k.keyword IS NOT NULL 
ORDER BY 
    t.title, a.name, c.name;
