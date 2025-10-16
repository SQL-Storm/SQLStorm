WITH RankedUserPosts AS (
    SELECT 
        u.Id AS UserId,
        u.DisplayName,
        p.Id AS PostId,
        p.Title,
        p.Score,
        p.Tags,
        p.ViewCount,
        ROW_NUMBER() OVER (PARTITION BY u.Id ORDER BY p.Score DESC) AS ScoreRank,
        -- compute each individual tag in a lateral subquery and then rank by ViewCount per tag
        -- produce Tag string for later use in TagPopularityRank via a join
        p.CreationDate
    FROM Users u
    JOIN Posts p ON u.Id = p.OwnerUserId
    WHERE p.PostTypeId = 1
      AND u.Reputation > 1000
      AND p.CreationDate > '2015-01-01'
),
PostTags AS (
    -- break Tags like '<tag1><tag2>' into rows: tag text without angle brackets
    SELECT
        rup.*,
        t.tag
    FROM RankedUserPosts rup
    CROSS JOIN LATERAL (
        SELECT TRIM(both '<>' FROM tagpart) AS tag
        FROM (
            SELECT regexp_split_to_table(rup.Tags, '><') AS tagpart
        ) s
    ) t
),
TagPopularity AS (
    -- rank posts per tag by ViewCount
    SELECT
        pt.UserId,
        pt.PostId,
        pt.tag,
        DENSE_RANK() OVER (PARTITION BY pt.tag ORDER BY pt.ViewCount DESC) AS TagPopularityRankPerTag,
        pt.Score,
        pt.DisplayName
    FROM PostTags pt
),
TagAnalytics AS (
    -- aggregate per user: unique tags, max score and avg view count for top 3 posts by user
    -- first restrict to top 3 posts per user
    SELECT 
        ra.UserId,
        ra.DisplayName,
        COUNT(DISTINCT pt.tag) AS UniqueTagCount,
        MAX(ra.Score) AS MaxPostScore,
        AVG(COALESCE(ra.ViewCount, 0)) AS AvgViewCount
    FROM RankedUserPosts ra
    JOIN (
        SELECT UserId, PostId
        FROM RankedUserPosts
        WHERE ScoreRank <= 3
    ) top3 ON ra.UserId = top3.UserId AND ra.PostId = top3.PostId
    LEFT JOIN PostTags pt ON ra.PostId = pt.PostId
    GROUP BY ra.UserId, ra.DisplayName
),
TopRankedPosts AS (
    -- pick only posts that are score rank = 1 and have tag popularity rank <=5 for at least one tag
    SELECT DISTINCT trp.UserId, trp.PostId, trp.Score, trp.DisplayName
    FROM RankedUserPosts trp
    JOIN PostTags pt ON trp.PostId = pt.PostId
    JOIN (
        SELECT PostId, tag, DENSE_RANK() OVER (PARTITION BY tag ORDER BY ViewCount DESC) AS TagPopularityRank
        FROM PostTags
    ) tpr ON pt.PostId = tpr.PostId AND pt.tag = tpr.tag
    WHERE trp.ScoreRank = 1
      AND tpr.TagPopularityRank <= 5
)
SELECT 
    rup.UserId,
    rup.DisplayName,
    ta.UniqueTagCount,
    ta.MaxPostScore,
    ta.AvgViewCount,
    COUNT(DISTINCT v.Id) AS TotalVotes,
    PERCENTILE_CONT(0.5) WITHIN GROUP (ORDER BY rup.Score) AS MedianPostScore,
    CASE 
        WHEN ta.UniqueTagCount > 10 THEN 'Expert'
        WHEN ta.UniqueTagCount > 5 THEN 'Intermediate'
        ELSE 'Beginner'
    END AS ExpertiseLevel
FROM RankedUserPosts rup
JOIN TagAnalytics ta ON rup.UserId = ta.UserId
LEFT JOIN Votes v ON rup.PostId = v.PostId
JOIN TopRankedPosts trp ON rup.UserId = trp.UserId AND rup.PostId = trp.PostId
WHERE (
        EXISTS (
            SELECT 1 
            FROM Badges b 
            WHERE b.UserId = rup.UserId 
              AND b.Class = 1
        )
        OR ta.MaxPostScore > 100
)
GROUP BY 
    rup.UserId, 
    rup.DisplayName, 
    ta.UniqueTagCount, 
    ta.MaxPostScore, 
    ta.AvgViewCount
HAVING COUNT(DISTINCT v.Id) > 10
ORDER BY ta.MaxPostScore DESC, ta.UniqueTagCount DESC
LIMIT 100;