-- {"query": "34082.sql", "dataset": "stackoverflow", "version": "v1.1", "prompt": "p2", "model": "gpt-4.1-mini", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 1986, "output_tokens": 709} 
WITH RecentQuestions AS (
    SELECT p.Id, p.Title, p.OwnerUserId, p.CreationDate, p.Score, p.ViewCount, p.AnswerCount, p.Tags,
           u.DisplayName, u.Reputation
    FROM Posts p
    JOIN Users u ON p.OwnerUserId = u.Id
    WHERE p.PostTypeId = 1
      AND p.CreationDate > cast('2024-10-01 12:34:56' as timestamp) - INTERVAL '6 months'
      AND p.Score >= 5
), AnswerCounts AS (
    SELECT ParentId, COUNT(*) AS TotalAnswers, AVG(Score) AS AvgAnswerScore
    FROM Posts
    WHERE PostTypeId = 2
    GROUP BY ParentId
), TopBadges AS (
    SELECT UserId, Name, COUNT(*) AS BadgeCount
    FROM Badges
    WHERE Date > cast('2024-10-01 12:34:56' as timestamp) - INTERVAL '1 year'
    GROUP BY UserId, Name
    HAVING COUNT(*) > 3
), QuestionVotes AS (
    SELECT v.PostId,
           SUM(CASE WHEN vt.Name = 'UpMod' THEN 1 ELSE 0 END) AS UpVotes,
           SUM(CASE WHEN vt.Name = 'DownMod' THEN 1 ELSE 0 END) AS DownVotes,
           SUM(CASE WHEN vt.Name = 'Favorite' THEN 1 ELSE 0 END) AS Favorites
    FROM Votes v
    JOIN VoteTypes vt ON v.VoteTypeId = vt.Id
    GROUP BY v.PostId
), CommentStats AS (
    SELECT c.PostId, COUNT(*) AS CommentCount, AVG(c.Score) AS AvgCommentScore
    FROM Comments c
    GROUP BY c.PostId
)
SELECT
    rq.Id AS QuestionId,
    rq.Title,
    rq.CreationDate,
    rq.Score AS QuestionScore,
    rq.ViewCount,
    rq.AnswerCount,
    rq.Tags,
    rq.DisplayName AS QuestionOwner,
    rq.Reputation AS OwnerReputation,
    COALESCE(ac.TotalAnswers, 0) AS TotalAnswersOnQuestion,
    COALESCE(ac.AvgAnswerScore, 0) AS AverageAnswerScore,
    COALESCE(qv.UpVotes, 0) AS TotalUpVotes,
    COALESCE(qv.DownVotes, 0) AS TotalDownVotes,
    COALESCE(qv.Favorites, 0) AS TotalFavorites,
    COALESCE(cs.CommentCount, 0) AS TotalComments,
    COALESCE(cs.AvgCommentScore, 0) AS AvgCommentScore,
    COALESCE(MAX(tb.BadgeCount), 0) AS MaxBadgeCount,
    MAX(tb.Name) AS MostFrequentBadge
FROM RecentQuestions rq
LEFT JOIN AnswerCounts ac ON rq.Id = ac.ParentId
LEFT JOIN QuestionVotes qv ON rq.Id = qv.PostId
LEFT JOIN CommentStats cs ON rq.Id = cs.PostId
LEFT JOIN TopBadges tb ON rq.OwnerUserId = tb.UserId
GROUP BY
    rq.Id, rq.Title, rq.CreationDate, rq.Score, rq.ViewCount, rq.AnswerCount, rq.Tags,
    rq.DisplayName, rq.Reputation, ac.TotalAnswers, ac.AvgAnswerScore,
    qv.UpVotes, qv.DownVotes, qv.Favorites, cs.CommentCount, cs.AvgCommentScore
ORDER BY rq.Score DESC, rq.ViewCount DESC
LIMIT 100;