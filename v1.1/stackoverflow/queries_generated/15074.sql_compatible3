WITH UserPostStats AS (
    SELECT 
        u.Id AS UserId,
        u.DisplayName,
        COUNT(p.Id) AS PostCount,
        AVG(p.Score) AS AvgPostScore,
        MAX(p.ViewCount) AS MaxViewCount,
        DENSE_RANK() OVER (ORDER BY COUNT(p.Id) DESC) AS PostCountRank
    FROM Users u
    LEFT JOIN Posts p ON u.Id = p.OwnerUserId
    WHERE p.PostTypeId = 1
    GROUP BY u.Id, u.DisplayName
),
TagPopularity AS (
    SELECT 
        tag_name AS TagName,
        COUNT(*) AS TagFrequency,
        AVG(p.Score) AS AvgTagScore
    FROM Posts p,
    LATERAL (
        WITH RECURSIVE split(str, rest, value) AS (
            SELECT
                CASE
                    WHEN p.Tags LIKE '<%>' AND LENGTH(p.Tags) >= 2 THEN SUBSTRING(p.Tags FROM 2 FOR LENGTH(p.Tags) - 2)
                    ELSE p.Tags
                END AS str,
                '' AS rest,
                NULL::text AS value
            UNION ALL
            SELECT
                CASE
                    WHEN POSITION('><' IN str) > 0 THEN SUBSTRING(str FROM 1 FOR POSITION('><' IN str) - 1)
                    ELSE str
                END AS value,
                CASE
                    WHEN POSITION('><' IN str) > 0 THEN SUBSTRING(str FROM POSITION('><' IN str) + 2)
                    ELSE ''
                END AS rest,
                NULL::text AS value
            FROM (
                SELECT CASE
                    WHEN p.Tags LIKE '<%>' AND LENGTH(p.Tags) >= 2 THEN SUBSTRING(p.Tags FROM 2 FOR LENGTH(p.Tags) - 2)
                    ELSE p.Tags
                END AS str
            ) init
            UNION ALL
            SELECT
                CASE
                    WHEN POSITION('><' IN rest) > 0 THEN SUBSTRING(rest FROM 1 FOR POSITION('><' IN rest) - 1)
                    ELSE rest
                END AS value,
                CASE
                    WHEN POSITION('><' IN rest) > 0 THEN SUBSTRING(rest FROM POSITION('><' IN rest) + 2)
                    ELSE ''
                END AS rest,
                NULL::text AS value
            FROM split
            WHERE rest <> ''
        ),
        flattened AS (
            SELECT DISTINCT TRIM(value) AS value
            FROM (
                SELECT
                    CASE
                        WHEN POSITION('><' IN str) > 0 THEN SUBSTRING(str FROM 1 FOR POSITION('><' IN str) - 1)
                        ELSE str
                    END AS value
                FROM (
                    SELECT CASE
                        WHEN p.Tags LIKE '<%>' AND LENGTH(p.Tags) >= 2 THEN SUBSTRING(p.Tags FROM 2 FOR LENGTH(p.Tags) - 2)
                        ELSE p.Tags
                    END AS str
                ) s1
                UNION ALL
                SELECT value FROM split WHERE value IS NOT NULL
            ) allvals
            WHERE value IS NOT NULL AND value <> ''
        )
        SELECT value FROM flattened
    ) t(tag_name)
    WHERE p.PostTypeId = 1
    GROUP BY tag_name
)
SELECT 
    ups.UserId,
    ups.DisplayName,
    ups.PostCount,
    ups.AvgPostScore,
    ups.MaxViewCount,
    ups.PostCountRank,
    COALESCE(
        (SELECT SUM(v.BountyAmount) 
         FROM Votes v 
         WHERE v.UserId = ups.UserId AND v.VoteTypeId = 8), 0) AS TotalBountyStarted,
    (SELECT tp.TagFrequency 
     FROM TagPopularity tp 
     WHERE tp.TagFrequency = (SELECT MAX(tp2.TagFrequency) FROM TagPopularity tp2)
     LIMIT 1) AS MostPopularTagFrequency,
    CASE 
        WHEN ups.PostCount > 10 AND ups.AvgPostScore > 5 THEN 'High Impact User'
        WHEN ups.PostCount BETWEEN 5 AND 10 THEN 'Emerging Contributor'
        ELSE 'New User'
    END AS UserCategory,
    RANK() OVER (ORDER BY ups.AvgPostScore DESC) AS ScoreRank
FROM UserPostStats ups
WHERE ups.PostCount > 0
    AND EXISTS (
        SELECT 1 
        FROM Badges b 
        WHERE b.UserId = ups.UserId 
        AND b.Class = 1
    )
ORDER BY ups.PostCount DESC, ups.AvgPostScore DESC
LIMIT 100;