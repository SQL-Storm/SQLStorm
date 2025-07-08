
SELECT 
    a.name AS actor_name,
    t.title AS movie_title,
    c.kind AS cast_kind,
    k.keyword AS movie_keyword,
    LISTAGG(ci.note, ', ') AS role_notes
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
    t.kind_id IN (SELECT id FROM kind_type WHERE kind IN ('feature', 'short'))
GROUP BY 
    a.name, t.title, c.kind, k.keyword
ORDER BY 
    a.name ASC, t.title ASC;
