-- {"query": "5631.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gpt-5-nano", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2026, "output_tokens": 1036} 
WITH
EligiblePosts AS (
  SELECT
    p.Id AS PostId,
    p.PostTypeId,
    p.OwnerUserId,
    p.Title,
    p.Tags,
    p.Score,
    p.ViewCount,
    p.CreationDate,
    p.LastActivityDate,
    p.AcceptedAnswerId,
    p.CommentCount,
    p.FavoriteCount,
    p.ParentId,
    p.Body,
    p.LastEditorUserId,
    p.LastEditDate,
    p.ContentLicense,
    p.OwnerDisplayName,
    p.LastEditorDisplayName,
    p.DateCreatedUtc
  FROM Posts p
  WHERE p.PostTypeId IN (1,2) -- Questions and Answers
),
Flagged AS (
  SELECT
    v.PostId,
    v.VoteTypeId,
    v.UserId,
    v.CreationDate,
    v.BountyAmount,
    ROW_NUMBER() OVER (PARTITION BY v.PostId ORDER BY v.CreationDate DESC) AS rn
  FROM Votes v
  WHERE v.VoteTypeId IN (10,16,11) -- Deletion, ModeratorReview, Undeletion
),
RecentActivity AS (
  SELECT
    po.PostId,
    po.ParentId,
    po.PostTypeId,
    po.OwnerUserId,
    po.Title,
    po.Tags,
    po.CreationDate,
    po.LastActivityDate,
    po.Score,
    po.ViewCount,
    po.CommentCount,
    COALESCE(ha.ReplyCount,0) AS ChildCommentCount
  FROM EligiblePosts po
  LEFT JOIN (
    SELECT PostId, COUNT(*) AS ReplyCount
    FROM Comments
    GROUP BY PostId
  ) ha ON ha.PostId = po.Id
),
TopTags AS (
  SELECT
    t.TagName,
    t.Count AS TagCount,
    t.ExcerptPostId,
    t.WikiPostId,
    ROW_NUMBER() OVER (ORDER BY t.Count DESC, t.TagName) AS rn
  FROM Tags t
  WHERE t.IsModeratorOnly = 0
),
CrossLinked AS (
  SELECT
    pl.Id,
    pl.PostId,
    pl.RelatedPostId,
    pl.LinkTypeId,
    pl.CreationDate,
    p1.Title AS PostTitle,
    p2.Title AS RelatedPostTitle
  FROM PostLinks pl
  JOIN Posts p1 ON pl.PostId = p1.Id
  JOIN Posts p2 ON pl.RelatedPostId = p2.Id
  WHERE pl.LinkTypeId IN (1,3) -- Linked or Duplicate
),
ComplexQuery AS (
  SELECT
    rp.PostId,
    rp.ParentId,
    rp.PostTypeId,
    rp.OwnerUserId,
    u.DisplayName AS OwnerDisplayName,
    rp.Title,
    rp.Tags,
    rp.CreationDate,
    rp.LastActivityDate,
    rp.Score,
    rp.ViewCount,
    rp.CommentCount,
    COALESCE(rn.Reports,0) AS ReportCount,
    COALESCE(vt.UpVotes,0) AS UpVotes,
    COALESCE(vt.DownVotes,0) AS DownVotes,
    CASE
      WHEN p.LastEditorUserId IS NULL THEN NULL
      ELSE ld.DisplayName
    END AS LastEditorDisplayName
  FROM RecentActivity rp
  LEFT JOIN Users u ON rp.OwnerUserId = u.Id
  LEFT JOIN Users ld ON rp.LastEditorUserId = ld.Id
  LEFT JOIN (
    SELECT PostId, COUNT(*) AS Reports
    FROM Votes
    WHERE VoteTypeId = 14 -- ModeratorReview as proxy for reports
    GROUP BY PostId
  ) rn ON rp.PostId = rn.PostId
  LEFT JOIN (
    SELECT PostId, SUM(BountyAmount) AS UpVotes
    FROM Votes
    WHERE VoteTypeId = 8 -- BountyStart used here as proxy for engagement
    GROUP BY PostId
  ) vt ON rp.PostId = vt.PostId
  WHERE rp.PostTypeId = 1
)
SELECT
  ComplexQuery.PostId,
  ComplexQuery.OwnerDisplayName,
  ComplexQuery.Title,
  ComplexQuery.Tags,
  ComplexQuery.CreationDate,
  ComplexQuery.LastActivityDate,
  ComplexQuery.Score,
  ComplexQuery.ViewCount,
  ComplexQuery.CommentCount,
  ComplexQuery.UpVotes,
  ComplexQuery.DownVotes,
  ComplexQuery.LastEditorDisplayName,
  CrossLinked.RelatedPostId,
  CrossLinked.RelatedPostTitle,
  TopTags.TagName AS TrendingTag
FROM ComplexQuery
LEFT JOIN CrossLinked ON ComplexQuery.PostId = CrossLinked.PostId
LEFT JOIN TopTags ON TopTags.rn = 1
WHERE
  ComplexQuery.Score >= 0
  AND ComplexQuery.ViewCount > 0
  AND (ComplexQuery.Tags IS NOT NULL OR ComplexQuery.Title IS NOT NULL)
ORDER BY ComplexQuery.LastActivityDate DESC, ComplexQuery.Score DESC
LIMIT 100;