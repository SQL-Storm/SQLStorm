
SELECT 
    a.name AS actor_name,
    t.title AS movie_title,
    t.production_year,
    LISTAGG(DISTINCT k.keyword, ', ') WITHIN GROUP (ORDER BY k.keyword) AS keywords,
    c.kind AS company_kind,
    n.gender AS actor_gender
FROM 
    aka_name a
JOIN 
    cast_info ci ON a.person_id = ci.person_id
JOIN 
    title t ON ci.movie_id = t.id
JOIN 
    movie_keyword mk ON t.id = mk.movie_id
JOIN 
    keyword k ON mk.keyword_id = k.id
JOIN 
    movie_companies mc ON t.id = mc.movie_id
JOIN 
    company_name cn ON mc.company_id = cn.id
JOIN 
    company_type c ON mc.company_type_id = c.id
JOIN 
    name n ON a.person_id = n.imdb_id
WHERE 
    t.production_year >= 2000
    AND c.kind LIKE 'Producer%'
GROUP BY 
    a.name, t.title, t.production_year, c.kind, n.gender
ORDER BY 
    t.production_year DESC, a.name;
