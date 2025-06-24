SELECT 
    a.name AS actor_name,
    t.title AS movie_title,
    c.kind AS company_type,
    GROUP_CONCAT(DISTINCT k.keyword) AS keywords,
    YEAR(m.production_year) AS year_of_release
FROM 
    aka_name a
JOIN 
    cast_info ci ON a.person_id = ci.person_id
JOIN 
    title t ON ci.movie_id = t.id
JOIN 
    movie_companies mc ON t.id = mc.movie_id
JOIN 
    company_type c ON mc.company_type_id = c.id
JOIN 
    movie_keyword mk ON t.id = mk.movie_id
JOIN 
    keyword k ON mk.keyword_id = k.id
JOIN 
    complete_cast cc ON t.id = cc.movie_id
JOIN 
    person_info pi ON a.person_id = pi.person_id
WHERE 
    pi.info_type_id = (SELECT id FROM info_type WHERE info = 'Birthdate')
    AND c.kind NOT LIKE '%Distributor%'
GROUP BY 
    a.name, t.title, c.kind, YEAR(m.production_year)
ORDER BY 
    year_of_release DESC, actor_name;
