-- {"query": "5035.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gpt-5-nano", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2026, "output_tokens": 710} 
WITH TopQuestions AS (
  SELECT
    p.Id AS PostId,
    p.Title,
    p.Tags,
    p.CreationDate,
    p.Score,
    p.ViewCount,
    p.OwnerUserId,
    u.DisplayName AS OwnerName,
    p.LastActivityDate,
    p.CommentCount,
    p.AnswerCount,
    ROW_NUMBER() OVER (PARTITION BY p.OwnerUserId ORDER BY p.Score DESC, p.ViewCount DESC, p.CreationDate DESC) AS rn
  FROM Posts p
  LEFT JOIN Users u ON p.OwnerUserId = u.Id
  WHERE p.PostTypeId = 1 -- Questions
    AND p.ClosedDate IS NULL
),
Engagement AS (
  SELECT
    q.PostId,
    q.Title,
    q.OwnerUserId,
    q.OwnerName,
    q.CreationDate,
    q.ViewCount,
    q.Score,
    COALESCE(a.AnswerCount, 0) AS AnswerCount,
    COALESCE(v.UpModCount, 0) AS UpModCount,
    COALESCE(v.DownModCount, 0) AS DownModCount,
    STRING_AGG(CONCAT(CONCAT('u', CAST(v.UserId AS VARCHAR)), ':', v.VoteTypeId), ',') AS VoteSignature
  FROM TopQuestions q
  LEFT JOIN (
    SELECT
      p.ParentId AS PostId, -- parent is the question for answers
      COUNT(*) AS AnswerCount
    FROM Posts p
    WHERE p.PostTypeId = 2
    GROUP BY p.ParentId
  ) a ON a.PostId = q.PostId
  LEFT JOIN (
    SELECT
      PostId,
      SUM(CASE WHEN VoteTypeId = 2 THEN 1 ELSE 0 END) AS UpModCount,
      SUM(CASE WHEN VoteTypeId = 3 THEN 1 ELSE 0 END) AS DownModCount
    FROM Votes
    GROUP BY PostId
  ) v ON v.PostId = q.PostId
  GROUP BY
    q.PostId, q.Title, q.OwnerUserId, q.OwnerName, q.CreationDate, q.ViewCount, q.Score, a.AnswerCount, v.UpModCount, v.DownModCount
),
Filtered AS (
  SELECT *
  FROM Engagement
  WHERE Score > 0 OR UpModCount > 0
)
SELECT
  q.PostId,
  q.Title,
  q.OwnerName,
  q.CreationDate,
  q.ViewCount,
  q.Score,
  q.AnswerCount,
  q.UpModCount,
  q.DownModCount,
  q.VoteSignature,
  (SELECT COUNT(*) FROM Comments c WHERE c.PostId = q.PostId) AS CommentCount,
  (SELECT MAX(CASE WHEN vt.Id = 2 THEN c.CreationDate END)
     FROM Votes v2
     JOIN VoteTypes vt ON v2.VoteTypeId = vt.Id
     WHERE v2.PostId = q.PostId AND vt.Id = 2) AS LastUpvoteDate,
  (SELECT STRING_AGG(CAST(v.UserId AS VARCHAR), ',')
     FROM Votes v
     WHERE v.PostId = q.PostId AND v.VoteTypeId IN (2,3)) AS Voters
FROM Filtered q
ORDER BY q.Score DESC, q.ViewCount DESC
LIMIT 100;