-- {"query": "5454.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gpt-5-nano", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2026, "output_tokens": 794} 
WITH
TopTags AS (
  SELECT
    t.TagName,
    COUNT(*) AS TagCount,
    SUM(CASE WHEN v.VoteTypeId = 2 THEN 1 ELSE 0 END) AS UpVotesOnTag,
    SUM(CASE WHEN v.VoteTypeId = 3 THEN 1 ELSE 0 END) AS DownVotesOnTag,
    AVG(p.Score) AS AvgQuestionScore
  FROM Posts p
  LEFT JOIN Tags t ON p.Id = t.WikiPostId OR p.Tags LIKE CONCAT('%', t.TagName, '%')
  LEFT JOIN Votes v ON p.Id = v.PostId
  WHERE p.PostTypeId = 1 -- questions
  GROUP BY t.TagName
),
TemporalActivity AS (
  SELECT
    p.Id AS PostId,
    p.Title,
    p.Tags,
    p.CreationDate,
    p.Score,
    p.ViewCount,
    p.OwnerUserId,
    ROW_NUMBER() OVER (PARTITION BY p.OwnerUserId ORDER BY p.CreationDate DESC) AS rn
  FROM Posts p
  WHERE p.PostTypeId = 1
),
ComplexMetrics AS (
  SELECT
    v.PostId,
    SUM(CASE WHEN vt.Name = 'UpMod' THEN 1 ELSE 0 END) AS UpModCount,
    SUM(CASE WHEN vt.Name = 'DownMod' THEN 1 ELSE 0 END) AS DownModCount,
    MAX(p.Score) AS MaxPostScore,
    AVG(p.ViewCount) AS AvgViews
  FROM Votes v
  JOIN VoteTypes vt ON v.VoteTypeId = vt.Id
  JOIN Posts p ON v.PostId = p.Id
  GROUP BY v.PostId
),
Joined AS (
  SELECT
    q.Id AS QuestionId,
    q.Title,
    q.CreationDate,
    q.Score AS QuestionScore,
    q.ViewCount,
    q.OwnerUserId,
    q.Tags,
    ct.CommentCount,
    COALESCE(b.Name, 'NoBadge') AS BadgeName,
    ct2.LastEditUserId,
    p2.RevisionGUID
  FROM Posts q
  LEFT JOIN Comments ct ON q.Id = ct.PostId
  LEFT JOIN Badges b ON q.OwnerUserId = b.UserId AND b.Class = 1
  LEFT JOIN PostLinks pl ON q.Id = pl.PostId
  LEFT JOIN Posts p2 ON p2.Id = q.Id
  LEFT JOIN PostHistory ph ON ph.PostId = q.Id
  LEFT JOIN (
    SELECT PostId, MAX(CreationDate) AS LastEdit
    FROM PostHistory
    GROUP BY PostId
  ) ph2 ON ph2.PostId = q.Id
  LEFT JOIN (
    SELECT PostId, RevisionGUID
    FROM Posts
  ) p2 ON p2.PostId = q.Id
  WHERE q.PostTypeId = 1
)
SELECT
  t.TagName,
  t.TagCount,
  t.UpVotesOnTag,
  t.DownVotesOnTag,
  t.AvgQuestionScore,
  ta.PostId AS TrendingPostId,
  ta.Title AS TrendingPostTitle,
  ta.CreationDate AS TrendingPostDate,
  ta.Score AS TrendingPostScore,
  ta.ViewCount AS TrendingPostViews,
  ta.OwnerUserId AS TrendingPostOwner,
  ta.Tags AS TrendingPostTags,
  cm.UpModCount,
  cm.DownModCount,
  cm.MaxPostScore,
  cm.AvgViews
FROM TopTags t
LEFT JOIN TemporalActivity ta ON ta.OwnerUserId IS NOT NULL
LEFT JOIN ComplexMetrics cm ON cm.PostId = ta.PostId
WHERE t.TagCount > 10
ORDER BY t.TagCount DESC, t.UpVotesOnTag - t.DownVotesOnTag DESC
LIMIT 100;