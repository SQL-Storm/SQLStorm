
SELECT 
    a.name AS actor_name, 
    t.title AS movie_title, 
    t.production_year, 
    LISTAGG(DISTINCT k.keyword, ', ') WITHIN GROUP (ORDER BY k.keyword) AS keywords, 
    c.kind AS cast_type,
    p.info AS person_info
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
    comp_cast_type c ON ci.person_role_id = c.id
JOIN 
    person_info p ON a.person_id = p.person_id
WHERE 
    t.production_year > 2000 
    AND c.kind = 'actor'
GROUP BY 
    a.name, t.title, t.production_year, c.kind, p.info
ORDER BY 
    t.production_year DESC, a.name;
