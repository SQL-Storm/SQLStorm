-- {"query": "5639.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gpt-5-nano", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2026, "output_tokens": 736} 
WITH RecentActivity AS (
  SELECT
    p.Id AS PostId,
    p.Title,
    p.OwnerUserId,
    p.CreationDate,
    p.LastActivityDate,
    p.Score,
    p.ViewCount,
    p.Tags,
    p.PostTypeId,
    COALESCE(a.TotalComments, 0) AS CommentCount,
    COALESCE(v.UpVotes, 0) AS UpVotes,
    COALESCE(v.DownVotes, 0) AS DownVotes,
    b.BadgeCount
  FROM Posts p
  LEFT JOIN (
    SELECT PostId, COUNT(*) AS TotalComments
    FROM Comments
    GROUP BY PostId
  ) a ON a.PostId = p.Id
  LEFT JOIN (
    SELECT PostId, SUM(CASE WHEN VoteTypes.Name = 'Up Mod' THEN 1 ELSE 0 END) AS UpVotes,
           SUM(CASE WHEN VoteTypes.Name = 'Down Mod' THEN 1 ELSE 0 END) AS DownVotes
    FROM Votes v
    JOIN VoteTypes vt ON v.VoteTypeId = vt.Id
    WHERE vt.Name IN ('UpMod','DownMod')
    GROUP BY PostId
  ) v ON v.PostId = p.Id
  LEFT JOIN (
    SELECT OwnerUserId, COUNT(*) AS BadgeCount
    FROM Badges
    GROUP BY OwnerUserId
  ) b ON b.OwnerUserId = p.OwnerUserId
  WHERE p.CreationDate >= NOW() - INTERVAL '180 days'
), Tagged AS (
  SELECT
    r.PostId,
    r.Title,
    r.OwnerUserId,
    r.CreationDate,
    r.LastActivityDate,
    r.CommentCount,
    r.ViewCount,
    r.TagList,
    ROW_NUMBER() OVER (PARTITION BY r.OwnerUserId ORDER BY r.Score DESC, r.LastActivityDate DESC) AS rn
  FROM (
    SELECT
      ra.PostId,
      ra.Title,
      ra.OwnerUserId,
      ra.CreationDate,
      ra.LastActivityDate,
      ra.CommentCount,
      ra.ViewCount,
      STRING_AGG(DISTINCT t.TagName, ',') OVER (PARTITION BY ra.OwnerUserId) AS TagList,
      ra.Score
    FROM RecentActivity ra
    LEFT JOIN LATERAL (
      SELECT TagName
      FROM unnest(string_to_array(ra.Tags, '>_<')) AS t(TagName)
    ) t ON true
  ) r
)
SELECT
  t.PostId,
  t.Title,
  t.OwnerUserId AS UserId,
  u.DisplayName AS OwnerDisplayName,
  t.CreationDate,
  t.LastActivityDate,
  t.CommentCount,
  t.ViewCount,
  t.TagList AS Tags,
  t.UpVotes,
  t.DownVotes,
  t.BadgeCount,
  CASE
    WHEN u.Reputation IS NULL THEN 0
    ELSE u.Reputation
  END AS ReputationScore,
  (SELECT AVG(Score) FROM Posts WHERE OwnerUserId = t.OwnerUserId) AS AvgUserPostScore,
  (SELECT COUNT(*) FROM Posts p2 WHERE p2.OwnerUserId = t.OwnerUserId AND p2.PostTypeId = 1) AS QuestionCount
FROM Tagged t
JOIN Users u ON u.Id = t.OwnerUserId
WHERE t.rn = 1
  AND (t.TagList IS NULL OR length(t.TagList) > 0)
ORDER BY t.LastActivityDate DESC
LIMIT 100;