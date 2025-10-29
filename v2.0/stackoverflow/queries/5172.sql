-- {"query": "5172.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gpt-5-nano", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2026, "output_tokens": 876}
WITH
recent_closed AS (
  SELECT p.Id AS PostId,
         p.Title,
         p.CreationDate,
         p.LastActivityDate,
         p.OwnerUserId,
         p.Score,
         p.ViewCount,
         p.Tags,
         ct.Name AS CloseReason,
         vh.CreationDate AS CloseVoteDate
  FROM Posts p
  LEFT JOIN PostHistory vh
    ON vh.PostId = p.Id
   AND vh.PostHistoryTypeId = 10
  LEFT JOIN CloseReasonTypes ct
    ON CAST(vh.Comment AS varchar) LIKE '%' || ct.Id || '%'
  WHERE p.ClosedDate IS NOT NULL
),
tag_badges AS (
  SELECT b.UserId,
         b.Name AS BadgeName,
         b.Date,
         b.Class,
         b.TagBased
  FROM Badges b
  WHERE b.TagBased = TRUE
),
top_users AS (
  SELECT u.Id,
         u.DisplayName,
         u.Reputation,
         u.CreationDate,
         u.LastAccessDate,
         u.Views,
         u.UpVotes,
         u.DownVotes,
         u.Location,
         ROW_NUMBER() OVER (PARTITION BY u.Location ORDER BY u.Reputation DESC, u.UpVotes DESC) AS rn
  FROM Users u
  WHERE u.Reputation > 1000
),
activity_window AS (
  SELECT p.Id AS PostId,
         p.OwnerUserId,
         p.Title,
         p.CreationDate,
         p.LastActivityDate,
         EXTRACT(epoch FROM (CAST('2024-10-01 12:34:56' AS timestamp) - p.LastActivityDate)) / 3600 AS hours_inactive,
         (SELECT COUNT(*) FROM Comments c WHERE c.PostId = p.Id) AS CommentCount,
         (SELECT COUNT(*) FROM Votes v WHERE v.PostId = p.Id AND v.VoteTypeId = 2) AS Upvotes,
         (SELECT COUNT(*) FROM Votes v WHERE v.PostId = p.Id AND v.VoteTypeId = 3) AS Downvotes
  FROM Posts p
  WHERE p.PostTypeId = 1 -- questions
    AND p.LastActivityDate > CAST('2024-10-01 12:34:56' AS timestamp) - INTERVAL '30 days'
),
complex_calc AS (
  SELECT a.PostId,
         a.OwnerUserId,
         a.Title,
         a.CommentCount,
         a.Upvotes,
         a.Downvotes,
         (a.Upvotes - a.Downvotes) * 1.0 / NULLIF(a.CommentCount,0) AS engagement_ratio,
         (CASE WHEN a.hours_inactive > 72 THEN TRUE ELSE FALSE END) AS stale
  FROM activity_window a
),
joined AS (
  SELECT c.PostId,
         c.Title,
         c.CreationDate AS PostCreation,
         ro.ReviewerId,
         ro.ReviewerDisplayName,
         ro.ReviewDate,
         t.BadgeName,
         t.Date AS BadgeDate,
         t.Class,
         t.TagBased
  FROM recent_closed c
  LEFT JOIN (
     SELECT v.UserId AS ReviewerId,
            u.DisplayName AS ReviewerDisplayName,
            MAX(v.CreationDate) AS ReviewDate
     FROM Votes v
     JOIN Users u ON u.Id = v.UserId
     WHERE v.VoteTypeId = 6
     GROUP BY v.UserId, u.DisplayName
  ) ro
    ON ro.ReviewerId = c.OwnerUserId
  LEFT JOIN tag_badges t
    ON t.UserId = c.OwnerUserId
  WHERE c.CloseReason IS NOT NULL
)
SELECT
  j.PostId,
  j.Title,
  j.PostCreation,
  j.ReviewerId,
  j.ReviewerDisplayName,
  j.ReviewDate,
  j.BadgeName,
  j.BadgeDate,
  j.Class,
  j.TagBased,
  cf.engagement_ratio,
  cf.stale
FROM joined j
LEFT JOIN complex_calc cf
  ON cf.PostId = j.PostId
LEFT JOIN top_users tu
  ON tu.Id = j.ReviewerId
WHERE tu.rn = 1
ORDER BY j.PostCreation DESC
LIMIT 200;