-- {"query": "35071.sql", "dataset": "stackoverflow", "version": "v1.1", "prompt": "p2", "model": "gpt-4.1", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 1986, "output_tokens": 575} 
WITH
TopUsers AS (
    SELECT Id, DisplayName, Reputation
    FROM Users
    WHERE Reputation > 10000
),
RecentQuestions AS (
    SELECT p.Id, p.OwnerUserId, p.Title, p.Score, p.ViewCount, p.AnswerCount, p.CreationDate, p.Tags
    FROM Posts p
    WHERE p.PostTypeId = 1
      AND p.CreationDate >= cast('2024-10-01 12:34:56' as timestamp) - INTERVAL '30 days'
      AND p.ViewCount > 100
),
QuestionVotes AS (
    SELECT v.PostId, SUM(CASE WHEN v.VoteTypeId = 2 THEN 1 ELSE 0 END) AS UpVotes,
                       SUM(CASE WHEN v.VoteTypeId = 3 THEN 1 ELSE 0 END) AS DownVotes
    FROM Votes v
    WHERE v.CreationDate >= cast('2024-10-01 12:34:56' as timestamp) - INTERVAL '30 days'
    GROUP BY v.PostId
),
AnswerStats AS (
    SELECT a.ParentId AS QuestionId,
           COUNT(a.Id) AS TotalAnswers,
           MAX(a.Score) AS MaxAnswerScore,
           AVG(a.Score) AS AvgAnswerScore
    FROM Posts a
    WHERE a.PostTypeId = 2
      AND a.CreationDate >= cast('2024-10-01 12:34:56' as timestamp) - INTERVAL '30 days'
    GROUP BY a.ParentId
),
CommentsPerQuestion AS (
    SELECT c.PostId, COUNT(*) AS CommentCount
    FROM Comments c
    WHERE c.CreationDate >= cast('2024-10-01 12:34:56' as timestamp) - INTERVAL '30 days'
    GROUP BY c.PostId
),
LinkedQuestions AS (
    SELECT pl.PostId, COUNT(*) AS LinkCount
    FROM PostLinks pl
    WHERE pl.LinkTypeId = 1
    GROUP BY pl.PostId
)
SELECT 
    u.DisplayName,
    u.Reputation,
    rq.Id AS QuestionId,
    rq.Title,
    rq.Score AS QuestionScore,
    rq.ViewCount,
    rq.AnswerCount,
    qs.UpVotes,
    qs.DownVotes,
    asn.TotalAnswers,
    asn.MaxAnswerScore,
    asn.AvgAnswerScore,
    coalesce(cq.CommentCount, 0) AS CommentCount,
    coalesce(lq.LinkCount, 0) AS LinkedQuestionsCount,
    rq.CreationDate,
    rq.Tags
FROM RecentQuestions rq
JOIN TopUsers u ON rq.OwnerUserId = u.Id
LEFT JOIN QuestionVotes qs ON rq.Id = qs.PostId
LEFT JOIN AnswerStats asn ON rq.Id = asn.QuestionId
LEFT JOIN CommentsPerQuestion cq ON rq.Id = cq.PostId
LEFT JOIN LinkedQuestions lq ON rq.Id = lq.PostId
ORDER BY u.Reputation DESC, rq.ViewCount DESC, rq.Score DESC
LIMIT 100;