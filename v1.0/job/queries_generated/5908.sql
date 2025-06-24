SELECT 
    a.name AS actor_name,
    t.title AS movie_title,
    t.production_year,
    c.kind AS cast_role,
    co.name AS company_name,
    k.keyword AS movie_keyword,
    m.info AS movie_info
FROM 
    aka_name a
JOIN 
    cast_info ci ON a.person_id = ci.person_id
JOIN 
    title t ON ci.movie_id = t.id
JOIN 
    role_type c ON ci.role_id = c.id
JOIN 
    movie_companies mc ON t.id = mc.movie_id
JOIN 
    company_name co ON mc.company_id = co.id
JOIN 
    movie_keyword mk ON t.id = mk.movie_id
JOIN 
    keyword k ON mk.keyword_id = k.id
JOIN 
    movie_info mi ON t.id = mi.movie_id
WHERE 
    t.production_year > 2000
    AND co.country_code = 'USA'
    AND k.keyword LIKE '%action%'
ORDER BY 
    t.production_year DESC, 
    actor_name ASC;
