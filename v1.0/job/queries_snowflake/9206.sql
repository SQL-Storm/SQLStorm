
SELECT 
    a.name AS actor_name,
    t.title AS movie_title,
    t.production_year,
    c.kind AS cast_type,
    LISTAGG(DISTINCT k.keyword, ', ') WITHIN GROUP (ORDER BY k.keyword) AS keywords
FROM 
    aka_name a
JOIN 
    cast_info ci ON a.person_id = ci.person_id
JOIN 
    title t ON ci.movie_id = t.id
JOIN 
    comp_cast_type c ON ci.person_role_id = c.id
JOIN 
    movie_keyword mk ON t.id = mk.movie_id
JOIN 
    keyword k ON mk.keyword_id = k.id
WHERE 
    t.production_year >= 2000
AND 
    c.kind = 'lead actor'
GROUP BY 
    a.name, t.title, t.production_year, c.kind
ORDER BY 
    t.production_year DESC, a.name;
