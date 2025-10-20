-- {"query": "6042.sql", "dataset": "stackoverflow", "version": "v1.1", "prompt": "p1", "model": "gpt-5-nano", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2026, "output_tokens": 606} 
WITH RankedQuestions AS (
  SELECT
    p.Id AS PostId,
    p.Title,
    p.CreationDate,
    p.Score,
    p.ViewCount,
    p.Tags,
    p.OwnerUserId,
    u.DisplayName AS OwnerName,
    p.LastActivityDate,
    ROW_NUMBER() OVER (ORDER BY p.Score DESC, p.ViewCount DESC, p.LastActivityDate DESC) AS rn
  FROM Posts p
  LEFT JOIN Users u ON p.OwnerUserId = u.Id
  WHERE p.PostTypeId = 1 -- questions
),
QuestionActivity AS (
  SELECT
    rq.PostId,
    rq.Title,
    rq.CreationDate,
    rq.Score,
    rq.ViewCount,
    rq.OwnerName,
    rq.OwnerUserId,
    rq.LastActivityDate,
    -- total number of answers for the question
    (SELECT COUNT(*) FROM Posts a WHERE a.ParentId = rq.PostId AND a.PostTypeId = 2) AS AnswerCount,
    -- number of comments on the question
    (SELECT COUNT(*) FROM Comments c WHERE c.PostId = rq.PostId) AS CommentCount,
    -- number of unique voters who upvoted or downvoted the question (if available)
    (SELECT COUNT(*) FROM Votes v WHERE v.PostId = rq.PostId AND v.VoteTypeId IN (2,3)) AS VoteCount
  FROM RankedQuestions rq
),
Engagement AS (
  SELECT
    qa.PostId,
    qa.Title,
    qa.CreationDate,
    qa.Score,
    qa.ViewCount,
    qa.OwnerName,
    qa.OwnerUserId,
    qa.LastActivityDate,
    qa.AnswerCount,
    qa.CommentCount,
    qa.VoteCount,
    -- windowed metrics: rolling 7-day activity count (posts created in last 7 days relative to each post)
    SUM(CASE WHEN p.CreationDate >= DATEADD(day, -7, qa.CreationDate) THEN 1 ELSE 0 END)
      OVER (ORDER BY qa.CreationDate ROWS BETWEEN 6 PRECEDING AND CURRENT ROW) AS SevenDayNewPosts,
    -- string-based transformation: tags to a normalized array-like string
    LOWER(REPLACE(REPLACE(qa.Tags, '><', ','), '<', '')) AS NormalizedTags
  FROM QuestionActivity qa
  LEFT JOIN Posts p ON p.Id = qa.PostId
)
SELECT
  e.PostId,
  e.Title,
  e.CreationDate,
  e.LastActivityDate,
  e.OwnerName,
  e.ViewCount,
  e.Score,
  e.AnswerCount,
  e.CommentCount,
  e.VoteCount,
  e.SevenDayNewPosts,
  e.NormalizedTags
FROM Engagement e
WHERE e.SevenDayNewPosts >= 0
ORDER BY e.CreationDate DESC
LIMIT 100;