WITH MovieDetails AS (
    SELECT 
        t.id AS movie_id, 
        t.title, 
        t.production_year, 
        GROUP_CONCAT(DISTINCT k.keyword) AS keywords,
        GROUP_CONCAT(DISTINCT c.name) AS company_names
    FROM title t
    JOIN movie_keyword mk ON t.id = mk.movie_id
    JOIN keyword k ON mk.keyword_id = k.id
    JOIN movie_companies mc ON t.id = mc.movie_id
    JOIN company_name c ON mc.company_id = c.id
    GROUP BY t.id, t.title, t.production_year
),
CastDetails AS (
    SELECT 
        ci.movie_id, 
        COUNT(DISTINCT ci.person_id) AS total_cast, 
        GROUP_CONCAT(DISTINCT ak.name) AS actors
    FROM cast_info ci
    JOIN aka_name ak ON ci.person_id = ak.person_id
    GROUP BY ci.movie_id
)
SELECT 
    md.movie_id,
    md.title,
    md.production_year,
    md.keywords,
    md.company_names,
    cd.total_cast,
    cd.actors
FROM MovieDetails md
LEFT JOIN CastDetails cd ON md.movie_id = cd.movie_id
WHERE md.production_year BETWEEN 2000 AND 2020
ORDER BY md.production_year DESC, md.title;
