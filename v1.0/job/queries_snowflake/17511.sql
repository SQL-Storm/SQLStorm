SELECT a.name AS actor_name, t.title AS movie_title, c.nr_order AS role_order
FROM cast_info c
JOIN aka_name a ON c.person_id = a.person_id
JOIN aka_title t ON c.movie_id = t.movie_id
WHERE t.production_year >= 2000
ORDER BY t.production_year DESC, c.nr_order;
