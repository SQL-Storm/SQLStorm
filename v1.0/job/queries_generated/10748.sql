-- Performance Benchmarking Query

SELECT 
    t.title AS movie_title,
    a.name AS actor_name,
    c.kind AS character_role,
    m.name AS company_name,
    k.keyword AS movie_keyword,
    p.info AS person_info
FROM 
    title t
JOIN 
    movie_companies mc ON t.id = mc.movie_id
JOIN 
    company_name m ON mc.company_id = m.id
JOIN 
    cast_info ci ON t.id = ci.movie_id
JOIN 
    aka_name a ON ci.person_id = a.person_id
JOIN 
    role_type c ON ci.role_id = c.id
JOIN 
    movie_keyword mk ON t.id = mk.movie_id
JOIN 
    keyword k ON mk.keyword_id = k.id
JOIN 
    person_info p ON a.person_id = p.person_id
WHERE 
    t.production_year >= 2000
    AND m.country_code = 'USA'
ORDER BY 
    t.title, a.name;
