SELECT 
    a.name AS actor_name,
    t.title AS movie_title,
    c.kind AS cast_type,
    i.info AS movie_info,
    GROUP_CONCAT(k.keyword) AS keywords
FROM aka_name a
JOIN cast_info ci ON a.person_id = ci.person_id
JOIN title t ON ci.movie_id = t.id
JOIN comp_cast_type c ON ci.person_role_id = c.id
LEFT JOIN movie_info mi ON t.id = mi.movie_id AND mi.info_type_id = (SELECT id FROM info_type WHERE info='rating')
LEFT JOIN movie_keyword mk ON t.id = mk.movie_id
LEFT JOIN keyword k ON mk.keyword_id = k.id
WHERE t.production_year > 2000
AND c.kind = 'actor'
GROUP BY a.name, t.title, c.kind, i.info
ORDER BY t.production_year DESC, a.name;
