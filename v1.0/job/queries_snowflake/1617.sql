
WITH RankedMovies AS (
    SELECT 
        a.title AS movie_title,
        COUNT(DISTINCT c.person_id) AS cast_count,
        AVG(CASE WHEN co.kind IS NOT NULL THEN 1 ELSE 0 END) AS avg_companies,
        ROW_NUMBER() OVER (PARTITION BY a.production_year ORDER BY COUNT(DISTINCT c.person_id) DESC) AS rank_by_cast,
        a.production_year
    FROM 
        aka_title a
    LEFT JOIN 
        complete_cast cc ON a.id = cc.movie_id
    LEFT JOIN 
        cast_info c ON cc.subject_id = c.id
    LEFT JOIN 
        movie_companies mc ON a.id = mc.movie_id
    LEFT JOIN 
        company_type co ON mc.company_type_id = co.id
    WHERE 
        a.production_year IS NOT NULL
    GROUP BY 
        a.id, a.title, a.production_year
),
FilteredMovies AS (
    SELECT 
        rm.movie_title,
        rm.cast_count,
        rm.avg_companies,
        rm.production_year,
        rm.rank_by_cast
    FROM 
        RankedMovies rm
    WHERE 
        rm.rank_by_cast <= 10
)
SELECT 
    fm.movie_title,
    fm.cast_count,
    fm.avg_companies,
    CASE 
        WHEN fm.production_year BETWEEN 2000 AND 2020 THEN '21st Century' 
        ELSE 'Earlier'
    END AS production_age,
    (SELECT COUNT(*) FROM movie_keyword mk WHERE mk.movie_id IN (SELECT id FROM aka_title WHERE title = fm.movie_title)) AS keyword_count
FROM 
    FilteredMovies fm
ORDER BY 
    fm.production_year DESC, fm.cast_count DESC;
