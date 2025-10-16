-- {"query": "22058.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "grok-code-fast", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2204, "output_tokens": 1494} 

WITH UserPostStats AS (
    SELECT OwnerUserId,
           COUNT(*) AS NumPosts,
           SUM(Score) AS TotalScore,
           AVG(LENGTH(COALESCE(Body, ''))) AS AvgBodyLength,
           CASE WHEN STRING_AGG(DISTINCT UNNEST(STRING_TO_ARRAY(SUBSTRING(COALESCE(Tags, '<><>'), 2, LENGTH(COALESCE(Tags, '<><>'))-2), '><')), ', ') IS NULL THEN 'No tags' ELSE STRING_AGG(DISTINCT UNNEST(STRING_TO_ARRAY(SUBSTRING(COALESCE(Tags, '<><>'), 2, LENGTH(COALESCE(Tags, '<><>'))-2), '><')), ', ') END AS UniqueTags,
           MAX(CreationDate) AS LastPostDate
    FROM Posts
    WHERE PostTypeId IN (1,2) AND OwnerUserId IS NOT NULL
    GROUP BY OwnerUserId
),
UserCommentStats AS (
    SELECT UserId,
           COUNT(*) AS NumComments,
           SUM(COALESCE(Score, 0)) AS TotalCommentScore,
           AVG(LENGTH(COALESCE(Text, ''))) AS AvgCommentLength
    FROM Comments
    WHERE UserId IS NOT NULL
    GROUP BY UserId
),
UserVoteStats AS (
    SELECT p.OwnerUserId,
           SUM(CASE WHEN v.VoteTypeId = 2 THEN 1 ELSE 0 END) AS UpVotesReceived,
           SUM(CASE WHEN v.VoteTypeId = 3 THEN 1 ELSE 0 END) AS DownVotesReceived,
           SUM(CASE WHEN v.VoteTypeId = 1 THEN 1 ELSE 0 END) AS AcceptedAnswers,
           COUNT(*) AS TotalVotesReceived
    FROM Votes v
    JOIN Posts p ON v.PostId = p.Id
    WHERE p.OwnerUserId IS NOT NULL
    GROUP BY p.OwnerUserId
),
UserBadgeStats AS (
    SELECT UserId,
           COUNT(*) AS NumBadges,
           SUM(CASE WHEN Class = 1 THEN 10 WHEN Class = 2 THEN 5 ELSE 1 END) AS BadgePoints,
           STRING_AGG(Name, '; ') AS BadgeList
    FROM Badges
    GROUP BY UserId
),
EngagementCTE AS (
    SELECT u.Id,
           COALESCE(ups.NumPosts, 0) + COALESCE(ucs.NumComments, 0) AS TotalActivity,
           u.Reputation + COALESCE(ups.TotalScore, 0) * 2 + COALESCE(uvs.UpVotesReceived, 0) - COALESCE(uvs.DownVotesReceived, 0) * 2 + COALESCE(ubs.BadgePoints, 0) AS EngagementScore
    FROM Users u
    LEFT JOIN UserPostStats ups ON u.Id = ups.OwnerUserId
    LEFT JOIN UserCommentStats ucs ON u.Id = ucs.UserId
    LEFT JOIN UserVoteStats uvs ON u.Id = uvs.OwnerUserId
    LEFT JOIN UserBadgeStats ubs ON u.Id = ubs.UserId
)
(
    SELECT u.Id, u.DisplayName, u.Reputation, u.CreationDate,
           COALESCE(ups.NumPosts, 0) AS NumPosts,
           COALESCE(ups.TotalScore, 0) AS TotalPostScore,
           COALESCE(ups.AvgBodyLength, 0) AS AvgBodyLength,
           COALESCE(ups.UniqueTags, 'No tags') AS UniqueTags,
           (SELECT COUNT(*) FROM Comments c WHERE c.UserId = u.Id AND c.Score > (SELECT AVG(Score) FROM Comments WHERE Score IS NOT NULL)) AS HighScoreComments,
           COALESCE(ucs.NumComments, 0) AS NumComments,
           COALESCE(ucs.TotalCommentScore, 0) AS TotalCommentScore,
           COALESCE(ucs.AvgCommentLength, 0) AS AvgCommentLength,
           COALESCE(uvs.UpVotesReceived, 0) AS UpVotesReceived,
           COALESCE(uvs.DownVotesReceived, 0) AS DownVotesReceived,
           COALESCE(uvs.AcceptedAnswers, 0) AS AcceptedAnswers,
           COALESCE(uvs.TotalVotesReceived, 0) AS TotalVotesReceived,
           COALESCE(ubs.NumBadges, 0) AS NumBadges,
           COALESCE(ubs.BadgePoints, 0) AS BadgePoints,
           COALESCE(ubs.BadgeList, 'No badges') AS BadgeList,
           e.TotalActivity,
           e.EngagementScore,
           ROW_NUMBER() OVER (ORDER BY u.Reputation DESC, e.EngagementScore DESC) AS OverallRank,
           DENSE_RANK() OVER (ORDER BY LENGTH(COALESCE(ups.UniqueTags, '')) DESC) AS TagDiversityRank,
           RANK() OVER (PARTITION BY EXTRACT(YEAR FROM u.CreationDate) ORDER BY e.TotalActivity DESC) AS YearlyActivityRank,
           (SELECT COUNT(*) FROM Posts p WHERE p.OwnerUserId = u.Id AND p.Score > (SELECT AVG(Score) FROM Posts WHERE OwnerUserId IS NOT NULL)) AS HighScorePosts,
           CASE WHEN u.Reputation > (SELECT AVG(Reputation) FROM Users) THEN 'High Rep' WHEN u.Reputation BETWEEN 100 AND (SELECT AVG(Reputation) FROM Users) THEN 'Medium Rep' ELSE 'Low Rep' END AS RepCategory
    FROM Users u
    LEFT JOIN UserPostStats ups ON u.Id = ups.OwnerUserId
    LEFT JOIN UserCommentStats ucs ON u.Id = ucs.UserId
    LEFT JOIN UserVoteStats uvs ON u.Id = uvs.OwnerUserId
    LEFT JOIN UserBadgeStats ubs ON u.Id = ubs.UserId
    JOIN EngagementCTE e ON u.Id = e.Id
    WHERE (COALESCE(ups.NumPosts, 0) > 0 OR COALESCE(ucs.NumComments, 0) > 0) AND u.LastAccessDate > u.CreationDate + INTERVAL '30 days'
    ORDER BY u.Reputation DESC, e.EngagementScore DESC
    LIMIT 500
)
EXCEPT
(
    SELECT u.Id, u.DisplayName, u.Reputation, u.CreationDate,
           0 AS NumPosts,
           0 AS TotalPostScore,
           0 AS AvgBodyLength,
           'No tags' AS UniqueTags,
           0 AS HighScoreComments,
           0 AS NumComments,
           0 AS TotalCommentScore,
           0 AS AvgCommentLength,
           0 AS UpVotesReceived,
           0 AS DownVotesReceived,
           0 AS AcceptedAnswers,
           0 AS TotalVotesReceived,
           0 AS NumBadges,
           0 AS BadgePoints,
           'No badges' AS BadgeList,
           0 AS TotalActivity,
           0 AS EngagementScore,
           0 AS OverallRank,
           0 AS TagDiversityRank,
           0 AS YearlyActivityRank,
           0 AS HighScorePosts,
           'Low Rep' AS RepCategory
    FROM Users u
    WHERE u.Reputation < 10 AND u.Views < 10
);
