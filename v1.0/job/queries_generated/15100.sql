SELECT 
    a.name AS aka_name, 
    t.title AS movie_title, 
    c.note AS cast_note
FROM 
    aka_name AS a
JOIN 
    cast_info AS c ON a.person_id = c.person_id
JOIN 
    aka_title AS t ON c.movie_id = t.movie_id
WHERE 
    t.production_year > 2000
ORDER BY 
    t.title;
