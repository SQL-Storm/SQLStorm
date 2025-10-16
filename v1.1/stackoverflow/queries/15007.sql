WITH RankedUserPosts AS (
    SELECT 
        u.Id AS UserId,
        u.DisplayName,
        p.Id AS PostId,
        p.Score,
        p.PostTypeId,
        p.Tags,
        RANK() OVER (PARTITION BY u.Id ORDER BY p.Score DESC) AS PostRank,
        DENSE_RANK() OVER (PARTITION BY EXTRACT(YEAR FROM p.CreationDate) ORDER BY p.ViewCount DESC) AS YearlyViewRank
    FROM Users u
    LEFT JOIN Posts p ON u.Id = p.OwnerUserId
    WHERE p.PostTypeId IN (1, 2)
),
ExplodedTags AS (
    SELECT
        rup.UserId,
        TRIM(tag) AS Tag
    FROM RankedUserPosts rup,
    LATERAL (
        SELECT value AS tag
        FROM (
            SELECT 
                CASE
                    WHEN rup.Tags IS NULL THEN ARRAY[]::text[]  -- placeholder to be replaced per dialect
                    WHEN LENGTH(rup.Tags) <= 2 THEN ARRAY[]::text[]
                    ELSE
                        string_to_array(substring(rup.Tags FROM 2 FOR GREATEST(length(rup.Tags) - 2,0)), '><')
                END AS arr
        ) arr_tbl,
        UNNEST(arr_tbl.arr) AS t(value)
    ) s
    WHERE rup.Tags IS NOT NULL AND LENGTH(rup.Tags) > 2
),
TagAnalytics AS (
    SELECT 
        rup.UserId,
        rup.DisplayName,
        MAX(rup.PostRank) AS MaxPostRank,
        AVG(COALESCE(rup.Score, 0)) AS AvgPostScore,
        COUNT(DISTINCT et.Tag) AS UniqueTagCount
    FROM RankedUserPosts rup
    LEFT JOIN ExplodedTags et ON rup.UserId = et.UserId
    GROUP BY rup.UserId, rup.DisplayName
    HAVING MAX(rup.PostRank) <= 10
)
SELECT 
    ta.UserId,
    ta.DisplayName,
    ta.MaxPostRank,
    ta.AvgPostScore,
    ta.UniqueTagCount,
    v.Count AS TotalVotes,
    CASE 
        WHEN ta.AvgPostScore > 10 THEN 'High Performer'
        WHEN ta.AvgPostScore BETWEEN 5 AND 10 THEN 'Moderate Contributor'
        ELSE 'Emerging User'
    END AS UserCategory,
    COALESCE(b.GoldBadges, 0) AS GoldBadgeCount
FROM TagAnalytics ta
LEFT JOIN (
    SELECT UserId, COUNT(*) AS Count 
    FROM Votes 
    WHERE VoteTypeId IN (2, 3) 
    GROUP BY UserId
) v ON ta.UserId = v.UserId
LEFT JOIN (
    SELECT UserId, COUNT(*) AS GoldBadges 
    FROM Badges 
    WHERE Class = 1 
    GROUP BY UserId
) b ON ta.UserId = b.UserId
WHERE ta.UniqueTagCount > 5
ORDER BY ta.AvgPostScore DESC, v.Count DESC
LIMIT 100;