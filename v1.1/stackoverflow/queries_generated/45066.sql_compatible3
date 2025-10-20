WITH RankedUserPosts AS (
    SELECT 
        u.Id AS UserId,
        u.DisplayName,
        p.Id AS PostId,
        p.Score,
        p.ViewCount,
        p.PostTypeId,
        p.Tags,
        ROW_NUMBER() OVER (PARTITION BY u.Id ORDER BY p.Score DESC, p.ViewCount DESC) AS PostRank,
        COUNT(*) OVER (PARTITION BY u.Id) AS TotalUserPosts,
        AVG(p.Score) OVER (PARTITION BY u.Id) AS AvgUserPostScore
    FROM 
        Users u
    JOIN 
        Posts p ON u.Id = p.OwnerUserId
    WHERE 
        p.PostTypeId IN (1,2)
        AND u.Reputation > 1000
),
TagAnalytics AS (
    SELECT 
        r.PostId,
        TRIM(t.tag) AS Tag,
        r.Score,
        r.PostRank,
        r.TotalUserPosts
    FROM 
        RankedUserPosts r,
        LATERAL (
            SELECT value AS tag
            FROM (
                -- remove leading '<' and trailing '>' if present, else empty string
                SELECT
                    CASE 
                        WHEN r.Tags IS NULL OR r.Tags = '' THEN ''
                        WHEN LEFT(r.Tags,1) = '<' AND RIGHT(r.Tags,1) = '>' THEN SUBSTR(r.Tags, 2, LENGTH(r.Tags) - 2)
                        WHEN LEFT(r.Tags,1) = '<' THEN SUBSTR(r.Tags, 2)
                        WHEN RIGHT(r.Tags,1) = '>' THEN SUBSTR(r.Tags, 1, LENGTH(r.Tags) - 1)
                        ELSE r.Tags
                    END AS stripped
            ) s,
            -- split the stripped string on '><' into rows. Use a generic string-split-emulation that works in many dialects.
            -- This implementation uses a recursive common table expression to split the string into rows.
            LATERAL (
                WITH RECURSIVE split(pos, rest, piece) AS (
                    SELECT 1 AS pos,
                           s.stripped AS rest,
                           CASE 
                             WHEN s.stripped = '' THEN NULL
                             WHEN INSTR(s.stripped, '><') = 0 THEN s.stripped
                             ELSE SUBSTR(s.stripped, 1, INSTR(s.stripped, '><') - 1)
                           END AS piece
                    UNION ALL
                    SELECT pos + 1,
                           CASE 
                             WHEN INSTR(rest, '><') = 0 THEN ''
                             ELSE SUBSTR(rest, INSTR(rest, '><') + 2)
                           END,
                           CASE 
                             WHEN INSTR(rest, '><') = 0 THEN NULL
                             ELSE
                               CASE WHEN INSTR(CASE WHEN INSTR(rest, '><') = 0 THEN '' ELSE SUBSTR(rest, INSTR(rest, '><') + 2) END, '><') = 0
                                    THEN CASE WHEN INSTR(rest, '><') = 0 THEN NULL ELSE SUBSTR(rest, INSTR(rest, '><') + 2) END
                                    ELSE SUBSTR(rest, INSTR(rest, '><') + 2, INSTR(CASE WHEN INSTR(rest, '><') = 0 THEN '' ELSE SUBSTR(rest, INSTR(rest, '><') + 2) END, '><') - 1)
                               END
                           END
                    FROM split
                    WHERE rest IS NOT NULL AND rest <> ''
                    AND INSTR(rest, '><') <> 0
                )
                SELECT piece AS value FROM split WHERE piece IS NOT NULL
                UNION ALL
                -- handle the last piece when there is no delimiter
                SELECT s.stripped AS value WHERE s.stripped <> '' AND INSTR(s.stripped, '><') = 0
            ) parts
        ) t
)
SELECT 
    Tag,
    COUNT(DISTINCT PostId) AS PostCount,
    ROUND(AVG(Score), 2) AS AvgTagScore,
    MAX(Score) AS MaxTagScore
FROM 
    TagAnalytics
WHERE 
    PostRank <= 10
    AND TotalUserPosts > 5
GROUP BY 
    Tag
HAVING 
    COUNT(DISTINCT PostId) > 100
ORDER BY 
    AvgTagScore DESC, 
    PostCount DESC
LIMIT 50;