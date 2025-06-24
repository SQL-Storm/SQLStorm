SELECT 
    a.name AS actor_name, 
    t.title AS movie_title, 
    c.kind AS cast_type, 
    p.info AS actor_info, 
    mk.keyword AS movie_keyword,
    co.name AS company_name, 
    ti.info AS movie_info
FROM 
    aka_name a 
JOIN 
    cast_info c ON a.person_id = c.person_id 
JOIN 
    title t ON c.movie_id = t.id 
JOIN 
    movie_info mi ON t.id = mi.movie_id 
JOIN 
    info_type it ON mi.info_type_id = it.id 
JOIN 
    movie_keyword mk ON t.id = mk.movie_id 
JOIN 
    keyword k ON mk.keyword_id = k.id 
JOIN 
    movie_companies mc ON t.id = mc.movie_id 
JOIN 
    company_name co ON mc.company_id = co.id 
JOIN 
    person_info p ON a.person_id = p.person_id 
WHERE 
    it.info = 'Director' 
    AND t.production_year >= 2000 
ORDER BY 
    t.production_year DESC, 
    a.name;
