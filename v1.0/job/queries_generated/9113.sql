SELECT 
    t.title AS movie_title,
    a.name AS actor_name,
    r.role AS actor_role,
    c.note AS cast_note,
    co.name AS company_name,
    k.keyword AS movie_keyword,
    m.info AS movie_info,
    COUNT(DISTINCT t.id) AS total_movies
FROM 
    title t
JOIN 
    cast_info c ON t.id = c.movie_id
JOIN 
    aka_name a ON c.person_id = a.person_id
JOIN 
    role_type r ON c.role_id = r.id
JOIN 
    movie_companies mc ON t.id = mc.movie_id
JOIN 
    company_name co ON mc.company_id = co.id
LEFT JOIN 
    movie_keyword mk ON t.id = mk.movie_id
LEFT JOIN 
    keyword k ON mk.keyword_id = k.id
LEFT JOIN 
    movie_info m ON t.id = m.movie_id
WHERE 
    t.production_year >= 2000
    AND co.country_code = 'USA'
GROUP BY 
    t.title, a.name, r.role, c.note, co.name, k.keyword, m.info
ORDER BY 
    total_movies DESC, t.title ASC;
