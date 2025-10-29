-- {"query": "5440.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gpt-5-nano", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2026, "output_tokens": 903} 
WITH
RecentTopQuestions AS (
  SELECT
    p.Id AS PostId,
    p.Title,
    p.CreationDate,
    p.Score,
    p.ViewCount,
    p.Tags,
    p.OwnerUserId,
    p.OwnerDisplayName,
    ROW_NUMBER() OVER (PARTITION BY p.OwnerUserId ORDER BY p.Score DESC, p.CreationDate DESC) AS rn
  FROM Posts p
  WHERE p.PostTypeId = 1 -- Question
    AND p.ClosedDate IS NULL
    AND p.CreationDate >= cast('2024-10-01 12:34:56' as timestamp) - INTERVAL '90 days'
),
TaggedActivity AS (
  SELECT
    p.Id AS PostId,
    unnest(string_to_array(substr(p.Tags, 2, length(p.Tags) - 2), '><')) AS Tag
  FROM Posts p
  WHERE p.PostTypeId = 1
),
TopTags AS (
  SELECT
    Tag,
    COUNT(*) AS TagQuestionCount,
    SUM(COALESCE(p.ViewCount, 0)) AS TotalViews,
    SUM(COALESCE(p.Score, 0)) AS TotalScore
  FROM TaggedActivity ta
  JOIN Posts p ON p.Id = ta.PostId
  GROUP BY Tag
  ORDER BY TotalViews DESC
  LIMIT 20
),
TopContributors AS (
  SELECT
    u.Id AS UserId,
    u.DisplayName AS UserName,
    COUNT(*) AS QuestionsCreated,
    SUM(p.ViewCount) AS ViewsOnQuestions,
    SUM(p.Score) AS ScoreOnQuestions
  FROM Users u
  JOIN Posts p ON p.OwnerUserId = u.Id
  WHERE p.PostTypeId = 1
  GROUP BY u.Id, u.DisplayName
  ORDER BY ScoreOnQuestions DESC
  LIMIT 10
),
CrossRef AS (
  SELECT
    r.PostId,
    r.Title,
    r.CreationDate,
    r.Score,
    r.ViewCount,
    r.OwnerDisplayName,
    COALESCE(vb.BountyAmount, 0) AS Bounty
  FROM (
    SELECT
      p.Id AS PostId,
      p.Title,
      p.CreationDate,
      p.Score,
      p.ViewCount,
      p.OwnerDisplayName
    FROM Posts p
    WHERE p.PostTypeId = 1
  ) r
  LEFT JOIN Votes vb ON vb.PostId = r.PostId
  WHERE vb.VoteTypeId = 8 -- BountyStart (if any) (may be NULL)
)
SELECT
  -- 1) Rich set of post-level metrics with windowed ranking per owner
  q.PostId,
  q.Title,
  q.CreationDate,
  q.Score,
  q.ViewCount,
  q.OwnerDisplayName AS Owner,
  -- 2) last editor info via window function
  FIRST_VALUE(p.LastEditorDisplayName) OVER (PARTITION BY p.OwnerUserId ORDER BY p.LastEditDate DESC
    ROWS BETWEEN UNBOUNDED PRECEDING AND UNBOUNDED FOLLOWING) AS LastEditor,
  -- 3) computed derived metrics
  ROUND((q.Score * 1.0) / NULLIF(q.ViewCount, 0), 4) AS ScorePerView,
  -- 4) correlated subquery: number of comments on this post
  (SELECT COUNT(*) FROM Comments c WHERE c.PostId = q.PostId) AS CommentCount,
  -- 5) set operation: union with a synthetic row for a global benchmark
  t.Tag AS TopTag,
  t.TagQuestionCount AS TagQuestionCount,
  t.TotalViews AS TagTotalViews,
  t.TotalScore AS TagTotalScore
FROM
  (SELECT
     p.Id AS PostId,
     p.Title,
     p.CreationDate,
     p.Score,
     p.ViewCount,
     p.OwnerDisplayName,
     p.OwnerUserId,
     p.LastEditorDisplayName,
     p.LastEditDate
   FROM Posts p
   WHERE p.PostTypeId = 1
     AND p.CreationDate >= cast('2024-10-01 12:34:56' as timestamp) - INTERVAL '180 days'
  ) q
  JOIN TopTags t ON 1=1
  LEFT JOIN Posts p ON p.Id = q.PostId
ORDER BY q.CreationDate DESC
LIMIT 100;