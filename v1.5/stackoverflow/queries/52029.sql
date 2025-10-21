-- {"query": "52029.sql", "dataset": "stackoverflow", "version": "v1.1", "prompt": "p2", "model": "grok-code-fast", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2165, "output_tokens": 568} 
WITH top_questions AS (
    SELECT p.Id, p.Title, p.Tags, p.Score, p.ViewCount, p.AnswerCount, p.CreationDate, u.DisplayName AS OwnerName, u.Reputation AS OwnerRep
    FROM Posts p
    JOIN Users u ON p.OwnerUserId = u.Id
    WHERE p.PostTypeId = 1
      AND p.ClosedDate IS NULL
      AND p.CreationDate >= '2023-01-01'
      AND p.AnswerCount > 5
      AND p.ViewCount > 100
),
voted_answers AS (
    SELECT v.PostId AS AnswerId, COUNT(*) AS UpvoteCount
    FROM Votes v
    WHERE v.VoteTypeId = 2
    GROUP BY v.PostId
),
commented_posts AS (
    SELECT c.PostId, COUNT(*) AS CommentCount, AVG(c.Score) AS AvgCommentScore
    FROM Comments c
    GROUP BY c.PostId
),
tag_usage AS (
    SELECT unnest(string_to_array(substring(p.Tags, 2, length(p.Tags)-2), '><')) AS TagName, p.Id AS PostId
    FROM Posts p
    WHERE p.PostTypeId = 1 AND p.Tags IS NOT NULL
),
tag_stats AS (
    SELECT TagName, COUNT(*) AS QuestionCount, AVG(p.Score) AS AvgScore
    FROM tag_usage tu
    JOIN Posts p ON tu.PostId = p.Id
    GROUP BY TagName
    HAVING COUNT(*) > 10
)
SELECT tq.Id, tq.Title, tq.Tags, tq.Score, tq.ViewCount, tq.AnswerCount, tq.CreationDate, tq.OwnerName, tq.OwnerRep,
       COALESCE(va.UpvoteCount, 0) AS TotalUpvotesOnAnswers,
       COALESCE(cp.CommentCount, 0) AS CommentCount, COALESCE(cp.AvgCommentScore, 0) AS AvgCommentScore,
       ts.AvgScore AS TagAvgScore,
       (tq.Score / NULLIF(tq.ViewCount, 0)) * 1000 AS ScorePerViewRatio
FROM top_questions tq
LEFT JOIN (
    SELECT p.ParentId, SUM(va.UpvoteCount) AS UpvoteCount
    FROM voted_answers va
    JOIN Posts p ON va.AnswerId = p.Id
    GROUP BY p.ParentId
) va ON tq.Id = va.ParentId
LEFT JOIN commented_posts cp ON tq.Id = cp.PostId
LEFT JOIN tag_usage tu ON tq.Id = tu.PostId
LEFT JOIN tag_stats ts ON tu.TagName = ts.TagName
ORDER BY ScorePerViewRatio DESC, tq.Score DESC
LIMIT 50;