SELECT
    a.name AS actor_name,
    t.title AS movie_title,
    t.production_year,
    GROUP_CONCAT(DISTINCT k.keyword) AS keywords,
    c.kind AS company_type,
    COUNT(ci.id) AS character_count
FROM
    aka_name a
JOIN
    cast_info ci ON a.person_id = ci.person_id
JOIN
    aka_title t ON ci.movie_id = t.movie_id
JOIN
    movie_companies mc ON t.id = mc.movie_id
JOIN
    company_type c ON mc.company_type_id = c.id
LEFT JOIN
    movie_keyword mk ON t.id = mk.movie_id
LEFT JOIN
    keyword k ON mk.keyword_id = k.id
WHERE
    t.production_year >= 2000
    AND c.kind IS NOT NULL
GROUP BY
    a.name, t.title, t.production_year, c.kind
HAVING
    COUNT(ci.id) > 1
ORDER BY
    t.production_year DESC,
    a.name ASC;
