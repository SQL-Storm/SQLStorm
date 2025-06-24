WITH movie_data AS (
    SELECT 
        t.id AS movie_id,
        t.title AS movie_title,
        t.production_year,
        ak.name AS actor_name,
        ak.imdb_index AS actor_imdb_index,
        GROUP_CONCAT(DISTINCT kw.keyword) AS keywords
    FROM 
        aka_title t
    JOIN 
        cast_info c ON t.id = c.movie_id
    JOIN 
        aka_name ak ON c.person_id = ak.person_id
    LEFT JOIN 
        movie_keyword mk ON t.id = mk.movie_id
    LEFT JOIN 
        keyword kw ON mk.keyword_id = kw.id
    WHERE 
        t.production_year >= 2000
        AND ak.name IS NOT NULL
    GROUP BY 
        t.id, ak.person_id
),
company_info AS (
    SELECT 
        mc.movie_id,
        GROUP_CONCAT(DISTINCT cn.name) AS company_names,
        GROUP_CONCAT(DISTINCT ct.kind) AS company_types
    FROM 
        movie_companies mc
    JOIN 
        company_name cn ON mc.company_id = cn.id
    JOIN 
        company_type ct ON mc.company_type_id = ct.id
    GROUP BY 
        mc.movie_id
)
SELECT 
    md.movie_id,
    md.movie_title,
    md.production_year,
    md.actor_name,
    md.actor_imdb_index,
    ci.company_names,
    ci.company_types,
    md.keywords
FROM 
    movie_data md
JOIN 
    company_info ci ON md.movie_id = ci.movie_id
ORDER BY 
    md.production_year DESC, 
    md.movie_title ASC
LIMIT 100;
This SQL query benchmarks string processing by extracting detailed information about movies released after 2000, including the titles, production years, involved actors, and their respective companies. It combines data from multiple tables while ensuring distinct results, using aggregation functions for keyword and company information, and sorts the output based on production year and title.
