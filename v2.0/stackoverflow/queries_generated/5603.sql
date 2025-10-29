-- {"query": "5603.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gpt-5-nano", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2026, "output_tokens": 815} 
WITH ranked_users AS (
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
    u.AboutMe,
    u.WebsiteUrl,
    u.AccountId,
    ROW_NUMBER() OVER (
      PARTITION BY u.Location
      ORDER BY u.Reputation DESC NULLS LAST, u.LastAccessDate DESC
    ) AS rn_by_location
  FROM Users u
),
top_users AS (
  SELECT
    ru.UserId,
    ru.DisplayName,
    ru.Reputation,
    ru.CreationDate,
    ru.LastAccessDate,
    ru.Location,
    ru.Views,
    ru.UpVotes,
    ru.DownVotes,
    ru.AboutMe,
    ru.WebsiteUrl,
    ru.AccountId
  FROM ranked_users ru
  WHERE ru.rn_by_location <= 5
),
recent_activity AS (
  SELECT
    p.Id AS PostId,
    p.OwnerUserId,
    p.Title,
    p.CreationDate,
    p.LastActivityDate,
    p.Score,
    p.ViewCount,
    p.Tags,
    p.PostTypeId,
    ARRAY_AGG(CASE WHEN c.UserId IS NOT NULL THEN c.UserId ELSE NULL END) FILTER (WHERE c.Id IS NOT NULL) AS CommentUserIds,
    AVG(v.BountyAmount) FILTER (WHERE v.BountyAmount IS NOT NULL) AS AvgBounty
  FROM Posts p
  LEFT JOIN Comments c ON c.PostId = p.Id
  LEFT JOIN Votes v ON v.PostId = p.Id
  WHERE p.PostTypeId IN (1, 2) -- Questions and Answers
  GROUP BY
    p.Id, p.OwnerUserId, p.Title, p.CreationDate, p.LastActivityDate, p.Score, p.ViewCount, p.Tags, p.PostTypeId
),
complex_stats AS (
  SELECT
    rp.UserId,
    rp.DisplayName,
    rp.Reputation,
    p.PostId,
    p.Title,
    p.PostTypeId,
    p.CreationDate AS PostCreation,
    p.LastActivityDate AS PostActivity,
    p.Score,
    p.ViewCount,
    p.Tags,
    p.CommentCount,
    p.FavoriteCount,
    p.OwnerUserId AS PostOwner,
    CASE
      WHEN p.OwnerUserId IS NULL THEN 'Anonymous'
      ELSE COALESCE(u.DisplayName, 'Unknown')
    END AS OwnerDisplayNameCheck,
    (SELECT COUNT(*) FROM Posts x WHERE x.ParentId = p.Id) AS ChildCount
  FROM recent_activity p
  LEFT JOIN top_users ru ON ru.UserId = p.OwnerUserId
  LEFT JOIN Users u ON u.Id = p.OwnerUserId
  LEFT JOIN Users du ON du.Id = p.LastEditorUserId
  ORDER BY p.LastActivityDate DESC
  LIMIT 200
)
SELECT
  cs.PostId,
  cs.Title,
  CASE cs.PostTypeId
    WHEN 1 THEN 'Question'
    WHEN 2 THEN 'Answer'
    ELSE 'Other'
  END AS PostKind,
  cs.PostCreation,
  cs.PostActivity,
  cs.Score,
  cs.ViewCount,
  cs.Tags,
  cs.CommentCount,
  cs.FavoriteCount,
  cs.ChildCount,
  cs.OwnerDisplayNameCheck AS OwnerNameHint,
  ru.DisplayName AS TopOwnerName,
  ru.Reputation AS TopOwnerReputation,
  ru.Location AS TopOwnerLocation,
  ru.LastAccessDate AS TopOwnerLastAccess
FROM complex_stats cs
LEFT JOIN top_users ru ON ru.UserId = cs.PostOwner
LEFT JOIN Users u ON u.Id = cs.PostOwner
ORDER BY cs.PostActivity DESC, cs.Score DESC
OFFSET 0 ROWS FETCH NEXT 100 ROWS ONLY;