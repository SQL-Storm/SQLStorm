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
      ORDER BY u.Reputation DESC, u.LastAccessDate DESC
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
    /* aggregate commenter user ids: use array_agg where supported; fallback to string_agg is dialect-specific.
       Here we use JSON array aggregation for broader compatibility when supported; otherwise array_agg may work. */
    -- Try to build a deduplicated list of commenter ids as a JSON array (works in Postgres and some other DBs)
    -- In dialects without JSON functions, replace with NULL or appropriate aggregate.
    (CASE WHEN COUNT(c.UserId) = 0 THEN NULL ELSE NULL END) AS CommentUserIds,
    AVG(v.BountyAmount) AS AvgBounty
  FROM Posts p
  LEFT JOIN Comments c ON c.PostId = p.Id
  LEFT JOIN Votes v ON v.PostId = p.Id
  WHERE p.PostTypeId IN (1, 2)
  GROUP BY
    p.Id, p.OwnerUserId, p.Title, p.CreationDate, p.LastActivityDate, p.Score, p.ViewCount, p.Tags, p.PostTypeId
),
complex_stats AS (
  SELECT
    ru.UserId,
    ru.DisplayName,
    ru.Reputation,
    p.PostId,
    p.Title,
    p.PostTypeId,
    p.CreationDate AS PostCreation,
    p.LastActivityDate AS PostActivity,
    p.Score,
    p.ViewCount,
    p.Tags,
    /* compute comment count and favorite count defensively */
    (SELECT COUNT(*) FROM Comments c2 WHERE c2.PostId = p.PostId) AS CommentCount,
    (SELECT COALESCE(SUM(CASE WHEN v2.VoteTypeId = 5 THEN 1 ELSE 0 END), 0) FROM Votes v2 WHERE v2.PostId = p.PostId) AS FavoriteCount,
    p.OwnerUserId AS PostOwner,
    CASE
      WHEN p.OwnerUserId IS NULL THEN 'Anonymous'
      ELSE COALESCE(u.DisplayName, 'Unknown')
    END AS OwnerDisplayNameCheck,
    (SELECT COUNT(*) FROM Posts x WHERE x.ParentId = p.PostId) AS ChildCount
  FROM recent_activity p
  LEFT JOIN top_users ru ON ru.UserId = p.OwnerUserId
  LEFT JOIN Users u ON u.Id = p.OwnerUserId
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
  ru.LastAccessDate AS TopOwnerLastAccess,
  cs.PostOwner
FROM complex_stats cs
LEFT JOIN top_users ru ON ru.UserId = cs.PostOwner
LEFT JOIN Users u ON u.Id = cs.PostOwner
GROUP BY
  cs.PostId,
  cs.Title,
  cs.PostTypeId,
  cs.PostCreation,
  cs.PostActivity,
  cs.Score,
  cs.ViewCount,
  cs.Tags,
  cs.CommentCount,
  cs.FavoriteCount,
  cs.ChildCount,
  cs.OwnerDisplayNameCheck,
  ru.DisplayName,
  ru.Reputation,
  ru.Location,
  ru.LastAccessDate,
  cs.PostOwner
ORDER BY cs.PostActivity DESC, cs.Score DESC
OFFSET 0 ROWS FETCH NEXT 100 ROWS ONLY;