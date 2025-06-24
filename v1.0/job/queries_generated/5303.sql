SELECT 
    a.name AS actor_name, 
    t.title AS movie_title, 
    t.production_year, 
    c.kind AS company_type, 
    r.role AS role_type
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
    movie_keyword mk ON t.id = mk.movie_id
JOIN 
    keyword k ON mk.keyword_id = k.id
JOIN 
    complete_cast cc ON t.id = cc.movie_id
JOIN 
    role_type r ON ci.role_id = r.id
WHERE 
    t.production_year BETWEEN 2000 AND 2020
    AND k.keyword ILIKE '%action%'
ORDER BY 
    t.production_year DESC, 
    a.name;
