
WITH MovieDetails AS (
    SELECT 
        t.id AS movie_id,
        t.title AS movie_title,
        t.production_year,
        LISTAGG(DISTINCT ak.name, ', ') WITHIN GROUP (ORDER BY ak.name) AS aka_names,
        LISTAGG(DISTINCT c.name, ', ') WITHIN GROUP (ORDER BY c.name) AS cast_names,
        LISTAGG(DISTINCT k.keyword, ', ') WITHIN GROUP (ORDER BY k.keyword) AS keywords
    FROM 
        aka_title t
    LEFT JOIN 
        aka_name ak ON t.id = ak.id
    LEFT JOIN 
        cast_info ci ON t.id = ci.movie_id
    LEFT JOIN 
        name c ON ci.person_id = c.id
    LEFT JOIN 
        movie_keyword mk ON t.id = mk.movie_id
    LEFT JOIN 
        keyword k ON mk.keyword_id = k.id
    GROUP BY 
        t.id, t.title, t.production_year
),
CompanyDetails AS (
    SELECT 
        mc.movie_id,
        LISTAGG(DISTINCT cn.name, ', ') WITHIN GROUP (ORDER BY cn.name) AS company_names,
        LISTAGG(DISTINCT ct.kind, ', ') WITHIN GROUP (ORDER BY ct.kind) AS company_types
    FROM 
        movie_companies mc
    JOIN 
        company_name cn ON mc.company_id = cn.id
    JOIN 
        company_type ct ON mc.company_type_id = ct.id
    GROUP BY 
        mc.movie_id
),
FinalResults AS (
    SELECT 
        md.movie_id,
        md.movie_title,
        md.production_year,
        md.aka_names,
        md.cast_names,
        md.keywords,
        cd.company_names,
        cd.company_types
    FROM 
        MovieDetails md
    LEFT JOIN 
        CompanyDetails cd ON md.movie_id = cd.movie_id
)
SELECT 
    *
FROM 
    FinalResults
WHERE 
    production_year BETWEEN 2000 AND 2023
ORDER BY 
    production_year DESC, movie_title;
