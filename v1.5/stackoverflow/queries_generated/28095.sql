-- {"query": "28095.sql", "dataset": "stackoverflow", "version": "v1.1", "prompt": "p1", "model": "deepseek-r1", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2074, "output_tokens": 1389} 

WITH UserBadgeSummary AS (
    SELECT 
        UserId,
        COUNT(CASE WHEN Class = 1 THEN 1 END) AS GoldBadges,
        COUNT(CASE WHEN Class = 2 THEN 1 END) AS SilverBadges,
        COUNT(CASE WHEN Class = 3 THEN 1 END) AS BronzeBadges
    FROM Badges
    GROUP BY UserId
),
PostActivity AS (
    SELECT
        p.OwnerUserId,
        COUNT(DISTINCT p.Id) AS TotalPosts,
        COUNT(DISTINCT CASE WHEN p.PostTypeId = 1 THEN p.Id END) AS Questions,
        COUNT(DISTINCT CASE WHEN p.PostTypeId = 2 THEN p.Id END) AS Answers,
        MAX(p.Score) AS HighestPostScore,
        STRING_AGG(DISTINCT SUBSTRING(p.Tags, 2, LENGTH(p.Tags)-2), ', ') FILTER (WHERE p.Tags IS NOT NULL) AS AllTags
    FROM Posts p
    GROUP BY p.OwnerUserId
),
VoteAnalysis AS (
    SELECT 
        UserId,
        SUM(CASE WHEN VoteTypeId = 2 THEN 1 ELSE 0 END) AS UpvotesReceived,
        SUM(CASE WHEN VoteTypeId = 3 THEN 1 ELSE 0 END) AS DownvotesReceived
    FROM Votes v
    WHERE EXISTS (SELECT 1 FROM Posts WHERE Id = v.PostId AND OwnerUserId = v.UserId)
    GROUP BY UserId
)
SELECT 
    u.Id AS UserId,
    u.DisplayName,
    COALESCE(ubs.GoldBadges, 0) + COALESCE(ubs.SilverBadges, 0) * 0.5 + COALESCE(ubs.BronzeBadges, 0) * 0.25 AS BadgeScore,
    pa.TotalPosts,
    (pa.Questions * 2 + pa.Answers) * 1.0 / NULLIF(DATE_PART('day', NOW() - u.CreationDate), 0) AS DailyPostRate,
    RANK() OVER (ORDER BY u.Reputation DESC) AS GlobalRank,
    DENSE_RANK() OVER (PARTITION BY u.Location ORDER BY u.Reputation DESC) AS LocalRank,
    va.UpvotesReceived - va.DownvotesReceived AS NetVotes,
    (SELECT MAX(CreationDate) FROM Comments WHERE UserId = u.Id) AS LastCommentDate,
    (SELECT STRING_AGG(DISTINCT TagName, ', ' ORDER BY COUNT DESC LIMIT 3) 
     FROM Tags t 
     WHERE t.Id IN (SELECT unnest(string_to_array(SUBSTRING(p.Tags, 2, LENGTH(p.Tags)-2), '><')) FROM Posts p WHERE p.OwnerUserId = u.Id)) AS TopTags,
    COALESCE(ph.EditCount, 0) AS PostEdits,
    CASE 
        WHEN u.Reputation > 100000 THEN 'Legendary' 
        WHEN u.Reputation > 50000 THEN 'Epic' 
        WHEN u.Reputation > 10000 THEN 'Veteran' 
        ELSE 'Regular' 
    END AS ReputationClass,
    SUM(va.UpvotesReceived) OVER (ORDER BY u.Reputation DESC ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW) AS CumulativeUpvotes,
    COALESCE((SELECT JSON_AGG(text) FROM PostHistory WHERE UserId = u.Id AND PostHistoryTypeId = 5 LIMIT 3), '[]'::json) AS RecentEdits
FROM Users u
LEFT JOIN UserBadgeSummary ubs ON u.Id = ubs.UserId
LEFT JOIN PostActivity pa ON u.Id = pa.OwnerUserId
LEFT JOIN VoteAnalysis va ON u.Id = va.UserId
LEFT JOIN (
    SELECT UserId, COUNT(*) AS EditCount 
    FROM PostHistory 
    WHERE PostHistoryTypeId IN (4,5,6) 
    GROUP BY UserId
) ph ON u.Id = ph.UserId
WHERE u.CreationDate BETWEEN '2022-01-01' AND '2022-12-31'
  AND EXISTS (SELECT 1 FROM Posts WHERE OwnerUserId = u.Id)
  AND (u.DownVotes < u.UpVotes OR u.DownVotes IS NULL)
ORDER BY u.Reputation DESC
LIMIT 100;
