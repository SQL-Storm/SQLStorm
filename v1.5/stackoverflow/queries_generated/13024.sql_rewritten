-- {"query": "13024.sql", "dataset": "stackoverflow", "version": "v1.1", "prompt": "p1", "model": "nova-premier", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2142, "output_tokens": 876} 
WITH UserActivity AS (
    SELECT u.Id, u.DisplayName, u.Reputation, u.Views,
           COUNT(DISTINCT b.Id) AS BadgesCount,
           SUM(CASE WHEN b.Class = 1 THEN 1 ELSE 0 END) AS GoldBadges,
           SUM(CASE WHEN b.Class = 2 THEN 1 ELSE 0 END) AS SilverBadges,
           SUM(CASE WHEN b.Class = 3 THEN 1 ELSE 0 END) AS BronzeBadges,
           COUNT(DISTINCT CASE WHEN p.PostTypeId = 1 THEN p.Id END) AS QuestionsCount,
           COUNT(DISTINCT CASE WHEN p.PostTypeId = 2 THEN p.Id END) AS AnswersCount,
           SUM(p.Score) AS TotalScore,
           MAX(p.CreationDate) AS LastPostDate
    FROM Users u
    LEFT JOIN Badges b ON u.Id = b.UserId
    LEFT JOIN Posts p ON u.Id = p.OwnerUserId
    GROUP BY u.Id, u.DisplayName, u.Reputation, u.Views
),
TopPerformers AS (
    SELECT Id, DisplayName, Reputation, BadgesCount, GoldBadges,
           ROW_NUMBER() OVER (ORDER BY Reputation DESC, GoldBadges DESC, BadgesCount DESC) AS PerformanceRank
    FROM UserActivity
    WHERE Views > 0
),
QuestionsWithAnswers AS (
    SELECT p.Id, p.Title, p.Tags,
           COUNT(DISTINCT CASE WHEN p2.PostTypeId = 2 THEN p2.Id END) AS AnswerCount,
           MAX(p2.Score) AS HighestAnswerScore
    FROM Posts p
    LEFT JOIN Posts p2 ON p.Id = p2.ParentId
    WHERE p.PostTypeId = 1 AND p.ClosedDate IS NULL
    GROUP BY p.Id, p.Title, p.Tags
    HAVING COUNT(DISTINCT CASE WHEN p2.PostTypeId = 2 THEN p2.Id END) > 0
),
CommentedPosts AS (
    SELECT p.Id, COUNT(c.Id) AS CommentsCount,
           MAX(c.CreationDate) AS LastCommentDate
    FROM Posts p
    LEFT JOIN Comments c ON p.Id = c.PostId
    GROUP BY p.Id
),
PostMetrics AS (
    SELECT q.Id, q.Title, q.Tags, q.AnswerCount, q.HighestAnswerScore,
           COALESCE(cp.CommentsCount, 0) AS CommentsCount,
           cp.LastCommentDate,
           ROW_NUMBER() OVER (PARTITION BY q.Tags ORDER BY q.AnswerCount DESC, q.HighestAnswerScore DESC) AS TagRank
    FROM QuestionsWithAnswers q
    LEFT JOIN CommentedPosts cp ON q.Id = cp.Id
)
SELECT tp.DisplayName, tp.Reputation, tp.BadgesCount, pm.Title, pm.Tags, pm.AnswerCount, pm.HighestAnswerScore,
       CONCAT(SUBSTRING(u.Location FROM 1 FOR POSITION(',' IN u.Location) - 1), ', ', SUBSTRING(u.Location FROM POSITION(',' IN u.Location) + 2)) AS FormattedLocation,
       CASE 
           WHEN tp.PerformanceRank <= 10 THEN 'Top Contributor'
           WHEN tp.PerformanceRank <= 100 THEN 'Active Contributor'
           ELSE 'Contributor'
       END AS ContributorStatus
FROM TopPerformers tp
JOIN Users u ON tp.Id = u.Id
JOIN PostMetrics pm ON u.Id = pm.Id
WHERE pm.TagRank <= 5
ORDER BY tp.PerformanceRank, pm.TagRank, pm.AnswerCount DESC, pm.HighestAnswerScore DESC;