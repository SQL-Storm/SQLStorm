-- {"query": "5237.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gpt-5-nano", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2026, "output_tokens": 779}
WITH
RecentActivePosts AS (
  SELECT
    p.Id,
    p.Title,
    p.OwnerUserId,
    p.CreationDate,
    p.LastActivityDate,
    p.Score,
    p.ViewCount,
    p.Tags,
    p.PostTypeId,
    p.ParentId,
    p.AcceptedAnswerId,
    p.CommentCount,
    p.FavoriteCount,
    p.LastEditorDisplayName,
    p.LastEditDate
  FROM Posts p
  WHERE p.PostTypeId = 1
    AND p.LastActivityDate > CAST('2024-10-01 12:34:56' AS timestamp) - INTERVAL '30 days'
),
TagPopularity AS (
  SELECT
    t.tag AS TagName,
    COUNT(*) AS PostCount
  FROM Posts p
  JOIN RecentActivePosts rap ON rap.Id = p.Id
  CROSS JOIN LATERAL (
    SELECT unnest(string_to_array(substring(p.Tags FROM 2 FOR (length(p.Tags)-2)), '><')) AS tag
  ) t
  WHERE p.Tags IS NOT NULL
  GROUP BY t.tag
),
TopTags AS (
  SELECT TagName, PostCount,
         ROW_NUMBER() OVER (ORDER BY PostCount DESC, TagName) AS rn
  FROM TagPopularity
),
TopCommentedPosts AS (
  SELECT
    rp.Id AS PostId,
    rp.Title,
    rp.OwnerUserId,
    rp.CreationDate,
    rp.LastActivityDate,
    rp.Score,
    rp.ViewCount,
    rp.CommentCount,
    COALESCE(u.Reputation, 0) AS OwnerReputation,
    vb.TotalBounty,
    cm.CommentCount AS RecentCommentCount
  FROM RecentActivePosts rp
  LEFT JOIN Users u ON rp.OwnerUserId = u.Id
  LEFT JOIN (
    SELECT PostId, MAX(COALESCE(BountyAmount, 0)) AS TotalBounty
    FROM Votes v
    WHERE v.VoteTypeId = 8
    GROUP BY PostId
  ) vb ON vb.PostId = rp.Id
  LEFT JOIN (
    SELECT PostId, COUNT(*) AS CommentCount
    FROM Comments
    GROUP BY PostId
  ) cm ON cm.PostId = rp.Id
),
Benchmarks AS (
  SELECT
    rp.PostId AS Id,
    rp.Title,
    rp.OwnerUserId,
    rp.CreationDate,
    rp.LastActivityDate,
    rp.Score,
    rp.ViewCount,
    rp.CommentCount,
    u.DisplayName AS OwnerDisplayName,
    wv.Name AS LastEditorVoteType,
    b.TotalBounty,
    tc.RecentCommentCount,
    t.TagName,
    ROW_NUMBER() OVER (ORDER BY rp.LastActivityDate DESC, rp.Score DESC, rp.ViewCount DESC) AS rn
  FROM TopCommentedPosts rp
  LEFT JOIN Users u ON rp.OwnerUserId = u.Id
  LEFT JOIN Votes v ON v.PostId = rp.PostId
  LEFT JOIN VoteTypes wv ON v.VoteTypeId = wv.Id
  LEFT JOIN (
    SELECT PostId, SUM(BountyAmount) AS TotalBounty
    FROM Votes
    WHERE VoteTypeId = 8
    GROUP BY PostId
  ) b ON b.PostId = rp.PostId
  LEFT JOIN TopCommentedPosts tc ON tc.PostId = rp.PostId
  LEFT JOIN TopTags t ON true
  GROUP BY
    rp.PostId,
    rp.Title,
    rp.OwnerUserId,
    rp.CreationDate,
    rp.LastActivityDate,
    rp.Score,
    rp.ViewCount,
    rp.CommentCount,
    u.DisplayName,
    wv.Name,
    b.TotalBounty,
    tc.RecentCommentCount,
    t.TagName
)
SELECT
  bp.Id,
  bp.Title,
  bp.OwnerUserId,
  bp.OwnerDisplayName,
  bp.CreationDate,
  bp.LastActivityDate,
  bp.Score,
  bp.ViewCount,
  bp.CommentCount,
  bp.TotalBounty,
  bp.RecentCommentCount,
  bp.TagName,
  bp.LastEditorVoteType
FROM Benchmarks bp
WHERE bp.rn <= 50
ORDER BY bp.LastActivityDate DESC, bp.Score DESC, bp.ViewCount DESC;