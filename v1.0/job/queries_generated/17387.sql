SELECT 
    a.name AS actor_name,
    t.title AS movie_title,
    ci.note AS role_note
FROM 
    cast_info ci
JOIN 
    aka_name a ON ci.person_id = a.person_id
JOIN 
    aka_title t ON ci.movie_id = t.movie_id
WHERE 
    t.production_year = 2020;
