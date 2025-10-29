-- {"query": "5028.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gpt-5-nano", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2026, "output_tokens": 873} 
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
    u.EmailHash,
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
    p.Opened AS OpenFlag
  FROM Posts p
  LEFT JOIN (SELECT Id, 1 AS Opened FROM Posts WHERE ClosedDate IS NULL) as o ON p.Id = o.Id
  WHERE p.LastActivityDate > NOW() - INTERVAL '90 days'
),
correlated_comments AS (
  SELECT
    c.PostId,
    COUNT(*) AS CommentCountRecent
  FROM Comments c
  WHERE c.CreationDate > NOW() - INTERVAL '90 days'
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
full AS (
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
    cs.CommentCount AS PostCommentCount,
    vs.UpVotes,
    vs.DownVotes,
    vs.ModVotes,
    COALESCE(ta.CommentCountRecent, 0) AS RecentCommentCount,
    rt.TagName AS PrimaryTag,
    CASE
      WHEN ra.PostTypeId = 1 THEN 'Question'
      WHEN ra.PostTypeId = 2 THEN 'Answer'
      ELSE 'Other'
    END AS PostType
  FROM top_users tu
  LEFT JOIN recent_activity ra ON ra.OwnerUserId = tu.UserId
  LEFT JOIN correlated_comments cs ON cs.PostId = ra.PostId
  LEFT JOIN vote_summary vs ON vs.PostId = ra.PostId
  LEFT JOIN tag_pop tp ON tp.TagId = CAST(REGEXP_SUBSTR(ra.Tags, '[^><]+', 1, 1) AS INTEGER)
  LEFT JOIN Tags rt ON rt.Id = tp.TagId
  LEFT JOIN (
    SELECT PostId, COUNT(*) AS CommentCountRecent
    FROM Comments
    WHERE CreationDate > NOW() - INTERVAL '180 days'
    GROUP BY PostId
  ) ta ON ta.PostId = ra.PostId
  WHERE tu.rn <= 100 -- top 100 by reputation for benchmarking
)
SELECT
  UserId,
  UserDisplayName,
  Reputation,
  PostId,
  PostType,
  Title,
  PrimaryTag,
  COALESCE(RecentCommentCount, 0) AS RecentCommentCount,
  PostCommentCount,
  UpVotes,
  DownVotes,
  ModVotes,
  ViewCount,
  Score,
  CreationDate AS PostCreationDate,
  LastActivityDate
FROM full
ORDER BY Reputation DESC, PostCreationDate DESC
LIMIT 100;