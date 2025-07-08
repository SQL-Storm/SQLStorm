
SELECT 
    a.name AS actor_name,
    COUNT(DISTINCT mc.movie_id) AS number_of_movies,
    LISTAGG(DISTINCT t.title, ', ') WITHIN GROUP (ORDER BY t.title) AS movie_titles,
    LISTAGG(DISTINCT k.keyword, ', ') WITHIN GROUP (ORDER BY k.keyword) AS keywords_associated,
    LISTAGG(DISTINCT c.kind, ', ') WITHIN GROUP (ORDER BY c.kind) AS company_types,
    LISTAGG(DISTINCT p.info, '; ') WITHIN GROUP (ORDER BY p.info) AS additional_info
FROM 
    aka_name a
JOIN 
    cast_info ci ON a.person_id = ci.person_id
JOIN 
    title t ON ci.movie_id = t.id
JOIN 
    movie_keyword mk ON t.id = mk.movie_id
JOIN 
    keyword k ON mk.keyword_id = k.id
JOIN 
    movie_companies mc ON t.id = mc.movie_id
JOIN 
    company_type c ON mc.company_type_id = c.id
JOIN 
    person_info p ON a.person_id = p.person_id
WHERE 
    a.name IS NOT NULL 
    AND t.production_year >= 2000 
    AND c.kind LIKE 'Production%'
GROUP BY 
    a.name
HAVING 
    COUNT(DISTINCT mc.movie_id) > 5
ORDER BY 
    number_of_movies DESC;
