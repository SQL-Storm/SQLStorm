WITH RankedMovies AS (
    SELECT 
        t.id AS title_id,
        t.title,
        t.production_year,
        COUNT(c.id) AS cast_count,
        ROW_NUMBER() OVER (PARTITION BY t.production_year ORDER BY COUNT(c.id) DESC) AS rank
    FROM title t
    LEFT JOIN cast_info c ON t.id = c.movie_id
    GROUP BY t.id, t.title, t.production_year
),
NoteworthyCompanies AS (
    SELECT 
        mc.movie_id,
        STRING_AGG(DISTINCT cn.name, ', ') AS company_names,
        COUNT(mc.id) AS company_count
    FROM movie_companies mc
    JOIN company_name cn ON mc.company_id = cn.id
    WHERE cn.country_code IS NOT NULL
    GROUP BY mc.movie_id
),
KeywordInfo AS (
    SELECT 
        mk.movie_id,
        STRING_AGG(DISTINCT k.keyword, ', ') AS keywords
    FROM movie_keyword mk
    JOIN keyword k ON mk.keyword_id = k.id
    GROUP BY mk.movie_id
)
SELECT 
    rm.title_id,
    rm.title,
    rm.production_year,
    COALESCE(nc.company_names, 'No Companies') AS company_names,
    rm.cast_count,
    COALESCE(ki.keywords, 'No Keywords') AS keywords,
    CASE 
        WHEN rm.cast_count > 10 THEN 'Large Ensemble'
        WHEN rm.cast_count BETWEEN 5 AND 10 THEN 'Medium Ensemble'
        ELSE 'Small Cast'
    END AS cast_size_category
FROM RankedMovies rm
LEFT JOIN NoteworthyCompanies nc ON rm.title_id = nc.movie_id
LEFT JOIN KeywordInfo ki ON rm.title_id = ki.movie_id
WHERE rm.rank <= 5
ORDER BY rm.production_year DESC, rm.cast_count DESC;
