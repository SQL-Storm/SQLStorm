
SELECT 
    a.name AS actor_name, 
    t.title AS movie_title, 
    c.kind AS cast_type, 
    m.info AS movie_info, 
    STRING_AGG(k.keyword, ', ') AS keywords
FROM 
    aka_name AS a
JOIN 
    cast_info AS ci ON a.person_id = ci.person_id
JOIN 
    aka_title AS t ON ci.movie_id = t.movie_id
JOIN 
    comp_cast_type AS c ON ci.person_role_id = c.id
JOIN 
    complete_cast AS cc ON cc.movie_id = t.id
JOIN 
    movie_info AS m ON m.movie_id = t.id
LEFT JOIN 
    movie_keyword AS mk ON mk.movie_id = t.id
LEFT JOIN 
    keyword AS k ON mk.keyword_id = k.id
WHERE 
    t.production_year BETWEEN 2000 AND 2020
    AND c.kind IN ('actor', 'actress')
GROUP BY 
    a.name, t.title, c.kind, m.info
ORDER BY 
    MAX(t.production_year) DESC, a.name;
