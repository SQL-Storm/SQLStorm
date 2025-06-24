SELECT 
    a.name AS actor_name,
    t.title AS movie_title,
    t.production_year,
    GROUP_CONCAT(DISTINCT c.kind SEPARATOR ', ') AS company_types,
    GROUP_CONCAT(DISTINCT k.keyword SEPARATOR ', ') AS keywords,
    COUNT(DISTINCT p.id) AS total_person_info
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
    person_info p ON ci.person_id = p.person_id
WHERE 
    t.production_year >= 2000 
GROUP BY 
    a.id, t.id
ORDER BY 
    t.production_year DESC, actor_name;
