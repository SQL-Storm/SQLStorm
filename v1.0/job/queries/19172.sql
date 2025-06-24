SELECT 
    a.name AS actor_name,
    m.title AS movie_title,
    c.nr_order AS cast_order,
    r.role AS role_name
FROM 
    cast_info c
JOIN 
    aka_name a ON c.person_id = a.person_id
JOIN 
    title m ON c.movie_id = m.id
JOIN 
    role_type r ON c.role_id = r.id
WHERE 
    m.production_year = 2020
ORDER BY 
    c.nr_order;
