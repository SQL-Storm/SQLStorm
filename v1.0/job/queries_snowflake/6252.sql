
WITH RecursiveMovies AS (
    SELECT 
        t.id AS movie_id, 
        t.title, 
        t.production_year, 
        m.name AS company_name,
        LISTAGG(DISTINCT k.keyword, ', ') WITHIN GROUP (ORDER BY k.keyword) AS keywords,
        LISTAGG(DISTINCT a.name, ', ') WITHIN GROUP (ORDER BY a.name) AS actors
    FROM 
        aka_title t
    JOIN 
        movie_companies mc ON t.id = mc.movie_id
    JOIN 
        company_name m ON mc.company_id = m.id
    LEFT JOIN 
        movie_keyword mk ON t.id = mk.movie_id
    LEFT JOIN 
        keyword k ON mk.keyword_id = k.id
    LEFT JOIN 
        cast_info ci ON t.id = ci.movie_id
    LEFT JOIN 
        aka_name a ON ci.person_id = a.person_id
    WHERE 
        t.production_year >= 2000
    GROUP BY 
        t.id, t.title, t.production_year, m.name
),
StandardMovies AS (
    SELECT 
        movie_id, 
        title, 
        production_year, 
        company_name, 
        keywords, 
        actors 
    FROM 
        RecursiveMovies
)
SELECT 
    sm.movie_id, 
    sm.title, 
    sm.production_year, 
    sm.company_name, 
    sm.keywords, 
    sm.actors,
    COUNT(DISTINCT ci.id) AS total_cast_members
FROM 
    StandardMovies sm
LEFT JOIN 
    cast_info ci ON sm.movie_id = ci.movie_id
GROUP BY 
    sm.movie_id, sm.title, sm.production_year, sm.company_name, sm.keywords, sm.actors
ORDER BY 
    sm.production_year DESC, 
    total_cast_members DESC
LIMIT 50;
