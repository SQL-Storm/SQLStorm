
SELECT 
    a.name AS actor_name, 
    t.title AS movie_title, 
    LISTAGG(DISTINCT k.keyword, ', ') WITHIN GROUP (ORDER BY k.keyword) AS keywords, 
    c.kind AS company_type, 
    p.info AS person_info
FROM 
    aka_name a 
JOIN 
    cast_info ci ON a.person_id = ci.person_id 
JOIN 
    aka_title t ON ci.movie_id = t.id 
JOIN 
    movie_companies mc ON t.id = mc.movie_id 
JOIN 
    company_name cn ON mc.company_id = cn.id 
JOIN 
    company_type c ON mc.company_type_id = c.id 
JOIN 
    movie_keyword mk ON t.id = mk.movie_id 
JOIN 
    keyword k ON mk.keyword_id = k.id 
JOIN 
    person_info p ON a.person_id = p.person_id 
WHERE 
    a.name LIKE 'A%' 
    AND t.production_year BETWEEN 2000 AND 2020 
GROUP BY 
    a.name, t.title, c.kind, p.info 
ORDER BY 
    a.name, t.title;
