SELECT 
    t.title AS movie_title,
    a.name AS actor_name,
    GROUP_CONCAT(DISTINCT k.keyword ORDER BY k.keyword ASC) AS keywords,
    c.kind AS company_type,
    m.info AS movie_info
FROM 
    title t
JOIN 
    cast_info ci ON t.id = ci.movie_id
JOIN 
    aka_name a ON ci.person_id = a.person_id
JOIN 
    movie_companies mc ON t.id = mc.movie_id
JOIN 
    company_type c ON mc.company_type_id = c.id
LEFT JOIN 
    movie_keyword mk ON t.id = mk.movie_id
LEFT JOIN 
    keyword k ON mk.keyword_id = k.id
LEFT JOIN 
    movie_info m ON t.id = m.movie_id AND m.info_type_id IN (SELECT id FROM info_type WHERE info IN ('summary', 'rating'))
WHERE 
    t.production_year >= 2000 
    AND a.name IS NOT NULL 
    AND m.info IS NOT NULL
GROUP BY 
    t.id, a.name, c.kind, m.info
ORDER BY 
    t.title, a.name;
