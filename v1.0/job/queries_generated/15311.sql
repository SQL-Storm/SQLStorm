SELECT 
    a.name AS aka_name,
    t.title AS movie_title,
    c.nr_order AS cast_order,
    r.role AS role_name
FROM 
    aka_name AS a
JOIN 
    cast_info AS c ON a.person_id = c.person_id
JOIN 
    title AS t ON c.movie_id = t.id
JOIN 
    role_type AS r ON c.role_id = r.id
WHERE 
    t.production_year > 2000
ORDER BY 
    t.production_year DESC, 
    c.nr_order;
