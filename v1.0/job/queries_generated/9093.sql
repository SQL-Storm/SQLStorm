SELECT 
    a.name AS actor_name, 
    t.title AS movie_title, 
    tc.kind AS company_type, 
    k.keyword AS movie_keyword, 
    pi.info AS actor_info 
FROM 
    aka_name a 
JOIN 
    cast_info c ON a.person_id = c.person_id 
JOIN 
    title t ON c.movie_id = t.id 
JOIN 
    movie_companies mc ON t.id = mc.movie_id 
JOIN 
    company_type ct ON mc.company_type_id = ct.id 
JOIN 
    company_name cn ON mc.company_id = cn.id 
JOIN 
    movie_keyword mk ON t.id = mk.movie_id 
JOIN 
    keyword k ON mk.keyword_id = k.id 
LEFT JOIN 
    person_info pi ON a.person_id = pi.person_id 
WHERE 
    t.production_year > 2000 
    AND cn.country_code = 'USA' 
    AND pi.info_type_id = (SELECT id FROM info_type WHERE info = 'birth date') 
ORDER BY 
    t.production_year DESC, 
    a.name ASC;
