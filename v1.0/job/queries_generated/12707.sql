SELECT t.title, a.name AS actor_name, c.note AS cast_note, m.name AS company_name, k.keyword
FROM title t
JOIN aka_title at ON t.id = at.movie_id
JOIN cast_info c ON at.movie_id = c.movie_id
JOIN aka_name a ON c.person_id = a.person_id
JOIN movie_companies mc ON t.id = mc.movie_id
JOIN company_name m ON mc.company_id = m.id
JOIN movie_keyword mk ON t.id = mk.movie_id
JOIN keyword k ON mk.keyword_id = k.id
WHERE t.production_year >= 2000
ORDER BY t.production_year DESC, a.name;
