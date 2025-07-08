SELECT 
    a.name AS actor_name,
    t.title AS movie_title,
    c.kind AS company_type,
    ci.note AS cast_note,
    COUNT(mk.id) AS keyword_count
FROM 
    aka_name a
JOIN 
    cast_info ci ON a.person_id = ci.person_id
JOIN 
    aka_title t ON ci.movie_id = t.movie_id
JOIN 
    movie_companies mc ON t.id = mc.movie_id
JOIN 
    company_type c ON mc.company_type_id = c.id
LEFT JOIN 
    movie_keyword mk ON t.id = mk.movie_id
WHERE 
    t.production_year >= 2000
AND 
    ci.nr_order < 3
GROUP BY 
    a.name, t.title, c.kind, ci.note
ORDER BY 
    keyword_count DESC, a.name ASC;
