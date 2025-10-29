-- {"query": "5744.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gpt-5-nano", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2026, "output_tokens": 913} 
WITH
RecentTopQuestions AS (
  SELECT
    p.Id AS QuestionId,
    p.Title,
    p.CreationDate,
    p.ViewCount,
    p.Score,
    p.OwnerUserId,
    p.Tags,
    ROW_NUMBER() OVER (ORDER BY p.Score DESC, p.ViewCount DESC, p.CreationDate DESC) AS rn
  FROM Posts p
  WHERE p.PostTypeId = 1
),
HotTags AS (
  SELECT
    t.TagName,
    SUM(t.Count) AS TagTotal
  FROM Tags t
  GROUP BY t.TagName
),
QuestionAnswerStats AS (
  SELECT
    q.QuestionId,
    q.Title,
    q.CreationDate,
    q.ViewCount,
    q.Score,
    q.OwnerUserId,
    q.Tags,
    COALESCE(a.AnswerCount, 0) AS AnswerCount,
    COALESCE(v.UpMod, 0) AS UpModCount,
    COALESCE(v.DownMod, 0) AS DownModCount,
    CASE
      WHEN q.OwnerUserId IS NULL THEN 'Unknown'
      ELSE COALESCE(u.DisplayName, 'User-' || q.OwnerUserId)
    END AS OwnerDisplayName
  FROM RecentTopQuestions q
  LEFT JOIN (
    SELECT ParentId AS QuestionId, COUNT(*) AS AnswerCount
    FROM Posts
    WHERE PostTypeId = 2
    GROUP BY ParentId
  ) a ON a.QuestionId = q.QuestionId
  LEFT JOIN (
    SELECT PostId, SUM(CASE WHEN VoteTypeId = 2 THEN 1 ELSE 0 END) AS UpMod,
                   SUM(CASE WHEN VoteTypeId = 3 THEN 1 ELSE 0 END) AS DownMod
    FROM Votes
    GROUP BY PostId
  ) v ON v.PostId = q.QuestionId
  LEFT JOIN Users u ON u.Id = q.OwnerUserId
),
CrossReview AS (
  SELECT
    q.QuestionId,
    q.Title,
    q.CreationDate,
    q.ViewCount,
    q.Score,
    q.OwnerUserId,
    q.Tags,
    q.AnswerCount,
    q.UpModCount,
    q.DownModCount,
    q.OwnerDisplayName,
    COUNT(ci.Id) AS CommentCount,
    MAX(c.CreationDate) AS LastCommentDate
  FROM QuestionAnswerStats q
  LEFT JOIN Comments ci ON ci.PostId = q.QuestionId
  LEFT JOIN Posts c ON c.Id = ci.PostId
  GROUP BY
    q.QuestionId, q.Title, q.CreationDate, q.ViewCount, q.Score,
    q.OwnerUserId, q.Tags, q.AnswerCount, q.UpModCount, q.DownModCount,
    q.OwnerDisplayName
),
ComplexBenchmark AS (
  SELECT
    cr.QuestionId,
    cr.Title,
    cr.CreationDate,
    cr.ViewCount,
    cr.Score,
    cr.OwnerUserId,
    cr.Tags,
    cr.AnswerCount,
    cr.UpModCount,
    cr.DownModCount,
    cr.OwnerDisplayName,
    cr.CommentCount,
    cr.LastCommentDate,
    -- Window function to derive a running metric over time
    SUM(cr.Score) OVER (PARTITION BY cr.OwnerUserId ORDER BY cr.CreationDate ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW) AS RunningScore
  FROM CrossReview cr
),
FinalOutput AS (
  SELECT
    cq.QuestionId,
    cq.Title,
    cq.CreationDate,
    cq.ViewCount,
    cq.Score,
    cq.OwnerUserId,
    cq.OwnerDisplayName,
    cq.Tags,
    cq.AnswerCount,
    cq.UpModCount,
    cq.DownModCount,
    cq.CommentCount,
    cq.LastCommentDate,
    cq.RunningScore,
    -- Complex predicate: include only questions with at least one answer and either high score or recent activity
    CASE
      WHEN cq.AnswerCount > 0 AND (cq.Score > 5 OR EXTRACT(EPOCH FROM (cast('2024-10-01 12:34:56' as timestamp) - cq.LastCommentDate)) < 86400)
        THEN TRUE
      ELSE FALSE
    END AS IncludeInBenchmark
  FROM ComplexBenchmark cq
)
SELECT
  *
FROM FinalOutput
WHERE IncludeInBenchmark
ORDER BY RunningScore DESC, CreationDate DESC
LIMIT 100;