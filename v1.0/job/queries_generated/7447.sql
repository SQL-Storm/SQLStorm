SELECT
    t.title AS movie_title,
    a.name AS actor_name,
    ct.kind AS cast_type,
    c.name AS company_name,
    ki.keyword AS movie_keyword,
    mi.info AS movie_info
FROM
    title t
JOIN
    complete_cast cc ON t.id = cc.movie_id
JOIN
    cast_info ci ON cc.subject_id = ci.id
JOIN
    aka_name a ON ci.person_id = a.person_id
JOIN
    movie_companies mc ON t.id = mc.movie_id
JOIN
    company_name c ON mc.company_id = c.id
JOIN
    movie_keyword mk ON t.id = mk.movie_id
JOIN
    keyword ki ON mk.keyword_id = ki.id
LEFT JOIN
    movie_info mi ON t.id = mi.movie_id
LEFT JOIN
    role_type rt ON ci.role_id = rt.id
LEFT JOIN
    info_type it ON mi.info_type_id = it.id
WHERE
    t.production_year >= 2000
    AND ci.nr_order <= 5
    AND c.country_code = 'USA'
ORDER BY
    t.production_year DESC,
    a.name ASC;
