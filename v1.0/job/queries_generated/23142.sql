WITH RecursiveMovieCTE AS (
    SELECT 
        mt.id AS movie_id, 
        mt.title, 
        mt.production_year, 
        COALESCE(AVG(CASE WHEN ci.role_id IS NOT NULL THEN 1 END), 0) AS avg_starring_roles,
        COUNT(DISTINCT ci.person_id) AS full_cast_count,
        STRING_AGG(DISTINCT an.name, ', ') AS actors_list
    FROM 
        aka_title mt
    LEFT JOIN 
        cast_info ci ON mt.movie_id = ci.movie_id
    LEFT JOIN 
        aka_name an ON ci.person_id = an.person_id
    GROUP BY 
        mt.id
    HAVING 
        COUNT(DISTINCT ci.person_id) > 5
), FilteredMovies AS (
    SELECT 
        movie_id,
        title,
        production_year,
        avg_starring_roles,
        full_cast_count,
        actors_list
    FROM 
        RecursiveMovieCTE
    WHERE 
        production_year IS NOT NULL AND (production_year < 2000 OR avg_starring_roles > 2)
), MovieKeywordCTE AS (
    SELECT 
        km.movie_id,
        STRING_AGG(DISTINCT k.keyword, ', ') AS keywords
    FROM 
        movie_keyword km
    JOIN 
        keyword k ON km.keyword_id = k.id
    GROUP BY 
        km.movie_id
), FinalMovieInfo AS (
    SELECT 
        fm.movie_id,
        fm.title,
        fm.production_year,
        fm.avg_starring_roles,
        fm.full_cast_count,
        fm.actors_list,
        COALESCE(mk.keywords, 'None') AS keywords
    FROM 
        FilteredMovies fm
    LEFT JOIN 
        MovieKeywordCTE mk ON fm.movie_id = mk.movie_id
)
SELECT 
    f.movie_id,
    f.title,
    f.production_year,
    f.avg_starring_roles,
    f.full_cast_count,
    f.actors_list,
    f.keywords
FROM 
    FinalMovieInfo f
WHERE 
    f.keywords LIKE '%action%' OR f.title LIKE '% thriller%'
ORDER BY 
    CASE 
        WHEN f.avg_starring_roles > 3 THEN 1 
        ELSE 2 
    END, 
    f.production_year DESC;

-- Crafting a statement for additional complexity 
WITH MovieInfoComparative AS (
    SELECT 
        title, 
        production_year, 
        COUNT(DISTINCT actor_id) AS lead_actors_count
    FROM 
        (SELECT 
            mt.title,
            mt.production_year,
            ci.person_id AS actor_id
        FROM 
            aka_title mt
        JOIN 
            cast_info ci ON mt.id = ci.movie_id
        WHERE 
            ci.nr_order < 3 -- considering only lead roles
        ) AS leads
    GROUP BY 
        title, production_year
)
SELECT 
    f.title, 
    f.production_year, 
    f.full_cast_count,
    mic.lead_actors_count
FROM 
    FinalMovieInfo f
LEFT JOIN 
    MovieInfoComparative mic ON f.title = mic.title AND f.production_year = mic.production_year
WHERE 
    mic.lead_actors_count IS NOT NULL
ORDER BY 
    f.full_cast_count DESC, 
    mic.lead_actors_count ASC;
