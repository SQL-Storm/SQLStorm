WITH UserPostScores AS (
    SELECT 
        u.Id AS UserId, 
        u.DisplayName, 
        pt.Name AS PostType, 
        SUM(p.Score) AS TotalScore,
        COUNT(p.Id) AS PostCount,
        RANK() OVER (PARTITION BY pt.Name ORDER BY SUM(p.Score) DESC) AS ScoreRank
    FROM 
        Users u
    JOIN 
        Posts p ON u.Id = p.OwnerUserId
    JOIN 
        PostTypes pt ON p.PostTypeId = pt.Id
    WHERE 
        u.Reputation > 1000 
        AND p.CreationDate > DATE '2015-01-01'
    GROUP BY 
        u.Id, u.DisplayName, pt.Name
),
TagPopularity AS (
    -- Parse tags stored like '<tag1><tag2>' into rows, count and average score per tag
    SELECT 
        tag AS Tag,
        COUNT(*) AS TagCount,
        AVG(Score) AS AvgTagScore
    FROM (
        SELECT
            p.Id,
            TRIM(tag_item) AS tag,
            p.Score
        FROM Posts p
        CROSS JOIN LATERAL (
            SELECT
                CASE
                    WHEN p.Tags IS NULL THEN NULL
                    ELSE
                        CASE
                            WHEN LEFT(p.Tags,1) = '<' AND RIGHT(p.Tags,1) = '>' THEN SUBSTRING(p.Tags FROM 2 FOR (CHAR_LENGTH(p.Tags) - 2))
                            ELSE p.Tags
                        END
                END AS tags_inner
        ) ti
        CROSS JOIN LATERAL (
            -- split tags_inner by '><' into rows using a recursive CTE approach
            WITH RECURSIVE split(tp, rest) AS (
                SELECT
                    CASE
                        WHEN ti.tags_inner IS NULL THEN NULL
                        WHEN POSITION('><' IN ti.tags_inner) = 0 THEN ti.tags_inner
                        ELSE SUBSTRING(ti.tags_inner FROM 1 FOR POSITION('><' IN ti.tags_inner) - 1)
                    END,
                    CASE
                        WHEN ti.tags_inner IS NULL THEN NULL
                        WHEN POSITION('><' IN ti.tags_inner) = 0 THEN NULL
                        ELSE SUBSTRING(ti.tags_inner FROM POSITION('><' IN ti.tags_inner) + 2)
                    END
                UNION ALL
                SELECT
                    CASE
                        WHEN POSITION('><' IN rest) = 0 THEN rest
                        ELSE SUBSTRING(rest FROM 1 FOR POSITION('><' IN rest) - 1)
                    END,
                    CASE
                        WHEN POSITION('><' IN rest) = 0 THEN NULL
                        ELSE SUBSTRING(rest FROM POSITION('><' IN rest) + 2)
                    END
                FROM split
                WHERE rest IS NOT NULL
            )
            SELECT tp AS tag_item FROM split WHERE tp IS NOT NULL
        ) s
    ) sub
    WHERE tag IS NOT NULL AND tag <> ''
    GROUP BY 
        tag
)
SELECT 
    ups.UserId,
    ups.DisplayName,
    ups.PostType,
    ups.TotalScore,
    ups.PostCount,
    ups.ScoreRank,
    tp.Tag,
    tp.TagCount,
    tp.AvgTagScore
FROM 
    UserPostScores ups
JOIN 
    TagPopularity tp ON 1=1
WHERE 
    ups.ScoreRank <= 10
ORDER BY 
    ups.TotalScore DESC, 
    tp.TagCount DESC
LIMIT 100;