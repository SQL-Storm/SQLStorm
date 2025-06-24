
SELECT 
    a.name AS actor_name, 
    t.title AS movie_title, 
    t.production_year, 
    r.role AS role_name, 
    ct.kind AS company_kind, 
    STRING_AGG(DISTINCT k.keyword, ', ') AS keywords
FROM 
    aka_name a
JOIN 
    cast_info ci ON a.person_id = ci.person_id
JOIN 
    title t ON ci.movie_id = t.id
JOIN 
    role_type r ON ci.role_id = r.id
JOIN 
    movie_companies mc ON t.id = mc.movie_id
JOIN 
    company_name cn ON mc.company_id = cn.id
JOIN 
    company_type ct ON mc.company_type_id = ct.id
LEFT JOIN 
    movie_keyword mk ON t.id = mk.movie_id
LEFT JOIN 
    keyword k ON mk.keyword_id = k.id
WHERE 
    a.name LIKE '%Smith%' 
    AND t.production_year BETWEEN 2000 AND 2020
GROUP BY 
    a.name, t.title, t.production_year, r.role, ct.kind
ORDER BY 
    t.production_year DESC, a.name;
