SELECT 
    t.title AS movie_title,
    a.name AS actor_name,
    c.kind AS cast_type,
    COUNT(DISTINCT mk.keyword) AS keyword_count,
    COUNT(DISTINCT mi.info) AS info_count,
    AVG(CASE WHEN ct.role IS NOT NULL THEN 1 ELSE 0 END) AS has_role_percentage
FROM 
    aka_title t
JOIN 
    complete_cast cc ON t.id = cc.movie_id
JOIN 
    cast_info ci ON cc.subject_id = ci.id
JOIN 
    aka_name a ON ci.person_id = a.person_id
JOIN 
    movie_keyword mk ON t.id = mk.movie_id
JOIN 
    movie_info mi ON t.id = mi.movie_id
JOIN 
    comp_cast_type c ON ci.person_role_id = c.id
JOIN 
    role_type ct ON ci.role_id = ct.id
WHERE 
    t.production_year >= 2000 
    AND t.kind_id IN (SELECT id FROM kind_type WHERE kind = 'movie')
GROUP BY 
    t.title, a.name, c.kind
HAVING 
    COUNT(DISTINCT mk.keyword) > 2 
ORDER BY 
    keyword_count DESC, movie_title ASC;
