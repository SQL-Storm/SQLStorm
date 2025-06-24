SELECT 
    ak.name AS aka_name,
    t.title AS movie_title,
    r.role AS role,
    c.note AS cast_note,
    comp.name AS company_name,
    info.info AS movie_info,
    k.keyword AS movie_keyword
FROM 
    aka_name ak
JOIN 
    cast_info c ON ak.person_id = c.person_id
JOIN 
    title t ON c.movie_id = t.id
JOIN 
    role_type r ON c.role_id = r.id
JOIN 
    movie_companies mc ON t.id = mc.movie_id
JOIN 
    company_name comp ON mc.company_id = comp.id
JOIN 
    movie_info mi ON t.id = mi.movie_id
JOIN 
    info_type it ON mi.info_type_id = it.id
JOIN 
    movie_keyword mk ON t.id = mk.movie_id
JOIN 
    keyword k ON mk.keyword_id = k.id
WHERE 
    ak.name LIKE '%Smith%'
    AND t.production_year BETWEEN 2000 AND 2022
    AND comp.country_code = 'USA'
ORDER BY 
    t.production_year DESC, ak.name;
