SELECT 
    a.name AS actor_name,
    t.title AS movie_title,
    y.production_year,
    c.kind AS cast_type,
    co.name AS company_name,
    k.keyword AS movie_keyword
FROM 
    aka_name a
JOIN 
    cast_info ci ON a.person_id = ci.person_id
JOIN 
    aka_title t ON ci.movie_id = t.movie_id
JOIN 
    kind_type y ON t.kind_id = y.id
JOIN 
    movie_companies mc ON t.id = mc.movie_id
JOIN 
    company_name co ON mc.company_id = co.id
JOIN 
    movie_keyword mk ON t.id = mk.movie_id
JOIN 
    keyword k ON mk.keyword_id = k.id
ORDER BY 
    y.production_year DESC, a.name ASC;
