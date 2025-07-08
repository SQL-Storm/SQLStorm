
SELECT 
    a.name AS actor_name,
    t.title AS movie_title,
    c.kind AS company_type,
    LISTAGG(DISTINCT k.keyword, ', ') AS keywords,
    LISTAGG(DISTINCT pi.info, ', ') AS person_infos
FROM 
    cast_info ci
JOIN 
    aka_name a ON ci.person_id = a.person_id
JOIN 
    aka_title t ON ci.movie_id = t.movie_id
JOIN 
    movie_companies mc ON t.id = mc.movie_id
JOIN 
    company_type c ON mc.company_type_id = c.id
LEFT JOIN 
    movie_keyword mk ON t.id = mk.movie_id
LEFT JOIN 
    keyword k ON mk.keyword_id = k.id
LEFT JOIN 
    person_info pi ON a.person_id = pi.person_id
WHERE 
    t.production_year >= 2000 
    AND c.kind LIKE '%studio%'
    AND a.name IS NOT NULL
GROUP BY 
    a.name, t.title, c.kind
ORDER BY 
    actor_name ASC, movie_title ASC;
