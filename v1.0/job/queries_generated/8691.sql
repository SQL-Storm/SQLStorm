SELECT
    a.name AS actor_name,
    t.title AS movie_title,
    c.kind AS cast_type,
    co.name AS company_name,
    COUNT(DISTINCT k.keyword) AS keyword_count
FROM
    aka_name a
JOIN
    cast_info ci ON a.person_id = ci.person_id
JOIN
    title t ON ci.movie_id = t.id
JOIN
    movie_companies mc ON t.id = mc.movie_id
JOIN
    company_name co ON mc.company_id = co.id
JOIN
    movie_keyword mk ON t.id = mk.movie_id
JOIN
    keyword k ON mk.keyword_id = k.id
JOIN
    role_type r ON ci.role_id = r.id
WHERE
    t.production_year >= 2000
    AND co.country_code = 'USA'
GROUP BY
    a.name,
    t.title,
    c.kind,
    co.name
ORDER BY
    keyword_count DESC,
    actor_name ASC;
