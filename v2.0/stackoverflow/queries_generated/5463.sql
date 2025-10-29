-- {"query": "5463.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gpt-5-nano", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2026, "output_tokens": 722} 
WITH recent_top_posts AS (
  SELECT
    p.Id AS PostId,
    p.Title,
    p.Tags,
    p.CreationDate,
    p.Score,
    p.ViewCount,
    p.OwnerUserId,
    p.LastActivityDate,
    ROW_NUMBER() OVER (PARTITION BY p.PostTypeId ORDER BY p.Score DESC, p.ViewCount DESC, p.CreationDate DESC) AS rn
  FROM Posts p
  WHERE p.PostTypeId = 1 -- Questions
    AND p.CreationDate >= NOW() - INTERVAL '180 days'
),
qualified_posts AS (
  SELECT
    rp.PostId,
    rp.Title,
    rp.Tags,
    rp.CreationDate,
    rp.Score,
    rp.ViewCount,
    rp.OwnerUserId,
    rp.LastActivityDate,
    u.Reputation,
    u.DisplayName,
    u.CreationDate AS UserCreationDate,
    ub.BadgeCount,
    COALESCE(vs.VoteCount, 0) AS VoteCount,
    COALESCE(cc.CommentCount, 0) AS CommentCount
  FROM recent_top_posts rp
  LEFT JOIN Users u ON rp.OwnerUserId = u.Id
  LEFT JOIN (
    SELECT UserId, COUNT(*) AS BadgeCount
    FROM Badges
    GROUP BY UserId
  ) ub ON u.Id = ub.UserId
  LEFT JOIN (
    SELECT PostId, COUNT(*) AS VoteCount
    FROM Votes
    GROUP BY PostId
  ) vs ON rp.PostId = vs.PostId
  LEFT JOIN (
    SELECT PostId, COUNT(*) AS CommentCount
    FROM Comments
    GROUP BY PostId
  ) cc ON rp.PostId = cc.PostId
  WHERE rp.rn <= 5
),
stats AS (
  SELECT
    p.PostId,
    p.Title,
    p.Tags,
    p.CreationDate,
    p.Score,
    p.ViewCount,
    p.OwnerUserId,
    p.LastActivityDate,
    p.Reputation,
    p.DisplayName,
    p.UserCreationDate,
    p.BadgeCount,
    p.VoteCount,
    p.CommentCount,
    -- window: rolling average of score over last 7 posts in same day
    AVG(p.Score) OVER (PARTITION BY DATE(p.CreationDate) ORDER BY p.CreationDate ROWS BETWEEN 6 PRECEDING AND CURRENT ROW) AS SevenDayAvgScore,
    -- derived metrics with NULL handling
    (p.Score + COALESCE(p.VoteCount,0) - COALESCE(p.CommentCount,0)) AS NetEngagement,
    CASE
      WHEN p.ViewCount > 1000 THEN 'High Exposure'
      WHEN p.ViewCount BETWEEN 500 AND 999 THEN 'Medium Exposure'
      ELSE 'Low Exposure'
    END AS ExposureCategory
  FROM qualified_posts p
)
SELECT
  s.PostId,
  s.Title,
  s.Tags,
  s.CreationDate,
  s.Score,
  s.ViewCount,
  s.OwnerUserId,
  s.LastActivityDate,
  s.Reputation,
  s.DisplayName,
  s.UserCreationDate,
  s.BadgeCount,
  s.VoteCount,
  s.CommentCount,
  s.SevenDayAvgScore,
  s.NetEngagement,
  s.ExposureCategory
FROM stats s
ORDER BY s.CreationDate DESC, s.Score DESC
LIMIT 100;