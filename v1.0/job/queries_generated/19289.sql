SELECT
    t.title,
    a.name AS actor_name,
    ci.kind AS role_type
FROM
    title t
JOIN
    movie_companies mc ON t.id = mc.movie_id
JOIN
    company_name cn ON mc.company_id = cn.id
JOIN
    complete_cast cc ON t.id = cc.movie_id
JOIN
    cast_info ci ON cc.subject_id = ci.id
JOIN
    aka_name a ON ci.person_id = a.person_id
WHERE
    t.production_year > 2000
ORDER BY
    t.production_year DESC;
