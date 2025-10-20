-- {"query": "35053.sql", "dataset": "stackoverflow", "version": "v1.1", "prompt": "p2", "model": "gpt-4.1", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 1986, "output_tokens": 568} 
WITH TopTags AS (
    SELECT t.TagName, t.Count
    FROM Tags t
    WHERE t.Count > 1000
    ORDER BY t.Count DESC
    LIMIT 10
), 
RecentQuestions AS (
    SELECT p.Id AS QuestionId, p.Title, p.CreationDate, p.OwnerUserId, p.Tags
    FROM Posts p
    WHERE p.PostTypeId = 1
      AND p.CreationDate > CURRENT_DATE - INTERVAL '30 days'
), 
TagQuestions AS (
    SELECT rq.QuestionId, rq.Title, rq.CreationDate, rq.OwnerUserId, tt.TagName
    FROM RecentQuestions rq
    JOIN TopTags tt 
        ON ('<' || tt.TagName || '>') = ANY(string_to_array(substring(rq.Tags, 2, length(rq.Tags)-2), '><'))
), 
AnswerStats AS (
    SELECT p.ParentId AS QuestionId, COUNT(*) AS AnswerCount, AVG(p.Score) AS AvgAnswerScore
    FROM Posts p
    WHERE p.PostTypeId = 2
    GROUP BY p.ParentId
), 
VoteStats AS (
    SELECT v.PostId, 
           SUM(CASE WHEN v.VoteTypeId = 2 THEN 1 ELSE 0 END) AS Upvotes,
           SUM(CASE WHEN v.VoteTypeId = 3 THEN 1 ELSE 0 END) AS Downvotes
    FROM Votes v
    GROUP BY v.PostId
),
QuestionCommentStats AS (
    SELECT c.PostId, COUNT(1) AS CommentCount, MAX(c.Score) AS MaxCommentScore
    FROM Comments c
    GROUP BY c.PostId
)
SELECT 
    tq.TagName,
    tq.QuestionId,
    tq.Title,
    tq.CreationDate,
    u.DisplayName AS Author,
    COALESCE(a.AnswerCount, 0) AS AnswerCount,
    ROUND(COALESCE(a.AvgAnswerScore, 0),2) AS AvgAnswerScore,
    COALESCE(vs.Upvotes, 0) AS Upvotes,
    COALESCE(vs.Downvotes, 0) AS Downvotes,
    COALESCE(qcs.CommentCount, 0) AS CommentCount,
    COALESCE(qcs.MaxCommentScore, 0) AS MaxCommentScore
FROM TagQuestions tq
LEFT JOIN Users u ON tq.OwnerUserId = u.Id
LEFT JOIN AnswerStats a ON tq.QuestionId = a.QuestionId
LEFT JOIN VoteStats vs ON tq.QuestionId = vs.PostId
LEFT JOIN QuestionCommentStats qcs ON tq.QuestionId = qcs.PostId
ORDER BY tq.TagName, tq.CreationDate DESC, tq.QuestionId
LIMIT 1000;