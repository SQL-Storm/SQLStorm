-- {"query": "28005.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "deepseek-r1", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2074, "output_tokens": 1469} 

WITH UserBadgeStats AS (
    SELECT 
        UserId, 
        COUNT(*) AS TotalBadges,
        SUM(CASE WHEN Class = 1 THEN 1 ELSE 0 END) AS GoldBadges,
        SUM(CASE WHEN Class = 2 THEN 1 ELSE 0 END) AS SilverBadges,
        SUM(CASE WHEN Class = 3 THEN 1 ELSE 0 END) AS BronzeBadges
    FROM Badges
    GROUP BY UserId
), PostActivity AS (
    SELECT 
        OwnerUserId,
        COUNT(DISTINCT CASE WHEN PostTypeId = 1 THEN Id END) AS QuestionsAsked,
        COUNT(DISTINCT CASE WHEN PostTypeId = 2 THEN Id END) AS AnswersProvided,
        MAX(COALESCE(Score, 0)) AS HighestPostScore,
        AVG(COALESCE(ViewCount, 0)) OVER (PARTITION BY OwnerUserId) AS AvgViews
    FROM Posts
    WHERE OwnerUserId IS NOT NULL
    GROUP BY OwnerUserId
), CommentRanking AS (
    SELECT 
        UserId,
        Text AS LatestComment,
        CreationDate,
        ROW_NUMBER() OVER (PARTITION BY UserId ORDER BY CreationDate DESC) AS CommentRank
    FROM Comments
)
SELECT 
    u.Id,
    u.DisplayName,
    COALESCE(u.Location, 'Unknown') AS UserLocation,
    u.Reputation,
    bs.TotalBadges,
    bs.GoldBadges,
    pa.QuestionsAsked,
    pa.AnswersProvided,
    pa.HighestPostScore,
    cr.LatestComment,
    (SELECT COUNT(*) FROM Votes v WHERE v.UserId = u.Id AND v.VoteTypeId = 2) AS UpvotesGiven,
    (SELECT COUNT(*) FROM Votes v WHERE v.PostId IN (SELECT Id FROM Posts WHERE OwnerUserId = u.Id) AND v.VoteTypeId = 2) AS UpvotesReceived,
    STRING_AGG(DISTINCT ph.Text, '; ') FILTER (WHERE ph.PostHistoryTypeId = 5) AS RecentEdits,
    COUNT(DISTINCT CASE WHEN p.ClosedDate IS NOT NULL THEN p.Id END) AS ClosedPosts,
    AVG(LENGTH(p.Tags) - LENGTH(REPLACE(p.Tags, '><', '')) + 1) AS AvgTagsPerQuestion
FROM Users u
LEFT JOIN UserBadgeStats bs ON u.Id = bs.UserId
LEFT JOIN PostActivity pa ON u.Id = pa.OwnerUserId
LEFT JOIN CommentRanking cr ON u.Id = cr.UserId AND cr.CommentRank = 1
LEFT JOIN Posts p ON u.Id = p.OwnerUserId
LEFT JOIN PostHistory ph ON p.Id = ph.PostId AND ph.CreationDate > (CURRENT_DATE - INTERVAL '6 months')
WHERE u.Reputation > 1000
  AND (pa.QuestionsAsked > 10 OR pa.AnswersProvided > 50)
  AND (bs.GoldBadges >= 1 OR bs.SilverBadges >= 5)
  AND EXISTS (SELECT 1 FROM Posts p2 WHERE p2.OwnerUserId = u.Id AND p2.CreationDate > '2020-01-01')
GROUP BY u.Id, u.DisplayName, u.Location, u.Reputation, bs.TotalBadges, bs.GoldBadges, pa.QuestionsAsked, pa.AnswersProvided, pa.HighestPostScore, cr.LatestComment
HAVING AVG(LENGTH(p.Tags) - LENGTH(REPLACE(p.Tags, '><', '')) + 1) BETWEEN 1 AND 5
   AND COUNT(DISTINCT ph.Id) FILTER (WHERE ph.PostHistoryTypeId = 5) > 3
ORDER BY u.Reputation DESC, pa.HighestPostScore DESC
LIMIT 100
UNION ALL
SELECT 
    u.Id,
    u.DisplayName,
    COALESCE(u.Location, 'Unknown'),
    u.Reputation,
    0,
    0,
    0,
    0,
    0,
    NULL,
    0,
    0,
    NULL,
    0,
    0
FROM Users u
WHERE u.Reputation > 10000
  AND NOT EXISTS (SELECT 1 FROM Posts WHERE OwnerUserId = u.Id)
ORDER BY Reputation DESC;
