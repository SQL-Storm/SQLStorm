SELECT
    t.title,
    a.name AS actor_name,
    c.kind AS company_type,
    kw.keyword
FROM
    title t
JOIN
    movie_info mi ON t.id = mi.movie_id
JOIN
    movie_companies mc ON t.id = mc.movie_id
JOIN
    company_type c ON mc.company_type_id = c.id
JOIN
    movie_keyword mk ON t.id = mk.movie_id
JOIN
    keyword kw ON mk.keyword_id = kw.id
JOIN
    complete_cast cc ON t.id = cc.movie_id
JOIN
    cast_info ci ON cc.subject_id = ci.id
JOIN
    aka_name a ON ci.person_id = a.person_id
WHERE
    t.production_year > 2000
ORDER BY
    t.title, a.name;
