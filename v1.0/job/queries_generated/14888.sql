SELECT 
    a.name AS aka_name, 
    t.title AS movie_title, 
    c.note AS cast_note, 
    co.name AS company_name, 
    it.info AS movie_info
FROM 
    aka_name a
JOIN 
    cast_info c ON a.person_id = c.person_id
JOIN 
    aka_title t ON c.movie_id = t.movie_id
JOIN 
    movie_companies mc ON t.movie_id = mc.movie_id
JOIN 
    company_name co ON mc.company_id = co.id
JOIN 
    movie_info mi ON t.movie_id = mi.movie_id
JOIN 
    info_type it ON mi.info_type_id = it.id
WHERE 
    t.production_year > 2000
ORDER BY 
    t.production_year DESC;
