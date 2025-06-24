SELECT
    a.name AS actor_name,
    t.title AS movie_title,
    c.kind AS company_type,
    ci.note AS cast_note,
    mi.info AS movie_info,
    COUNT(DISTINCT k.keyword) AS keyword_count
FROM 
    aka_name a
JOIN 
    cast_info ci ON a.person_id = ci.person_id
JOIN 
    title t ON ci.movie_id = t.id
JOIN 
    movie_companies mc ON t.id = mc.movie_id
JOIN 
    company_type c ON mc.company_type_id = c.id
JOIN 
    movie_info mi ON t.id = mi.movie_id
LEFT JOIN 
    movie_keyword mk ON t.id = mk.movie_id
LEFT JOIN 
    keyword k ON mk.keyword_id = k.id
WHERE 
    t.production_year >= 2000 
    AND mi.info_type_id IN (SELECT id FROM info_type WHERE info LIKE '%plot%')
GROUP BY 
    a.name, t.title, c.kind, ci.note, mi.info
ORDER BY 
    keyword_count DESC, movie_title ASC;
