WITH ranked_posts AS (
  SELECT
    p.Id AS PostId,
    p.Title,
    p.CreationDate,
    p.Score,
    p.ViewCount,
    p.OwnerUserId,
    p.Tags,
    p.LastActivityDate,
    p.PostTypeId,
    pc.Name AS PostTypeName,
    COALESCE(a.Id, NULL) AS AcceptedAnswerId,
    COUNT(DISTINCT c.Id) AS CommentCount,
    SUM(CASE WHEN v.VoteTypeId = 2 THEN 1 ELSE 0 END) AS UpVotes,
    SUM(CASE WHEN v.VoteTypeId = 3 THEN 1 ELSE 0 END) AS DownVotes,
    AVG(EXTRACT(EPOCH FROM (CAST('2024-10-01 12:34:56' AS TIMESTAMP) - p.CreationDate)) / 3600.0) AS HoursSinceCreation,
    ARRAY_AGG(DISTINCT tq.TagName) FILTER (WHERE tq.TagName IS NOT NULL) AS TagNames
  FROM Posts p
  JOIN PostTypes pc ON p.PostTypeId = pc.Id
  LEFT JOIN Posts a ON p.AcceptedAnswerId = a.Id
  LEFT JOIN Comments c ON c.PostId = p.Id
  LEFT JOIN Votes v ON v.PostId = p.Id
  LEFT JOIN LATERAL (
      SELECT unnest(string_to_array(trim(BOTH ' ' FROM p.Tags), '><')) AS TagName
  ) tq ON TRUE
  GROUP BY
    p.Id, p.Title, p.CreationDate, p.Score, p.ViewCount, p.OwnerUserId,
    p.Tags, p.LastActivityDate, p.PostTypeId, pc.Name, a.Id
),
differences AS (
  SELECT
    rp.PostId,
    rp.Title,
    rp.CreationDate,
    rp.CommentCount,
    rp.UpVotes,
    rp.DownVotes,
    rp.HoursSinceCreation,
    rp.TagNames,
    u.Reputation,
    u.DisplayName,
    u.AccountId,
    b1.Name AS BadgeName,
    b1.Class AS BadgeClass,
    b1.Date AS BadgeDate
  FROM ranked_posts rp
  LEFT JOIN Users u ON rp.OwnerUserId = u.Id
  LEFT JOIN LATERAL (
    SELECT Name, Class, Date
    FROM Badges
    WHERE UserId = u.Id
    ORDER BY Date DESC
    LIMIT 1
  ) b1 ON TRUE
),
final AS (
  SELECT
    d.PostId,
    d.Title,
    d.CreationDate,
    d.CommentCount,
    d.UpVotes,
    d.DownVotes,
    d.HoursSinceCreation,
    d.TagNames,
    d.Reputation,
    d.DisplayName,
    d.AccountId,
    d.BadgeName,
    d.BadgeClass,
    d.BadgeDate,
    ROW_NUMBER() OVER (
      PARTITION BY d.PostId
      ORDER BY d.Reputation DESC NULLS LAST, d.BadgeDate DESC NULLS LAST
    ) AS rn
  FROM differences d
)
SELECT
  PostId,
  Title,
  CreationDate,
  CommentCount,
  UpVotes,
  DownVotes,
  HoursSinceCreation,
  TagNames,
  Reputation,
  DisplayName,
  AccountId,
  BadgeName,
  BadgeClass,
  BadgeDate
FROM final
WHERE rn = 1
ORDER BY CreationDate DESC
LIMIT 100;