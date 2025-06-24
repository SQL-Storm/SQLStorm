SELECT 
    ak.name AS aka_name,
    t.title AS movie_title,
    c.role_id,
    p.info AS person_info,
    k.keyword AS movie_keyword,
    cn.name AS company_name,
    ct.kind AS company_type
FROM 
    aka_name ak
JOIN 
    cast_info c ON ak.person_id = c.person_id
JOIN 
    title t ON c.movie_id = t.id
JOIN 
    person_info p ON ak.person_id = p.person_id
JOIN 
    movie_keyword mk ON t.id = mk.movie_id
JOIN 
    keyword k ON mk.keyword_id = k.id
JOIN 
    movie_companies mc ON t.id = mc.movie_id
JOIN 
    company_name cn ON mc.company_id = cn.id
JOIN 
    company_type ct ON mc.company_type_id = ct.id
WHERE 
    t.production_year > 2000
    AND k.keyword LIKE '%action%'
ORDER BY 
    t.production_year DESC, ak.name;
