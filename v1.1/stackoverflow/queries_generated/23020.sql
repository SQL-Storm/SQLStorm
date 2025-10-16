-- {"query": "23020.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "grok-4", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2685, "output_tokens": 863} 

WITH TopUsers AS (
    SELECT u.Id, u.Reputation, u.DisplayName,
           ROW_NUMBER() OVER (ORDER BY u.Reputation DESC) AS Rank,
           COUNT(b.Id) AS BadgeCount,
           SUM(CASE WHEN b.Class = 1 THEN 3 WHEN b.Class = 2 THEN 2 ELSE 1 END) AS WeightedBadgeScore
    FROM Users u
    LEFT JOIN Badges b ON u.Id = b.UserId
    GROUP BY u.Id, u.Reputation, u.DisplayName
    HAVING COUNT(b.Id) > 0 OR u.Reputation > 1000
),
PostAnalytics AS (
    SELECT p.Id, p.OwnerUserId, p.Score, p.ViewCount,
           COALESCE(p.FavoriteCount, 0) + COALESCE(p.AnswerCount, 0) AS Engagement,
           (SELECT COUNT(*) FROM Comments c WHERE c.PostId = p.Id AND c.Score > 0) AS PositiveComments,
           STRING_AGG(SUBSTRING(t.Tags, 2, LENGTH(t.Tags)-2), ', ') AS TagList
    FROM Posts p
    LEFT JOIN Posts t ON p.Id = t.Id AND p.PostTypeId = 1
    WHERE p.CreationDate >= '2020-01-01' AND (p.Title LIKE '%SQL%' OR p.Tags LIKE '%<sql>%')
    GROUP BY p.Id, p.OwnerUserId, p.Score, p.ViewCount, p.FavoriteCount, p.AnswerCount
),
UserPostSummary AS (
    SELECT tu.Id AS UserId, tu.Rank, tu.DisplayName, tu.BadgeCount,
           AVG(pa.Score) AS AvgPostScore,
           SUM(pa.Engagement) AS TotalEngagement,
           MAX(pa.PositiveComments) AS MaxCommentsOnPost,
           COUNT(DISTINCT v.Id) AS UniqueVotes,
           LAG(tu.Reputation) OVER (ORDER BY tu.Rank) AS PrevReputation,
           CASE WHEN tu.Reputation IS NULL THEN 0 ELSE tu.Reputation - COALESCE(LAG(tu.Reputation) OVER (ORDER BY tu.Rank), 0) END AS RepDiff
    FROM TopUsers tu
    INNER JOIN PostAnalytics pa ON tu.Id = pa.OwnerUserId
    LEFT JOIN Votes v ON pa.Id = v.PostId AND v.VoteTypeId IN (2, 3)
    WHERE EXISTS (SELECT 1 FROM PostHistory ph WHERE ph.PostId = pa.Id AND ph.PostHistoryTypeId = 5 AND ph.Text LIKE '%edit%')
    GROUP BY tu.Id, tu.Rank, tu.DisplayName, tu.BadgeCount, tu.Reputation
)
SELECT ups.UserId, ups.DisplayName, ups.Rank, ups.BadgeCount, ups.AvgPostScore, ups.TotalEngagement,
       ups.MaxCommentsOnPost, ups.UniqueVotes, ups.RepDiff,
       COALESCE((SELECT MAX(Score) FROM Comments c WHERE c.UserId = ups.UserId), 0) AS MaxCommentScore,
       STRING_AGG(CONCAT('Post ', pa.Id, ': ', pa.TagList), '; ') AS AllTags
FROM UserPostSummary ups
LEFT JOIN PostAnalytics pa ON ups.UserId = pa.OwnerUserId
WHERE ups.Rank <= 10
GROUP BY ups.UserId, ups.DisplayName, ups.Rank, ups.BadgeCount, ups.AvgPostScore, ups.TotalEngagement,
         ups.MaxCommentsOnPost, ups.UniqueVotes, ups.RepDiff
UNION ALL
SELECT NULL AS UserId, 'Summary' AS DisplayName, NULL AS Rank, SUM(ups.BadgeCount) AS BadgeCount,
       AVG(ups.AvgPostScore) AS AvgPostScore, SUM(ups.TotalEngagement) AS TotalEngagement,
       MAX(ups.MaxCommentsOnPost) AS MaxCommentsOnPost, SUM(ups.UniqueVotes) AS UniqueVotes,
       AVG(ups.RepDiff) AS RepDiff, 0 AS MaxCommentScore, NULL AS AllTags
FROM UserPostSummary ups
WHERE ups.Rank > 10 AND ups.TotalEngagement IS NOT NULL
ORDER BY Rank ASC NULLS LAST;
