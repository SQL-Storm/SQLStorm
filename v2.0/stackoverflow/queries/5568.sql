-- {"query": "5568.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gpt-5-nano", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2026, "output_tokens": 733}
WITH RecentHot AS (
  SELECT
    p.Id AS PostId,
    p.Title,
    p.CreationDate,
    p.ViewCount,
    p.Score,
    p.Tags,
    p.OwnerUserId,
    p.OwnerDisplayName,
    p.LastActivityDate,
    p.LastEditDate,
    p.CommentCount,
    p.FavoriteCount,
    p.PostTypeId,
    ROW_NUMBER() OVER (ORDER BY p.Score DESC, p.LastActivityDate DESC) AS rn
  FROM Posts p
  LEFT JOIN Users u ON p.OwnerUserId = u.Id
  WHERE p.ClosedDate IS NULL
    AND p.PostTypeId IN (1,2)
),
TagStats AS (
  SELECT
    t.TagName,
    COUNT(p.Id) AS PostCount,
    AVG(p.Score) AS AvgScore,
    MAX(p.ViewCount) AS MaxViews
  FROM Tags t
  LEFT JOIN Posts p
    ON p.Tags LIKE ('%' || t.TagName || '%')
  GROUP BY t.TagName
),
HeavyJoin AS (
  SELECT
    r.PostId,
    r.Title,
    r.OwnerDisplayName,
    r.OwnerUserId,
    r.ViewCount,
    r.Score,
    r.Tags,
    r.LastActivityDate,
    r.LastEditDate,
    COALESCE(vs.TotalVotes, 0) AS TotalVotes,
    COALESCE(us.NumEditors, 0) AS NumEditors,
    COALESCE(fs.FollowerCount, 0) AS FollowerCount
  FROM RecentHot r
  LEFT JOIN (
    SELECT PostId, SUM(BountyAmount) AS TotalVotes
    FROM Votes
    GROUP BY PostId
  ) vs ON vs.PostId = r.PostId
  LEFT JOIN (
    SELECT PostId, COUNT(*) AS NumEditors
    FROM PostHistory
    GROUP BY PostId
  ) us ON us.PostId = r.PostId
  LEFT JOIN (
    SELECT UserId, COUNT(*) AS FollowerCount
    FROM Votes
    WHERE VoteTypeId = 6
    GROUP BY UserId
  ) fs ON fs.UserId = r.OwnerUserId
),
Filtered AS (
  SELECT
    hj.PostId,
    hj.Title,
    hj.OwnerDisplayName,
    hj.OwnerUserId,
    hj.ViewCount,
    hj.Score,
    hj.Tags,
    hj.LastActivityDate,
    hj.LastEditDate,
    hj.TotalVotes,
    hj.NumEditors,
    hj.FollowerCount
  FROM HeavyJoin hj
  WHERE (hj.OwnerDisplayName IS NULL OR hj.OwnerDisplayName <> '')
    AND hj.LastActivityDate > (CAST('2024-10-01 12:34:56' AS timestamp) - INTERVAL '30 days')
    AND hj.ViewCount > 0
    AND (hj.Score + hj.TotalVotes) > 0
),
Final AS (
  SELECT
    fh.PostId,
    fh.Title,
    fh.OwnerDisplayName,
    fh.ViewCount,
    fh.Score,
    fh.Tags,
    fh.LastActivityDate,
    fh.LastEditDate,
    fh.TotalVotes,
    fh.NumEditors,
    fh.FollowerCount,
    ROW_NUMBER() OVER (
      PARTITION BY fh.OwnerDisplayName
      ORDER BY fh.Score DESC, fh.TotalVotes DESC, fh.LastActivityDate DESC
    ) AS rn_owner
  FROM Filtered fh
)
SELECT
  f.PostId,
  f.Title,
  f.OwnerDisplayName,
  f.ViewCount,
  f.Score,
  f.Tags,
  f.LastActivityDate,
  f.LastEditDate,
  f.TotalVotes,
  f.NumEditors,
  f.FollowerCount
FROM Final f
WHERE f.rn_owner = 1
ORDER BY f.LastActivityDate DESC
LIMIT 100;