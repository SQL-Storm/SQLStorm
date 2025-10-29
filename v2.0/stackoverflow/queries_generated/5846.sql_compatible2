WITH
RecentActivePosts AS (
  SELECT
    p.Id AS PostId,
    p.Title,
    p.CreationDate,
    p.LastActivityDate,
    p.Score,
    p.ViewCount,
    p.OwnerUserId,
    p.Tags,
    p.PostTypeId,
    p.AnswerCount,
    p.CommentCount,
    p.FavoriteCount
  FROM Posts p
  WHERE p.CreationDate >= CAST(CAST('2024-10-01 12:34:56' AS varchar) AS timestamp) - INTERVAL '30 days'
),
TopTags AS (
  SELECT
    t.TagName,
    COUNT(*) AS TagUsage,
    SUM(r.ViewCount) AS TotalViews,
    SUM(r.Score) AS TotalScore
  FROM RecentActivePosts r,
  LATERAL (
    SELECT unnest(string_to_array(substring(r.Tags, 2, length(r.Tags)-2), '><')) AS TagName
  ) t
  GROUP BY t.TagName
  ORDER BY SUM(r.ViewCount) DESC
  LIMIT 5
),
TagEngagement AS (
  SELECT
    tt.TagName,
    tt.TotalViews,
    tt.TotalScore,
    CAST(tt.TotalViews AS DECIMAL(20,2)) / NULLIF(tt.TotalScore,0) AS ViewsPerScore
  FROM TopTags tt
),
CrossJoinUsers AS (
  SELECT
    u.Id AS UserId,
    u.DisplayName,
    u.Reputation,
    u.CreationDate,
    u.LastAccessDate,
    u.Location,
    u.Views,
    u.UpVotes,
    u.DownVotes,
    u.AccountId,
    COALESCE(b.TotalBadges, 0) AS BadgeCount
  FROM Users u
  LEFT JOIN (
    SELECT UserId, COUNT(*) AS TotalBadges
    FROM Badges
    GROUP BY UserId
  ) b ON b.UserId = u.Id
),
FlaggedPosts AS (
  SELECT
    ph.PostId,
    ph.PostHistoryTypeId,
    ph.UserId,
    ph.CreationDate,
    ph.Comment,
    ph.Text
  FROM PostHistory ph
  WHERE ph.PostHistoryTypeId IN (10, 11, 12, 13)
),
Correlation AS (
  SELECT
    r.PostId,
    r.Title,
    r.CreationDate AS PostCreation,
    r.LastActivityDate,
    r.OwnerUserId,
    r.Tags,
    p.PostTypeId,
    a.DisplayName AS OwnerDisplayName,
    v.TotalVotes,
    w.BountyAmount
  FROM RecentActivePosts r
  LEFT JOIN Posts p ON p.Id = r.PostId
  LEFT JOIN Users a ON a.Id = r.OwnerUserId
  LEFT JOIN (
    SELECT PostId, SUM(CASE WHEN VoteTypeId IN (2,3) THEN 1 ELSE 0 END) AS TotalVotes
    FROM Votes
    GROUP BY PostId
  ) v ON v.PostId = r.PostId
  LEFT JOIN (
    SELECT PostId, SUM(BountyAmount) AS BountyAmount
    FROM Votes
    WHERE VoteTypeId = 8
    GROUP BY PostId
  ) w ON w.PostId = r.PostId
)
SELECT
  cr.TagName,
  cr.TotalViews,
  cr.TotalScore,
  cr.ViewsPerScore,
  cu.UserId,
  cu.DisplayName AS UserDisplayName,
  cu.Reputation,
  cu.CreationDate AS UserCreationDate,
  cu.LastAccessDate AS UserLastAccessDate,
  cu.Location,
  CAST(NULL AS integer) AS PostId,
  CAST(NULL AS text) AS Title,
  CAST(NULL AS timestamp) AS PostCreation,
  CAST(NULL AS timestamp) AS LastActivityDate,
  CAST(NULL AS integer) AS PostTypeId,
  CAST(NULL AS text) AS OwnerDisplayName,
  CAST(NULL AS integer) AS TotalVotes,
  CAST(NULL AS numeric) AS BountyAmount
FROM
  TagEngagement cr
  CROSS JOIN LATERAL (
    SELECT ta.TagName
    FROM TopTags ta
    ORDER BY ta.TotalViews DESC
    LIMIT 1
  ) t
  LEFT JOIN CrossJoinUsers cu ON true
ORDER BY cr.TotalViews DESC
LIMIT 100;