-- {"query": "5822.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gpt-5-nano", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2026, "output_tokens": 985} 
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
    AND p.CreationDate >= NOW() - INTERVAL '90 days'
),
tag_refs AS (
  SELECT
    unnest(string_to_array(substring(p.Tags, 2, length(p.Tags)-2), '><')) AS TagName,
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
  WHERE v.CreationDate >= NOW() - INTERVAL '30 days'
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
    AND p.LastActivityDate >= NOW() - INTERVAL '7 days'
) rp
LEFT JOIN active_users u1 ON u1.Id = rp.OwnerUserId
LEFT JOIN Users u2 ON u2.Id = rp.OwnerUserId
LEFT JOIN closed_posts rc ON rc.PostId = rp.PostId
LEFT JOIN (
  SELECT
    t.TagName,
    ROW_NUMBER() OVER (ORDER BY COUNT(*) DESC) AS rn
  FROM Tag
) tt ON 1=1
LEFT JOIN (
  SELECT
    t.TagName,
    ts.PostCount,
    ts.AvgScore,
    ts.TotalViews
  FROM top_tags tt2
) rr ON 1=1
LEFT JOIN (
  SELECT
    TagName,
    PostCount,
    AvgScore,
    TotalViews
  FROM tag_stats
) ta ON ta.TagName = tt.TagName
LEFT JOIN Votes vt ON vt.PostId = rp.PostId
ORDER BY rp.LastActivityDate DESC
LIMIT 50;