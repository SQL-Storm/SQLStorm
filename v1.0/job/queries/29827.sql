WITH MovieDetails AS (
    SELECT 
        t.id AS movie_id,
        t.title,
        t.production_year,
        co.name AS company_name,
        k.keyword,
        COUNT(c.id) AS cast_count
    FROM 
        aka_title t
    JOIN 
        movie_companies mc ON t.id = mc.movie_id
    JOIN 
        company_name co ON mc.company_id = co.id
    LEFT JOIN 
        movie_keyword mk ON t.id = mk.movie_id
    LEFT JOIN 
        keyword k ON mk.keyword_id = k.id
    LEFT JOIN 
        complete_cast cc ON t.id = cc.movie_id
    LEFT JOIN 
        cast_info c ON cc.subject_id = c.person_id
    GROUP BY 
        t.id, t.title, t.production_year, co.name, k.keyword
),

DetailedAkaNames AS (
    SELECT 
        ak.person_id,
        ak.name AS aka_name,
        n.name AS real_name,
        ak.surname_pcode,
        ak.md5sum AS aka_md5
    FROM 
        aka_name ak
    JOIN 
        name n ON ak.person_id = n.imdb_id
),

FinalBenchmark AS (
    SELECT 
        md.title,
        md.production_year,
        md.company_name,
        md.keyword,
        md.cast_count,
        d.aka_name,
        d.real_name,
        d.surname_pcode
    FROM 
        MovieDetails md
    LEFT JOIN 
        DetailedAkaNames d ON md.cast_count > 0
    ORDER BY 
        md.production_year DESC, md.cast_count DESC, md.title ASC
)

SELECT 
    title,
    production_year,
    company_name,
    keyword,
    cast_count,
    aka_name,
    real_name,
    surname_pcode
FROM 
    FinalBenchmark
WHERE 
    production_year > 2000
AND 
    cast_count > 5
LIMIT 100;
