-- {"query": "5263.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gpt-5-nano", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2026, "output_tokens": 959}
WITH
TopQ AS (
  SELECT
    p.Id AS PostId,
    p.Title,
    p.CreationDate,
    p.OwnerUserId,
    p.Score,
    p.ViewCount,
    p.Tags,
    p.LastActivityDate,
    p.AnswerCount,
    p.CommentCount,
    p.FavoriteCount,
    p.Body,
    p.ClosedDate,
    p.ContentLicense,
    u.Reputation,
    u.DisplayName,
    u.AccountId,
    u.LastAccessDate
  FROM Posts p
  LEFT JOIN Users u ON p.OwnerUserId = u.Id
  WHERE p.PostTypeId = 1
    AND p.CreationDate >= CAST('2024-10-01 12:34:56' AS timestamp) - INTERVAL '180 days'
),
RecentEdits AS (
  SELECT
    ph.PostId,
    ph.CreationDate AS EditDate,
    ph.Text AS EditedText,
    ph.UserId AS EditorUserId,
    ph.UserDisplayName AS EditorDisplayName,
    ph.PostHistoryTypeId
  FROM PostHistory ph
  WHERE ph.PostHistoryTypeId IN (4,5,6,8,9,24,33,34)
),
TagStats AS (
  SELECT
    t.TagName,
    t.Id AS TagId,
    t.Count,
    t.ExcerptPostId,
    t.WikiPostId
  FROM Tags t
),
Links AS (
  SELECT
    pl.PostId,
    pl.RelatedPostId,
    pl.LinkTypeId,
    lt.Name AS LinkTypeName
  FROM PostLinks pl
  JOIN LinkTypes lt ON pl.LinkTypeId = lt.Id
),
VotesAgg AS (
  SELECT
    v.PostId,
    SUM(CASE WHEN vt.Id = 2 THEN 1 ELSE 0 END) AS UpVotes,
    SUM(CASE WHEN vt.Id = 3 THEN 1 ELSE 0 END) AS DownVotes,
    SUM(CASE WHEN vt.Id = 6 THEN 1 ELSE 0 END) AS CloseVotes,
    SUM(CASE WHEN vt.Id = 8 THEN 1 ELSE 0 END) AS BountyStarts
  FROM Votes v
  JOIN VoteTypes vt ON v.VoteTypeId = vt.Id
  GROUP BY v.PostId
),
ActiveBounties AS (
  SELECT
    v.PostId,
    v.BountyAmount,
    v.CreationDate AS BountyDate,
    v.UserId AS BountyUser
  FROM Votes v
  WHERE v.VoteTypeId = 8
    AND v.BountyAmount IS NOT NULL
),
Correlated AS (
  SELECT
    tq.PostId,
    tq.Title,
    tq.CreationDate,
    tq.OwnerUserId,
    tq.Reputation,
    tq.DisplayName,
    tq.LastAccessDate,
    COALESCE(recent.EditDate, tq.CreationDate) AS BenchmarkDate,
    COALESCE(va.UpVotes, 0) AS UpVotes,
    COALESCE(va.DownVotes, 0) AS DownVotes,
    COALESCE(va.CloseVotes, 0) AS CloseVotes,
    COALESCE(va.BountyStarts, 0) AS BountyStarts,
    tag_pairs.TagName,
    tag_pairs.TagCount,
    a.LinksCount
  FROM TopQ tq
  LEFT JOIN RecentEdits recent ON tq.PostId = recent.PostId
  LEFT JOIN VotesAgg va ON tq.PostId = va.PostId
  LEFT JOIN LATERAL (
      SELECT COUNT(*) AS LinksCount
      FROM PostLinks pl
      WHERE pl.PostId = tq.PostId
  ) a ON true
  LEFT JOIN LATERAL (
      -- split the tag string into rows without using set-returning functions in WHERE
      SELECT tname AS TagName,
             COALESCE(ts.Count, 0) AS TagCount
      FROM (
        SELECT TRIM(BOTH ' ' FROM val) AS tname
        FROM (
          SELECT regexp_split_to_table(tq.Tags, '>') AS val
        ) s
      ) tt
      LEFT JOIN Tags ts ON ts.TagName = tt.tname
  ) tag_pairs ON true
)
SELECT
  c.PostId,
  c.Title,
  c.BenchmarkDate,
  c.OwnerUserId,
  c.DisplayName AS OwnerDisplayName,
  c.Reputation,
  c.LastAccessDate,
  c.UpVotes,
  c.DownVotes,
  c.CloseVotes,
  c.BountyStarts,
  c.TagName,
  c.TagCount,
  c.LinksCount,
  (c.UpVotes - c.DownVotes) AS NetScore,
  (c.BenchmarkDate - c.CreationDate) AS AgeDays
FROM Correlated c
GROUP BY
  c.PostId,
  c.Title,
  c.CreationDate,
  c.OwnerUserId,
  c.Reputation,
  c.DisplayName,
  c.LastAccessDate,
  c.BenchmarkDate,
  c.UpVotes,
  c.DownVotes,
  c.CloseVotes,
  c.BountyStarts,
  c.TagName,
  c.TagCount,
  c.LinksCount
ORDER BY NetScore DESC, AgeDays ASC
LIMIT 100;