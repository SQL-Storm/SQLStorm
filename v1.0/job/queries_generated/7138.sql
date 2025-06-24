SELECT 
    a.name AS actor_name,
    t.title AS movie_title,
    c.kind AS cast_type,
    co.name AS company_name,
    k.keyword AS associated_keyword,
    mi.info AS movie_info
FROM 
    aka_name a
JOIN 
    cast_info ci ON a.person_id = ci.person_id
JOIN 
    title t ON ci.movie_id = t.id
JOIN 
    movie_companies mc ON t.id = mc.movie_id
JOIN 
    company_name co ON mc.company_id = co.id
JOIN 
    movie_keyword mk ON t.id = mk.movie_id
JOIN 
    keyword k ON mk.keyword_id = k.id
LEFT JOIN 
    movie_info mi ON t.id = mi.movie_id AND mi.info_type_id = (SELECT id FROM info_type WHERE info = 'Synopsis')
WHERE 
    t.production_year >= 2000 
    AND co.country_code = 'USA'
    AND k.keyword ILIKE '%action%'
ORDER BY 
    t.production_year DESC, 
    a.name;
