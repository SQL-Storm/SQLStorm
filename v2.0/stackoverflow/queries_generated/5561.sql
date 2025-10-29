-- {"query": "5561.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gpt-5-nano", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2026, "output_tokens": 841} 
WITH recent_questions AS (
  SELECT
    p.Id AS PostId,
    p.Title,
    p.Tags,
    p.CreationDate,
    p.OwnerUserId,
    p.ViewCount,
    p.Score,
    p.CommentCount,
    p.AnswerCount,
    p.LastActivityDate,
    p.FavoriteCount,
    p.ContentLicense
  FROM Posts p
  WHERE p.PostTypeId = 1 -- questions
),
tag_stats AS (
  SELECT
    t.TagName,
    t.Count AS TagCount,
    AVG(p.Score) AS AvgScorePerQuestion,
    SUM(p.ViewCount) AS TotalViews
  FROM (
    SELECT
      unnest string_to_array(substring(p.Tags, 2, length(p.Tags)-2), '<>') AS TagName,
      p.Score,
      p.ViewCount
    FROM Posts p
    WHERE p.PostTypeId = 1
  ) AS s
  JOIN LATERAL (SELECT TagName) AS t ON true
  GROUP BY t.TagName
),
top_contributors AS (
  SELECT
    u.Id AS UserId,
    u.DisplayName,
    SUM(p.Score) AS TotalScoreFromQuestions,
    SUM(p.ViewCount) AS TotalViewsFromQuestions
  FROM Users u
  LEFT JOIN Posts p ON p.OwnerUserId = u.Id AND p.PostTypeId = 1
  GROUP BY u.Id, u.DisplayName
  HAVING SUM(p.Score) > 50
),
complex_aggregate AS (
  SELECT
    q.PostId,
    q.Title,
    q.CreationDate AS QuestionCreated,
    q.LastActivityDate AS LastActive,
    q.ViewCount,
    q.Score,
    q.CommentCount,
    q.AnswerCount,
    COALESCE(v.PositiveVotes, 0) AS Upvotes,
    COALESCE(v.NegativeVotes, 0) AS Downvotes,
    CASE
      WHEN q.Score > 0 THEN 'positive'
      WHEN q.Score = 0 THEN 'neutral'
      ELSE 'negative'
    END AS ScoreMood,
    ARRAY_AGG(DISTINCT ltype.Name) FILTER (WHERE ltype.Name IS NOT NULL) AS LinkTypes,
    EXISTS (
      SELECT 1
      FROM PostLinks pl
      WHERE pl.PostId = q.PostId AND pl.RelatedPostId = q.Id
    ) AS HasSelfLink
  FROM recent_questions q
  LEFT JOIN (
    SELECT PostId, SUM(CASE WHEN vt.Id = 2 THEN 1 ELSE 0 END) AS PositiveVotes,
           SUM(CASE WHEN vt.Id = 3 THEN 1 ELSE 0 END) AS NegativeVotes
    FROM Votes v
    JOIN VoteTypes vt ON vt.Id = v.VoteTypeId
    GROUP BY PostId
  ) v ON v.PostId = q.PostId
  LEFT JOIN PostLinks pl ON pl.PostId = q.PostId
  LEFT JOIN LinkTypes ltype ON ltype.Id = pl.LinkTypeId
  GROUP BY q.PostId, q.Title, q.CreationDate, q.LastActivityDate, q.ViewCount, q.Score, q.CommentCount, q.AnswerCount, v.PositiveVotes, v.NegativeVotes
)
SELECT
  cq.PostId,
  cq.Title,
  cq.QuestionCreated,
  cq.LastActive,
  cq.ViewCount,
  cq.Score,
  cq.CommentCount,
  cq.AnswerCount,
  cq.Upvotes,
  cq.Downvotes,
  cq.ScoreMood,
  cq.LinkTypes,
  cq.HasSelfLink,
  tc.TagName,
  tc.TagCount,
  tc.AvgScorePerQuestion,
  tc.TotalViews,
  tc2.UserId AS TopContributorUserId,
  tc2.DisplayName AS TopContributorName,
  tc2.TotalScoreFromQuestions,
  tc2.TotalViewsFromQuestions
FROM complex_aggregate cq
LEFT JOIN tag_stats tc ON true
LEFT JOIN top_contributors tc2 ON true
ORDER BY cq.LastActive DESC
LIMIT 200;