SELECT 
    t.title AS movie_title,
    a.name AS actor_name,
    p.info AS person_info,
    c.kind AS cast_type,
    m.info AS movie_info
FROM 
    title t
JOIN 
    movie_link ml ON t.id = ml.movie_id
JOIN 
    title linked ON ml.linked_movie_id = linked.id
JOIN 
    movie_companies mc ON t.id = mc.movie_id
JOIN 
    company_name cn ON mc.company_id = cn.id
JOIN 
    cast_info ci ON t.id = ci.movie_id
JOIN 
    aka_name a ON ci.person_id = a.person_id
JOIN 
    role_type r ON ci.role_id = r.id
JOIN 
    person_info p ON a.person_id = p.person_id
JOIN 
    comp_cast_type c ON ci.person_role_id = c.id
JOIN 
    movie_info m ON t.id = m.movie_id
WHERE 
    t.production_year > 2000
ORDER BY 
    t.production_year DESC, a.name ASC;
