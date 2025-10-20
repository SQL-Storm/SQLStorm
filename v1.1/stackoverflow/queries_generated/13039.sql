-- {"query": "13039.sql", "dataset": "stackoverflow", "version": "v1.1", "prompt": "p1", "model": "nova-premier", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2142, "output_tokens": 632} 

WITH UserActivity AS (
    SELECT 
        u.Id AS UserId, 
        u.DisplayName, 
        COUNT(DISTINCT p.Id) AS PostsCount, 
        SUM(p.Score) AS TotalScore,
        MAX(p.LastActivityDate) AS LastActivityDate,
        AVG(p.ViewCount) AS AvgViewCount,
        SUM(CASE WHEN b.Class = 1 THEN 1 ELSE 0 END) AS GoldBadges,
        SUM(CASE WHEN b.Class = 2 THEN 1 ELSE 0 END) AS SilverBadges,
        SUM(CASE WHEN b.Class = 3 THEN 1 ELSE 0 END) AS BronzeBadges
    FROM Users u
    LEFT JOIN Posts p ON u.Id = p.OwnerUserId
    LEFT JOIN Badges b ON u.Id = b.UserId
    WHERE u.Reputation > 1000 AND u.LastAccessDate > CURRENT_TIMESTAMP - INTERVAL '1 year'
    GROUP BY u.Id, u.DisplayName
),
TopQuestions AS (
    SELECT 
        p.Id AS PostId,
        p.Title,
        p.Score,
        p.Tags,
        COUNT(DISTINCT ph.UserId) AS UniqueEditors,
        ROW_NUMBER() OVER (ORDER BY p.Score DESC) AS Rank
    FROM Posts p
    LEFT JOIN PostHistory ph ON p.Id = ph.PostId AND ph.PostHistoryTypeId IN (4, 5, 6)
    WHERE p.PostTypeId = 1 AND p.ClosedDate IS NULL AND p.Score > 50
    GROUP BY p.Id, p.Title, p.Score, p.Tags
    HAVING COUNT(DISTINCT ph.UserId) > 2
)
SELECT 
    ua.UserId,
    ua.DisplayName,
    ua.PostsCount,
    ua.TotalScore,
    ua.GoldBadges + ua.SilverBadges + ua.BronzeBadges AS TotalBadges,
    tq.PostId,
    tq.Title,
    tq.Score,
    string_to_array(substring(tq.Tags, 2, length(tq.Tags) - 2), '><') AS TagArray,
    tq.UniqueEditors,
    DENSE_RANK() OVER (PARTITION BY ua.UserId ORDER BY tq.Score DESC) AS UserPostRank
FROM UserActivity ua
LEFT JOIN TopQuestions tq ON ua.UserId = tq.OwnerUserId
WHERE tq.Rank <= 100 OR tq.Rank IS NULL
ORDER BY ua.TotalScore DESC NULLS LAST, tq.Score DESC NULLS LAST;
