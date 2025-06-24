WITH RECURSIVE movie_hierarchy AS (
    SELECT 
        mt.id AS movie_id,
        mt.title,
        mt.production_year,
        1 AS level
    FROM 
        aka_title mt
    WHERE 
        mt.production_year >= 2000
    UNION ALL
    SELECT 
        ml.linked_movie_id AS movie_id,
        at.title,
        at.production_year,
        mh.level + 1
    FROM 
        movie_link ml
    INNER JOIN aka_title at ON ml.linked_movie_id = at.id
    INNER JOIN movie_hierarchy mh ON ml.movie_id = mh.movie_id
    WHERE 
        mh.level < 3
),
actor_rankings AS (
    SELECT 
        ci.movie_id,
        ak.name AS actor_name,
        ROW_NUMBER() OVER (PARTITION BY ci.movie_id ORDER BY COUNT(*) DESC) AS role_rank
    FROM 
        cast_info ci
    JOIN aka_name ak ON ci.person_id = ak.person_id
    GROUP BY 
        ci.movie_id, ak.name
),
company_movie_info AS (
    SELECT 
        mc.movie_id,
        STRING_AGG(CASE 
            WHEN ct.kind IS NOT NULL THEN cn.name 
            ELSE 'Unknown Company' END, ', ') AS companies_involved
    FROM 
        movie_companies mc
    LEFT JOIN company_name cn ON mc.company_id = cn.id
    LEFT JOIN company_type ct ON mc.company_type_id = ct.id
    GROUP BY 
        mc.movie_id
)
SELECT 
    mh.movie_id,
    mh.title,
    mh.production_year,
    COALESCE(ar.actor_name, 'No Cast') AS lead_actor,
    cm.companies_involved,
    COUNT(DISTINCT ki.keyword) AS keyword_count,
    (SELECT COUNT(*) FROM complete_cast cc WHERE cc.movie_id = mh.movie_id) AS total_cast_count
FROM 
    movie_hierarchy mh
LEFT JOIN actor_rankings ar ON mh.movie_id = ar.movie_id AND ar.role_rank = 1
LEFT JOIN company_movie_info cm ON mh.movie_id = cm.movie_id
LEFT JOIN movie_keyword mk ON mh.movie_id = mk.movie_id
LEFT JOIN keyword ki ON mk.keyword_id = ki.id
GROUP BY 
    mh.movie_id, mh.title, mh.production_year, ar.actor_name, cm.companies_involved
HAVING 
    COUNT(DISTINCT ki.keyword) > 3
ORDER BY 
    mh.production_year DESC, mh.title ASC
LIMIT 100;
