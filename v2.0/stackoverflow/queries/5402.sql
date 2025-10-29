-- {"query": "5402.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gpt-5-nano", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2026, "output_tokens": 844}
WITH ranked_questions AS (
  SELECT
    p.Id AS PostId,
    p.Title,
    p.Tags,
    p.CreationDate,
    p.Score,
    p.ViewCount,
    p.OwnerUserId,
    p.AcceptedAnswerId,
    p.LastActivityDate,
    p.CommentCount,
    p.FavoriteCount,
    p.PostTypeId,
    ROW_NUMBER() OVER (
      PARTITION BY p.OwnerUserId
      ORDER BY p.Score DESC, p.ViewCount DESC, p.CreationDate DESC
    ) AS rn_by_owner
  FROM Posts p
  WHERE p.PostTypeId = 1
),
recent_activity AS (
  SELECT
    q.PostId,
    q.Title,
    q.OwnerUserId,
    q.CreationDate,
    q.LastActivityDate,
    q.ViewCount,
    q.Score,
    q.CommentCount,
    COALESCE(v1.CountUp, 0) AS UpVotesOnQuestion,
    COALESCE(v2.CountDown, 0) AS DownVotesOnQuestion,
    COALESCE(b.TotalBadges, 0) AS BadgeCount,
    u.DisplayName AS OwnerDisplayName,
    u.Reputation,
    u.Location,
    q.rn_by_owner
  FROM ranked_questions q
  LEFT JOIN (
    SELECT PostId, COUNT(*) AS CountUp
    FROM Votes
    WHERE VoteTypeId = 2
    GROUP BY PostId
  ) v1 ON v1.PostId = q.PostId
  LEFT JOIN (
    SELECT PostId, COUNT(*) AS CountDown
    FROM Votes
    WHERE VoteTypeId = 3
    GROUP BY PostId
  ) v2 ON v2.PostId = q.PostId
  LEFT JOIN (
    SELECT b.UserId AS OwnerUserId, COUNT(*) AS TotalBadges
    FROM Badges b
    GROUP BY b.UserId
  ) b ON b.OwnerUserId = q.OwnerUserId
  LEFT JOIN Users u ON u.Id = q.OwnerUserId
  WHERE q.rn_by_owner = 1
),
complex_filter AS (
  SELECT
    ra.PostId,
    ra.Title,
    ra.OwnerUserId,
    ra.OwnerDisplayName,
    ra.Reputation,
    ra.Location,
    ra.CreationDate,
    ra.LastActivityDate,
    ra.ViewCount,
    ra.Score,
    ra.CommentCount,
    ra.UpVotesOnQuestion,
    ra.DownVotesOnQuestion,
    ra.BadgeCount,
    CASE
      WHEN ra.Location IS NULL THEN 'Unknown'
      WHEN ra.Reputation > 10000 THEN 'Legend'
      WHEN ra.Reputation > 1000 THEN 'Aspirant'
      ELSE 'Newbie'
    END AS OwnerTier,
    CONCAT(
      COALESCE(ra.Title, ''),
      ' | ',
      CAST(ra.ViewCount AS VARCHAR(20)),
      ' | score=',
      CAST(ra.Score AS VARCHAR(20))
    ) AS MetaString
  FROM recent_activity ra
  WHERE ra.ViewCount > 1000
    AND ra.Score BETWEEN -5 AND 500
    AND (ra.OwnerUserId IS NOT NULL)
),
windowed AS (
  SELECT
    cft.PostId,
    cft.Title,
    cft.OwnerUserId,
    cft.OwnerDisplayName,
    cft.Reputation,
    cft.Location,
    cft.CreationDate,
    cft.LastActivityDate,
    cft.ViewCount,
    cft.Score,
    cft.CommentCount,
    cft.UpVotesOnQuestion,
    cft.DownVotesOnQuestion,
    cft.BadgeCount,
    cft.OwnerTier,
    cft.MetaString,
    ROW_NUMBER() OVER (ORDER BY cft.LastActivityDate DESC, cft.ViewCount DESC) AS seq
  FROM complex_filter cft
)
SELECT
  w.seq,
  w.PostId,
  w.Title,
  w.OwnerDisplayName AS Owner,
  w.Reputation,
  w.Location,
  w.CreationDate,
  w.LastActivityDate,
  w.ViewCount,
  w.Score,
  w.CommentCount,
  w.UpVotesOnQuestion,
  w.DownVotesOnQuestion,
  w.BadgeCount,
  w.OwnerTier,
  w.MetaString
FROM windowed w
WHERE w.seq <= 100
ORDER BY w.LastActivityDate DESC, w.ViewCount DESC;