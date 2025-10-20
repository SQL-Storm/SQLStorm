-- {"query": "34093.sql", "dataset": "stackoverflow", "version": "v1.1", "prompt": "p2", "model": "gpt-4.1-mini", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 1986, "output_tokens": 792} 
WITH RecentHighRepUsers AS (
    SELECT Id, DisplayName, Reputation
    FROM Users
    WHERE Reputation > 50000
      AND CreationDate > '2018-01-01'
), TopTags AS (
    SELECT t.Id, t.TagName, t.Count
    FROM Tags t
    WHERE t.Count > 10000
), TopQuestions AS (
    SELECT p.Id, p.OwnerUserId, p.Title, p.CreationDate, p.Score, p.ViewCount, p.Tags
    FROM Posts p
    JOIN PostTypes pt ON p.PostTypeId = pt.Id
    WHERE pt.Name = 'Question'
      AND p.Score > 50
      AND p.ViewCount > 1000
      AND EXISTS (
        SELECT 1 FROM RecentHighRepUsers rhu WHERE rhu.Id = p.OwnerUserId
      )
), AnswersWithScores AS (
    SELECT a.Id, a.ParentId AS QuestionId, a.OwnerUserId, a.Score, a.CreationDate
    FROM Posts a
    JOIN PostTypes pt ON a.PostTypeId = pt.Id
    WHERE pt.Name = 'Answer'
      AND EXISTS (SELECT 1 FROM TopQuestions tq WHERE tq.Id = a.ParentId)
), UserBadgeCounts AS (
    SELECT b.UserId,
           SUM(CASE WHEN b.Class = 1 THEN 1 ELSE 0 END) AS GoldBadges,
           SUM(CASE WHEN b.Class = 2 THEN 1 ELSE 0 END) AS SilverBadges,
           SUM(CASE WHEN b.Class = 3 THEN 1 ELSE 0 END) AS BronzeBadges
    FROM Badges b
    GROUP BY b.UserId
), QuestionAnswerStats AS (
    SELECT tq.Id AS QuestionId,
           tq.Title,
           tq.OwnerUserId,
           COUNT(a.Id) AS AnswerCount,
           AVG(a.Score) AS AvgAnswerScore,
           MAX(a.Score) AS MaxAnswerScore
    FROM TopQuestions tq
    LEFT JOIN AnswersWithScores a ON a.QuestionId = tq.Id
    GROUP BY tq.Id, tq.Title, tq.OwnerUserId
), RecentComments AS (
    SELECT c.PostId, COUNT(c.Id) AS CommentCount
    FROM Comments c
    WHERE c.CreationDate > cast('2024-10-01 12:34:56' as timestamp) - INTERVAL '60 days'
    GROUP BY c.PostId
), QuestionLinkCounts AS (
    SELECT pl.PostId, COUNT(pl.Id) AS LinkCount
    FROM PostLinks pl
    WHERE pl.LinkTypeId IN (1,3)
    GROUP BY pl.PostId
)
SELECT 
    qas.QuestionId,
    qas.Title,
    u.DisplayName AS QuestionOwner,
    u.Reputation AS QuestionOwnerReputation,
    ubc.GoldBadges,
    ubc.SilverBadges,
    ubc.BronzeBadges,
    qas.AnswerCount,
    COALESCE(qas.AvgAnswerScore, 0) AS AvgAnswerScore,
    COALESCE(qas.MaxAnswerScore, 0) AS MaxAnswerScore,
    COALESCE(rc.CommentCount, 0) AS RecentCommentCount,
    COALESCE(qlc.LinkCount, 0) AS LinkCount,
    tq.ViewCount,
    tq.Tags,
    tq.CreationDate
FROM QuestionAnswerStats qas
JOIN Users u ON qas.OwnerUserId = u.Id
LEFT JOIN UserBadgeCounts ubc ON ubc.UserId = u.Id
LEFT JOIN RecentComments rc ON rc.PostId = qas.QuestionId
LEFT JOIN QuestionLinkCounts qlc ON qlc.PostId = qas.QuestionId
JOIN TopQuestions tq ON tq.Id = qas.QuestionId
ORDER BY qas.AnswerCount DESC, AvgAnswerScore DESC, qas.MaxAnswerScore DESC
LIMIT 100;