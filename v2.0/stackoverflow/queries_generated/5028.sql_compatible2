WITH top_users AS (
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
    u.ProfileImageUrl,
    u.WebsiteUrl,
    u.AccountId,
    ROW_NUMBER() OVER (ORDER BY u.Reputation DESC, u.CreationDate ASC) AS rn
  FROM Users u
),
tag_pop AS (
  SELECT
    t.Id AS TagId,
    t.TagName,
    t.Count,
    t.ExcerptPostId,
    t.WikiPostId
  FROM Tags t
),
recent_activity AS (
  SELECT
    p.Id AS PostId,
    p.OwnerUserId,
    p.Score,
    p.ViewCount,
    p.CreationDate,
    p.LastActivityDate,
    p.Title,
    p.Tags,
    p.PostTypeId,
    p.ParentId,
    p.AcceptedAnswerId,
    p.CommentCount,
    p.FavoriteCount,
    p.ContentLicense,
    CASE WHEN p.ClosedDate IS NULL THEN 1 ELSE 0 END AS OpenFlag
  FROM Posts p
  WHERE p.LastActivityDate > (CAST('2024-10-01 12:34:56' AS TIMESTAMP) - INTERVAL '90' DAY)
),
correlated_comments AS (
  SELECT
    c.PostId,
    COUNT(*) AS CommentCountRecent
  FROM Comments c
  WHERE c.CreationDate > (CAST('2024-10-01 12:34:56' AS TIMESTAMP) - INTERVAL '90' DAY)
  GROUP BY c.PostId
),
vote_summary AS (
  SELECT
    v.PostId,
    SUM(CASE WHEN v.VoteTypeId = 2 THEN 1 ELSE 0 END) AS UpVotes,
    SUM(CASE WHEN v.VoteTypeId = 3 THEN 1 ELSE 0 END) AS DownVotes,
    SUM(CASE WHEN v.VoteTypeId = 14 THEN 1 ELSE 0 END) AS ModVotes
  FROM Votes v
  GROUP BY v.PostId
),
full_data AS (
  SELECT
    tu.UserId,
    tu.DisplayName AS UserDisplayName,
    tu.Reputation,
    ra.PostId,
    ra.Title,
    ra.Tags,
    ra.Score,
    ra.ViewCount,
    ra.CreationDate AS PostCreationDate,
    ra.LastActivityDate,
    cs.CommentCountRecent AS PostCommentCount,
    vs.UpVotes,
    vs.DownVotes,
    vs.ModVotes,
    COALESCE(ta.CommentCountRecent, 0) AS RecentCommentCount,
    rt.TagName AS PrimaryTag,
    CASE
      WHEN ra.PostTypeId = 1 THEN 'Question'
      WHEN ra.PostTypeId = 2 THEN 'Answer'
      ELSE 'Other'
    END AS PostType,
    tu.rn
  FROM top_users tu
  LEFT JOIN recent_activity ra ON ra.OwnerUserId = tu.UserId
  LEFT JOIN correlated_comments cs ON cs.PostId = ra.PostId
  LEFT JOIN vote_summary vs ON vs.PostId = ra.PostId
  LEFT JOIN (
    -- map tag name to tag id by extracting first tag text from ra.tags like '<tag1><tag2>'
    SELECT
      tp.TagId,
      tp.TagName
    FROM tag_pop tp
  ) tp_first ON tp_first.TagName = NULLIF(REGEXP_REPLACE(ra.Tags, '^<([^>]+)>(.*)$', '\1'), '')
  LEFT JOIN Tags rt ON rt.Id = tp_first.TagId
  LEFT JOIN (
    SELECT PostId, COUNT(*) AS CommentCountRecent
    FROM Comments
    WHERE CreationDate > (CAST('2024-10-01 12:34:56' AS TIMESTAMP) - INTERVAL '180' DAY)
    GROUP BY PostId
  ) ta ON ta.PostId = ra.PostId
  WHERE tu.rn <= 100
)
SELECT
  fd.UserId,
  fd.UserDisplayName,
  fd.Reputation,
  fd.PostId,
  fd.PostType,
  fd.Title,
  fd.PrimaryTag,
  COALESCE(fd.RecentCommentCount, 0) AS RecentCommentCount,
  COALESCE(fd.PostCommentCount, 0) AS PostCommentCount,
  COALESCE(fd.UpVotes, 0) AS UpVotes,
  COALESCE(fd.DownVotes, 0) AS DownVotes,
  COALESCE(fd.ModVotes, 0) AS ModVotes,
  fd.ViewCount,
  fd.Score,
  fd.PostCreationDate,
  fd.LastActivityDate
FROM full_data fd
ORDER BY fd.Reputation DESC, fd.PostCreationDate DESC
LIMIT 100;