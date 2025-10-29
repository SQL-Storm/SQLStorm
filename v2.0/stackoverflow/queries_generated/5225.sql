-- {"query": "5225.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gpt-5-nano", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2026, "output_tokens": 863} 
WITH TopPosts AS (
  SELECT
    p.Id AS PostId,
    p.Title,
    p.Tags,
    p.Score,
    p.ViewCount,
    p.CreationDate,
    p.LastActivityDate,
    p.OwnerUserId,
    p.OwnerDisplayName,
    p.CommentCount,
    p.AnswerCount,
    p.FavoriteCount,
    p.PostTypeId,
    p.ParentId,
    p.AcceptedAnswerId,
    p.ContentLicense,
    -- calculate a rich composite metric for benchmarking
    (p.Score * 1.0 + COALESCE(p.ViewCount,0) * 0.01
     + COUNT(DISTINCT c.Id) OVER (PARTITION BY p.Id) * 0.5
     + CASE WHEN p.PostTypeId = 1 THEN 1.5 ELSE 0 END
    ) AS BenchmarkScore
  FROM Posts p
  LEFT JOIN Comments c ON c.PostId = p.Id
  WHERE p.CreationDate >= NOW() - INTERVAL '365 days'
),
RecentEdits AS (
  SELECT
    ph.PostId,
    ph.Id AS RevisionId,
    ph.PostHistoryTypeId,
    ph.CreationDate AS RevisionDate,
    ph.UserId AS RevisionUserId,
    ph.Comment AS RevisionComment,
    ph.Text AS RevisionText
  FROM PostHistory ph
  WHERE ph.PostHistoryTypeId IN (4,5,6,8,9,10,11,14,15,16,24,33,34)
),
TagStats AS (
  SELECT
    t.TagName,
    t.Id AS TagId,
    t.Count AS TagCount,
    t.IsModeratorOnly,
    t.IsRequired
  FROM Tags t
  WHERE t.Count > 0
),
CrossLinked AS (
  SELECT
    lp.PostId,
    lp.RelatedPostId,
    lt.Name AS LinkTypeName,
    p2.OwnerUserId AS LinkedPostOwner
  FROM PostLinks lp
  JOIN Posts p2 ON p2.Id = lp.RelatedPostId
  JOIN LinkTypes lt ON lt.Id = lp.LinkTypeId
  WHERE lp.CreationDate >= NOW() - INTERVAL '180 days'
),
UserActivity AS (
  SELECT
    u.Id AS UserId,
    u.DisplayName,
    u.Reputation,
    u.CreationDate AS UserCreationDate,
    u.LastAccessDate,
    u.Views,
    u.UpVotes,
    u.DownVotes,
    u.AccountId,
    (SELECT COUNT(*) FROM Posts p WHERE p.OwnerUserId = u.Id) AS PostsByUser
  FROM Users u
  WHERE u.LastAccessDate >= NOW() - INTERVAL '365 days'
),
TopCorrelated AS (
  SELECT
    bp.PostId,
    bp.Title,
    bp.Tags,
    bp.BenchmarkScore,
    ROW_NUMBER() OVER (ORDER BY bp.BenchmarkScore DESC, bp.PostId) AS rn
  FROM TopPosts bp
)
SELECT
  t.PostId,
  t.Title,
  t.Tags,
  t.BenchmarkScore,
  t.Score AS RawScore,
  t.ViewCount,
  t.CreationDate,
  t.LastActivityDate,
  t.OwnerDisplayName,
  u.UserId AS RefOwnerUserId,
  u.DisplayName AS RefOwnerDisplayName,
  ra.RevisionDate,
  ra.RevisionComment,
  ctn.TagName,
  st.TagCount,
  cl.RelatedPostId,
  cl.LinkTypeName,
  ca.PostsByUser
FROM TopPosts t
LEFT JOIN RecentEdits ra ON ra.PostId = t.PostId
LEFT JOIN UserActivity u ON u.UserId = t.OwnerUserId
LEFT JOIN CrossLinked cl ON cl.PostId = t.PostId
LEFT JOIN TagStats ctn ON 1=1
LEFT JOIN TagStats st ON st.TagId = 1 -- placeholder to keep joinable structure for benchmark
LEFT JOIN Posts ca ON ca.Id = t.OwnerUserId
WHERE t.rn <= 100
ORDER BY t.BenchmarkScore DESC, t.PostId
LIMIT 100;