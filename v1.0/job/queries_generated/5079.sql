SELECT 
    a.name AS actor_name,
    t.title AS movie_title,
    c.kind AS cast_type,
    ci.name AS company_name,
    m.info AS movie_info,
    k.keyword AS movie_keyword
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
    comp_cast_type c ON ci.role_id = c.id
JOIN 
    movie_info m ON t.id = m.movie_id
JOIN 
    movie_keyword mk ON t.id = mk.movie_id
JOIN 
    keyword k ON mk.keyword_id = k.id
WHERE 
    a.name IS NOT NULL 
    AND t.production_year >= 2000 
    AND cn.country_code = 'USA'
ORDER BY 
    t.production_year DESC, a.name;
