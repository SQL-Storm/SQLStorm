
WITH RankedMovies AS (
    SELECT 
        t.title,
        t.production_year,
        t.kind_id,
        RANK() OVER (PARTITION BY t.production_year ORDER BY t.title) AS title_rank,
        COUNT(DISTINCT ci.person_id) AS cast_count
    FROM 
        aka_title t
    JOIN 
        movie_companies mc ON t.id = mc.movie_id
    JOIN 
        cast_info ci ON t.id = ci.movie_id
    GROUP BY 
        t.title, t.production_year, t.kind_id
),
FilteredMovies AS (
    SELECT 
        rm.title,
        rm.production_year,
        rm.cast_count,
        CASE 
            WHEN rm.production_year < 2000 THEN 'Classic'
            WHEN rm.production_year BETWEEN 2000 AND 2010 THEN 'Modern'
            ELSE 'Contemporary'
        END AS era
    FROM 
        RankedMovies rm
    WHERE 
        rm.cast_count > 10
),
MovieKeywords AS (
    SELECT 
        mk.movie_id, 
        LISTAGG(k.keyword, ', ') WITHIN GROUP (ORDER BY k.keyword) AS keywords
    FROM 
        movie_keyword mk
    JOIN 
        keyword k ON mk.keyword_id = k.id
    GROUP BY 
        mk.movie_id
),
CombinedData AS (
    SELECT 
        fm.title, 
        fm.production_year, 
        fm.era, 
        COALESCE(mk.keywords, 'No Keywords') AS keywords,
        COALESCE(mv.info, 'No Info') AS movie_info
    FROM 
        FilteredMovies fm
    LEFT JOIN 
        MovieKeywords mk ON fm.production_year = (SELECT production_year FROM aka_title WHERE id = mk.movie_id)
    LEFT JOIN (
        SELECT 
            m.movie_id, 
            m.info
        FROM 
            movie_info m
        WHERE 
            m.note IS NULL AND 
            (m.info_type_id = (SELECT id FROM info_type WHERE info = 'Synopsis'))
    ) mv ON fm.production_year = (SELECT production_year FROM aka_title WHERE id = mv.movie_id)
)
SELECT 
    cd.title,
    cd.production_year,
    cd.era,
    cd.keywords,
    CASE 
        WHEN cd.keywords LIKE '%action%' THEN 'Action Packed!'
        WHEN cd.keywords LIKE '%drama%' THEN 'Dramatic Flair!'
        ELSE 'Unique Genre'
    END AS genre_flair
FROM 
    CombinedData cd
WHERE 
    cd.production_year IS NOT NULL 
    AND (cd.keywords IS NOT NULL OR cd.keywords <> 'No Keywords')
ORDER BY 
    cd.production_year DESC, 
    cd.title ASC
LIMIT 50;
