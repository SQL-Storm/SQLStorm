-- {"query": "61.sql", "dataset": "stackoverflow", "version": "v1.4", "prompt": "p1", "model": "gpt-5-nano", "temperature": 1.0, "max_tokens": 32768, "reasoning": "minimal", "input_tokens": 2026, "output_tokens": 912} 
WITH RankedPosts AS (
  SELECT
    p.Id,
    p.Title,
    p.Tags,
    p.PostTypeId,
    p.CreationDate,
    p.ViewCount,
    p.Score,
    p.OwnerUserId,
    p.ParentId,
    p.AcceptedAnswerId,
    p.LastActivityDate,
    p.CommentCount,
    p.FavoriteCount,
    p.LastEditorUserId,
    p.LastEditDate,
    p.Body,
    p.ContentLicense,
    p.AnswerCount,
    u.DisplayName AS OwnerDisplayName,
    u.Reputation,
    u.CreationDate AS OwnerCreationDate,
    u.LastAccessDate,
    u.Views,
    u.UpVotes,
    u.DownVotes,
    u.ProfileImageUrl,
    u.Location,
    u.EmailHash,
    u.AccountId,
    ROW_NUMBER() OVER (
      PARTITION BY COALESCE(p.OwnerUserId, -1)
      ORDER BY p.Score DESC, p.ViewCount DESC, p.CreationDate DESC
    ) AS rn,
    COUNT(*) OVER (PARTITION BY COALESCE(p.OwnerUserId, -1)) AS total_by_owner
  FROM Posts p
  LEFT JOIN Users u ON p.OwnerUserId = u.Id
),
ActivityAgg AS (
  SELECT
    rp.Id,
    rp.Title,
    rp.Tags,
    rp.PostTypeId,
    rp.CreationDate,
    rp.ViewCount,
    rp.Score,
    rp.OwnerUserId,
    rp.ParentId,
    rp.AcceptedAnswerId,
    rp.LastActivityDate,
    rp.CommentCount,
    rp.FavoriteCount,
    rp.LastEditorUserId,
    rp.LastEditDate,
    rp.Body,
    rp.ContentLicense,
    rp.AnswerCount,
    rp.OwnerDisplayName,
    rp.Reputation,
    rp.OwnerCreationDate,
    rp.LastAccessDate,
    rp.Views,
    rp.UpVotes,
    rp.DownVotes,
    rp.ProfileImageUrl,
    rp.Location,
    rp.EmailHash,
    rp.AccountId,
    rp.rn,
    rp.total_by_owner
  FROM RankedPosts rp
  WHERE rp.rn = 1
),
TagStats AS (
  SELECT
    a.Id AS PostId,
    LOWER(t.TagName) AS TagLower,
    COUNT(*) AS TagPostCount
  FROM ActivityAgg a
  CROSS APPLY (
    SELECT DISTINCT TRIM(b.tag.value) AS TagName
    FROM STRING_SPLIT(a.Tags, '><') AS b(tag)
  ) AS t
  GROUP BY a.Id, LOWER(t.TagName)
),
ComplexFilter AS (
  SELECT
    a.*,
    ts.TagPostCount
  FROM ActivityAgg a
  LEFT JOIN TagStats ts ON ts.PostId = a.Id
),
TopN AS (
  SELECT
    *,
    ROW_NUMBER() OVER (
      ORDER BY Score DESC, ViewCount DESC, LastActivityDate DESC
    ) AS rn2
  FROM ComplexFilter
)
SELECT
  t.Id AS PostId,
  t.Title,
  t.Tags,
  t.PostTypeId,
  t.CreationDate,
  t.ViewCount,
  t.Score,
  t.OwnerUserId,
  t.OwnerDisplayName,
  t.Reputation,
  t.LastActivityDate,
  t.CommentCount,
  t.FavoriteCount,
  t.LastEditDate,
  t.Body,
  t.ContentLicense,
  t.AnswerCount,
  t.Location,
  t.AccountId,
  t.ProfileImageUrl,
  t.OwnerCreationDate,
  t.LastAccessDate,
  t.Views,
  t.UpVotes,
  t.DownVotes,
  t.EmailHash,
  t.Total_by_owner,
  t.TagLower,
  t.TagPostCount
FROM TopN t
WHERE t.rn2 = 1
  AND EXISTS (
    SELECT 1
    FROM Votes v
    WHERE v.PostId = t.Id
      AND v.VoteTypeId IN (2, 6)
      AND v.CreationDate >= DATEADD(year, -1, GETDATE())
  )
  AND (t.Score + COALESCE((SELECT AVG(v.BountyAmount) FROM Votes v WHERE v.PostId = t.Id AND v.BountyAmount IS NOT NULL), 0)) > 0
ORDER BY t.Score DESC, t.ViewCount DESC, t.LastActivityDate DESC
LIMIT 100;