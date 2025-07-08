
WITH RankedMovies AS (
    SELECT 
        t.id AS movie_id,
        t.title,
        t.production_year,
        CTE.actor_count,
        ROW_NUMBER() OVER (PARTITION BY t.production_year ORDER BY CTE.actor_count DESC) AS rank
    FROM 
        aka_title t
    LEFT JOIN (
        SELECT 
            c.movie_id,
            COUNT(DISTINCT c.person_id) AS actor_count
        FROM 
            cast_info c
        GROUP BY 
            c.movie_id
    ) AS CTE ON t.id = CTE.movie_id
),
HighlightedMovies AS (
    SELECT 
        rm.*,
        LISTAGG(DISTINCT ak.name, ', ') WITHIN GROUP (ORDER BY ak.name) AS actor_names
    FROM 
        RankedMovies rm
    LEFT JOIN 
        cast_info c ON rm.movie_id = c.movie_id
    LEFT JOIN 
        aka_name ak ON c.person_id = ak.person_id
    GROUP BY 
        rm.movie_id, rm.title, rm.production_year, rm.actor_count, rm.rank
)
SELECT 
    hm.title,
    hm.production_year,
    COALESCE(f.company_name, 'Independent') AS production_company,
    hm.actor_names,
    hm.rank
FROM 
    HighlightedMovies hm
LEFT JOIN (
    SELECT 
        mc.movie_id,
        cn.name AS company_name
    FROM 
        movie_companies mc
    JOIN 
        company_name cn ON mc.company_id = cn.id
    WHERE 
        mc.company_type_id IS NOT NULL
) f ON hm.movie_id = f.movie_id
WHERE 
    (hm.production_year > 2000 AND hm.rank <= 5)
    OR (hm.rank IS NULL AND hm.actor_count > 3)
ORDER BY 
    hm.production_year DESC, hm.rank;
