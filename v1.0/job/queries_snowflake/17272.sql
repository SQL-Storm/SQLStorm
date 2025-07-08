SELECT 
    t.title, 
    n.name, 
    c.note 
FROM 
    title t 
JOIN 
    cast_info c ON t.id = c.movie_id 
JOIN 
    aka_name n ON c.person_id = n.person_id 
WHERE 
    t.production_year = 2020 
ORDER BY 
    t.title;
