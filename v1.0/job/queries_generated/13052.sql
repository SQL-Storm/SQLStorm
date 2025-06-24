SELECT 
    t.title, 
    a.name AS actor_name, 
    c.kind AS role_type, 
    ti.info AS movie_info, 
    k.keyword 
FROM 
    title t 
JOIN 
    movie_info ti ON t.id = ti.movie_id 
JOIN 
    movie_keyword mk ON t.id = mk.movie_id 
JOIN 
    keyword k ON mk.keyword_id = k.id 
JOIN 
    complete_cast cc ON t.id = cc.movie_id 
JOIN 
    cast_info ci ON cc.subject_id = ci.id 
JOIN 
    aka_name a ON ci.person_id = a.person_id 
JOIN 
    comp_cast_type c ON ci.person_role_id = c.id 
WHERE 
    t.production_year >= 2000 
ORDER BY 
    t.production_year DESC, a.name;
