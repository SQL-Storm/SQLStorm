WITH recent_high_activity AS (
  SELECT
    p.Id AS PostId,
    p.Title,
    p.CreationDate,
    p.OwnerUserId,
    p.PostTypeId,
    COALESCE(p.ViewCount, 0) AS ViewCount,
    p.Score,
    p.Tags,
    -- derived metrics
    (SELECT COUNT(*) FROM Comments c WHERE c.PostId = p.Id) AS CommentCount,
    (SELECT COUNT(*) FROM Votes v WHERE v.PostId = p.Id AND v.VoteTypeId = 2) AS UpVotes,
    (SELECT COUNT(*) FROM Votes v WHERE v.PostId = p.Id AND v.VoteTypeId = 3) AS DownVotes,
    (SELECT MAX(CreationDate) FROM Votes v WHERE v.PostId = p.Id) AS LastVoteDate
  FROM Posts p
  WHERE p.PostTypeId = 1
    AND p.CreationDate >= CAST('2024-10-01 12:34:56' AS TIMESTAMP) - INTERVAL '180 days'
),
question_scoring AS (
  SELECT
    r.PostId,
    r.Title,
    r.CreationDate,
    r.OwnerUserId,
    r.PostTypeId,
    r.ViewCount,
    r.Score,
    r.CommentCount,
    r.UpVotes,
    r.DownVotes,
    r.Tags,
    r.LastVoteDate,
    -- advanced computed metrics
    (r.Score * 1.0 + r.UpVotes - r.DownVotes) AS netScore,
    CASE
      WHEN r.ViewCount > 1000 THEN 'High View'
      WHEN r.ViewCount BETWEEN 500 AND 1000 THEN 'Medium View'
      ELSE 'Low View'
    END AS view_band,
    (SELECT AVG(Score) FROM Posts WHERE PostTypeId = 1) AS avg_question_score
  FROM recent_high_activity r
),
top_in_tag AS (
  SELECT
    q.PostId,
    t.TagName,
    tg.Count AS TagPopularity,
    RANK() OVER (PARTITION BY t.TagName ORDER BY q.netScore DESC, q.LastVoteDate DESC) AS rnk_in_tag,
    q.CommentCount,
    q.UpVotes,
    q.DownVotes,
    q.LastVoteDate,
    q.netScore
  FROM question_scoring q
  CROSS JOIN LATERAL (
    SELECT unnest(string_to_array(substring(q.Tags, 2, length(q.Tags) - 2), '><')) AS TagName
  ) t
  JOIN Tags tg ON tg.TagName = t.TagName
),
complex_joins AS (
  SELECT
    t1.PostId,
    t1.Title,
    t1.CreationDate,
    t1.OwnerUserId,
    u.DisplayName AS OwnerDisplayName,
    COALESCE(u.Reputation, 0) AS OwnerReputation,
    COALESCE(b.TotalBadges, 0) AS BadgeCount,
    b.most_recent_badge,
    t1.netScore,
    t1.view_band,
    t1.avg_question_score,
    t2.CommentCount,
    t2.UpVotes,
    t2.DownVotes,
    t2.TagName,
    t1.LastVoteDate,
    t2.rnk_in_tag
  FROM question_scoring t1
  LEFT JOIN Users u ON t1.OwnerUserId = u.Id
  LEFT JOIN (
    SELECT bu.UserId, COUNT(*) AS TotalBadges, MAX(bu.Date) AS most_recent_badge
    FROM Badges bu
    GROUP BY bu.UserId
  ) b ON b.UserId = u.Id
  LEFT JOIN (
    SELECT PostId, CommentCount, UpVotes, DownVotes, TagName, rnk_in_tag
    FROM top_in_tag
    WHERE rnk_in_tag = 1
  ) t2 ON t2.PostId = t1.PostId
  LEFT JOIN (
    SELECT tg.Id, tg.TagName, tg.Count
    FROM Tags tg
  ) t3 ON t3.Id = 1
)
SELECT
  cj.PostId,
  cj.Title,
  cj.CreationDate,
  cj.OwnerUserId,
  cj.OwnerDisplayName,
  cj.OwnerReputation,
  cj.BadgeCount,
  cj.most_recent_badge,
  cj.netScore,
  cj.view_band,
  cj.avg_question_score,
  cj.CommentCount,
  cj.UpVotes,
  cj.DownVotes,
  cj.TagName
FROM complex_joins cj
WHERE cj.rnk_in_tag = 1
ORDER BY cj.netScore DESC, cj.LastVoteDate NULLS LAST
LIMIT 100;