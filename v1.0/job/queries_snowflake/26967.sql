
WITH RankedMovies AS (
    SELECT
        at.movie_id,
        at.title,
        at.production_year,
        ROW_NUMBER() OVER (PARTITION BY at.production_year ORDER BY at.title) AS title_rank
    FROM
        aka_title at
    JOIN
        movie_keyword mk ON at.movie_id = mk.movie_id
    JOIN
        keyword k ON mk.keyword_id = k.id
    WHERE
        k.keyword ILIKE '%comedy%'
), 
FilteredCast AS (
    SELECT
        ci.movie_id,
        c.name AS actor_name,
        pt.role AS character_name,
        ROW_NUMBER() OVER (PARTITION BY ci.movie_id ORDER BY ci.nr_order) AS actor_rank
    FROM
        cast_info ci
    JOIN
        aka_name c ON ci.person_id = c.person_id
    JOIN
        role_type pt ON ci.role_id = pt.id
    WHERE
        pt.role ILIKE '%lead%'
), 
MovieDetails AS (
    SELECT
        rm.movie_id,
        rm.title,
        rm.production_year,
        fc.actor_name,
        fc.character_name,
        rm.title_rank,
        fc.actor_rank
    FROM
        RankedMovies rm
    LEFT JOIN
        FilteredCast fc ON rm.movie_id = fc.movie_id
)
SELECT
    md.movie_id,
    md.title,
    md.production_year,
    LISTAGG(DISTINCT md.actor_name, ', ') AS lead_actors,
    LISTAGG(DISTINCT md.character_name, ', ') AS lead_characters
FROM
    MovieDetails md
GROUP BY
    md.movie_id, md.title, md.production_year
HAVING
    COUNT(md.actor_name) >= 2
ORDER BY
    md.production_year DESC, md.title;
