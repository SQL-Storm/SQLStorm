WITH
recent_q AS (
  SELECT
    p.Id AS PostId,
    p.Title,
    p.Tags,
    p.CreationDate,
    p.OwnerUserId,
    p.Score,
    p.ViewCount,
    p.LastActivityDate,
    p.AnswerCount,
    p.CommentCount,
    p.FavoriteCount,
    p.PostTypeId,
    ROW_NUMBER() OVER (ORDER BY p.LastActivityDate DESC, p.Score DESC) AS rn
  FROM Posts p
  WHERE p.PostTypeId = 1 -- questions
    AND p.CreationDate >= CAST('2024-10-01 12:34:56' AS timestamp) - INTERVAL '90 days'
),
tag_refs AS (
  SELECT
    unnest(string_to_array(substring(p.Tags FROM 2 FOR char_length(p.Tags)-2), '><')) AS TagName,
    p.Id AS PostId
  FROM Posts p
  WHERE p.PostTypeId = 1
),
tag_stats AS (
  SELECT
    t.TagName,
    COUNT(*) AS PostCount,
    AVG(p.Score) AS AvgScore,
    SUM(p.ViewCount) AS TotalViews
  FROM tag_refs t
  JOIN Posts p ON p.Id = t.PostId
  GROUP BY t.TagName
),
top_tags AS (
  SELECT
    ts.TagName,
    ts.PostCount,
    ts.AvgScore,
    ts.TotalViews,
    ROW_NUMBER() OVER (ORDER BY ts.PostCount DESC, ts.TotalViews DESC) AS rn
  FROM tag_stats ts
  WHERE ts.PostCount > 0
  ORDER BY ts.PostCount DESC, ts.TotalViews DESC
  LIMIT 20
),
active_users AS (
  SELECT
    u.Id,
    u.DisplayName,
    u.Reputation,
    u.CreationDate,
    u.LastAccessDate,
    u.Views,
    u.UpVotes,
    u.DownVotes,
    u.ProfileImageUrl
  FROM Users u
  WHERE u.Reputation > 1000
),
recent_votes AS (
  SELECT
    v.PostId,
    v.VoteTypeId,
    v.UserId,
    v.CreationDate,
    v.BountyAmount
  FROM Votes v
  WHERE v.CreationDate >= CAST('2024-10-01 12:34:56' AS timestamp) - INTERVAL '30 days'
),
closed_posts AS (
  SELECT
    p.Id AS PostId,
    p.Title,
    p.CreationDate,
    p.ClosedDate,
    p.OwnerUserId,
    c.Name AS CloseReason
  FROM Posts p
  LEFT JOIN PostHistory ph ON ph.PostId = p.Id AND ph.PostHistoryTypeId = 10
  LEFT JOIN CloseReasonTypes c ON CAST(ph.Comment AS varchar) LIKE '%' || CAST(c.Id AS varchar) || '%'
  WHERE p.ClosedDate IS NOT NULL
)
SELECT
  rp.PostId,
  rp.Title,
  rp.CreationDate AS PostCreationDate,
  rp.LastActivityDate,
  rp.OwnerUserId,
  au.DisplayName AS OwnerDisplayName,
  rc.CloseReason,
  vt.VoteTypeId AS LastVoteType,
  vt.UserId AS LastVoterId,
  u2.DisplayName AS LastVoterDisplayName,
  rr.rn AS TopTagRank,
  tt.TagName AS TopTagName,
  ta.PostCount AS TagPostCount,
  ta.AvgScore AS TagAvgScore,
  ta.TotalViews AS TagTotalViews,
  u1.Reputation AS OwnerReputation,
  u1.CreationDate AS OwnerCreationDate,
  u1.LastAccessDate AS OwnerLastAccessDate
FROM (
  SELECT
    p.Id AS PostId,
    p.Title,
    p.CreationDate,
    p.LastActivityDate,
    p.OwnerUserId
  FROM Posts p
  WHERE p.PostTypeId = 1
    AND p.LastActivityDate >= CAST('2024-10-01 12:34:56' AS timestamp) - INTERVAL '7 days'
) rp
LEFT JOIN active_users u1 ON u1.Id = rp.OwnerUserId
LEFT JOIN Users u2 ON u2.Id = rp.OwnerUserId
LEFT JOIN closed_posts rc ON rc.PostId = rp.PostId
LEFT JOIN (
  SELECT
    tr.TagName,
    ROW_NUMBER() OVER (ORDER BY COUNT(*) DESC) AS rn
  FROM tag_refs tr
  GROUP BY tr.TagName
  ORDER BY COUNT(*) DESC
) tt ON 1=1
LEFT JOIN (
  SELECT
    tt2.TagName,
    tt2.PostCount,
    tt2.AvgScore,
    tt2.TotalViews,
    tt2.rn
  FROM top_tags tt2
) rr ON rr.TagName = tt.TagName
LEFT JOIN (
  SELECT
    TagName,
    PostCount,
    AvgScore,
    TotalViews
  FROM tag_stats
) ta ON ta.TagName = tt.TagName
LEFT JOIN LATERAL (
  SELECT v1.VoteTypeId, v1.UserId
  FROM Votes v1
  WHERE v1.PostId = rp.PostId
  ORDER BY v1.CreationDate DESC
  LIMIT 1
) vt ON true
LEFT JOIN active_users au ON au.Id = rp.OwnerUserId
ORDER BY rp.LastActivityDate DESC
LIMIT 50;