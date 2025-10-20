WITH UserPostStats AS (
    SELECT 
        u.Id AS UserId,
        u.DisplayName,
        COUNT(p.Id) AS PostCount,
        AVG(p.Score) AS AvgPostScore,
        PERCENTILE_CONT(0.5) WITHIN GROUP (ORDER BY p.ViewCount) AS MedianViewCount,
        RANK() OVER (ORDER BY COUNT(p.Id) DESC) AS PostCountRank
    FROM Users u
    LEFT JOIN Posts p ON u.Id = p.OwnerUserId
    WHERE p.PostTypeId IN (1, 2)
    GROUP BY u.Id, u.DisplayName
),
TagPopularity AS (
    SELECT 
        tag AS Tag,
        COUNT(*) AS TagCount,
        AVG(x.Score) AS AvgTagScore
    FROM (
        SELECT p_all.Id, p_all.Score, TRIM(t) AS tag
        FROM Posts p_all
        JOIN LATERAL (
            SELECT regexp_split_to_table(substring(p_all.Tags FROM 2 FOR char_length(p_all.Tags) - 2), '><') AS t
        ) s ON p_all.Tags IS NOT NULL
        WHERE p_all.Tags IS NOT NULL
    ) x
    GROUP BY tag
)
SELECT 
    ups.UserId,
    ups.DisplayName,
    ups.PostCount,
    ups.AvgPostScore,
    ups.MedianViewCount,
    tp.Tag AS MostFrequentTag,
    tp.TagCount,
    tp.AvgTagScore,
    CASE 
        WHEN ups.PostCount > 0 AND tp.TagCount > 100 THEN 'Influential'
        WHEN ups.PostCount > 10 THEN 'Active'
        ELSE 'Casual'
    END AS UserCategory,
    (SELECT COUNT(*) FROM Badges b WHERE b.UserId = ups.UserId AND b.Class = 1) AS GoldBadgeCount,
    COALESCE(
        (SELECT MAX(v.CreationDate) 
         FROM Votes v 
         JOIN Posts p2 ON v.PostId = p2.Id 
         WHERE p2.OwnerUserId = ups.UserId AND v.VoteTypeId = 2), 
        CAST('1970-01-01' AS timestamp)
    ) AS LastUpvoteReceived
FROM UserPostStats ups
JOIN TagPopularity tp ON tp.TagCount = (
    SELECT MAX(tp2.TagCount) 
    FROM TagPopularity tp2 
    WHERE tp2.Tag IN (
        SELECT TRIM(t2)
        FROM Posts p3
        JOIN LATERAL (
            SELECT regexp_split_to_table(substring(p3.Tags FROM 2 FOR char_length(p3.Tags) - 2), '><') AS t2
        ) s2 ON p3.Tags IS NOT NULL
        WHERE p3.OwnerUserId = ups.UserId
          AND p3.Tags IS NOT NULL
    )
)
WHERE ups.PostCount > 5 
  AND ups.AvgPostScore > 1
GROUP BY
    ups.UserId,
    ups.DisplayName,
    ups.PostCount,
    ups.AvgPostScore,
    ups.MedianViewCount,
    tp.Tag,
    tp.TagCount,
    tp.AvgTagScore
ORDER BY ups.PostCount * ups.AvgPostScore DESC
LIMIT 100;