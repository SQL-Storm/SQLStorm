SELECT 
    a.name AS aka_name,
    t.title AS title,
    c.note AS cast_note,
    co.name AS company_name,
    ki.keyword AS movie_keyword,
    p.info AS person_info
FROM 
    aka_name AS a
JOIN 
    cast_info AS c ON a.person_id = c.person_id
JOIN 
    aka_title AS t ON c.movie_id = t.movie_id
JOIN 
    movie_companies AS mc ON t.id = mc.movie_id
JOIN 
    company_name AS co ON mc.company_id = co.id
JOIN 
    movie_keyword AS mk ON t.id = mk.movie_id
JOIN 
    keyword AS ki ON mk.keyword_id = ki.id
JOIN 
    person_info AS p ON a.person_id = p.person_id
WHERE 
    t.production_year > 2000
ORDER BY 
    a.name, t.title;
