-- Performance benchmarking query selecting titles and the names of actors from the joined tables
SELECT
    t.title,
    a.name AS actor_name,
    t.production_year,
    COUNT(c.id) AS total_cast_members
FROM
    title t
JOIN
    movie_companies mc ON t.id = mc.movie_id
JOIN
    company_name cn ON mc.company_id = cn.id
JOIN
    cast_info c ON t.id = c.movie_id
JOIN
    aka_name a ON c.person_id = a.person_id
WHERE
    t.production_year >= 2000
GROUP BY
    t.id, a.name
ORDER BY
    t.production_year DESC, total_cast_members DESC;
