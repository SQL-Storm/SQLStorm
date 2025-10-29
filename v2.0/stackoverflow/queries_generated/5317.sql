-- {"query": "5317.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gpt-5-nano", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2026, "output_tokens": 883} 
WITH RankedUsers AS (
  SELECT
    u.Id,
    u.DisplayName,
    u.Reputation,
    u.CreationDate,
    u.LastAccessDate,
    u.Location,
    u.Views,
    u.UpVotes,
    u.DownVotes,
    u.ProfileImageUrl,
    u.EmailHash,
    u.AccountId,
    ROW_NUMBER() OVER (
      PARTITION BY
        CASE
          WHEN u.Location IS NULL THEN 'NULL'
          ELSE u.Location
        END
      ORDER BY
        u.Reputation DESC,
        u.UpVotes - u.DownVotes DESC,
        u.CreationDate ASC
    ) AS rn_by_location
  FROM Users u
),
TopLocations AS (
  SELECT
    Location AS location_group,
    COUNT(*) AS user_cnt,
    AVG(Reputation) AS avg_rep,
    MAX(LastAccessDate) AS last_active
  FROM RankedUsers
  GROUP BY Location
  ORDER BY user_cnt DESC
  LIMIT 10
),
PostActivity AS (
  SELECT
    p.OwnerUserId AS user_id,
    p.PostTypeId,
    COUNT(*) FILTER (WHERE p.PostTypeId = 1) AS questions,
    COUNT(*) FILTER (WHERE p.PostTypeId = 2) AS answers,
    SUM(p.ViewCount) AS total_views,
    MAX(p.LastActivityDate) AS last_activity
  FROM Posts p
  GROUP BY p.OwnerUserId, p.PostTypeId
),
UserBadges AS (
  SELECT
    b.UserId,
    COUNT(*) AS badge_cnt,
    STRING_AGG(b.Name, ',') AS badge_names
  FROM Badges b
  GROUP BY b.UserId
),
RecentTags AS (
  SELECT
    t.TagName,
    t.Count,
    t.ExcerptPostId,
    t.WikiPostId
  FROM Tags t
  WHERE t.IsModeratorOnly = 0
),
ComplexQuery AS (
  SELECT
    ru.Id AS user_id,
    ru.DisplayName,
    ru.Reputation,
    ra.avg_rep AS location_avg_rep,
    la.last_active AS last_seen,
    pa.questions,
    pa.total_views,
    ub.badge_cnt,
    ub.badge_names,
    rt.location_group
  FROM RankedUsers ru
  LEFT JOIN TopLocations rt
    ON (CASE WHEN ru.Location IS NULL THEN 'NULL' ELSE ru.Location END) = rt.location_group
  LEFT JOIN PostActivity pa
    ON ru.Id = pa.user_id
  LEFT JOIN UserBadges ub
    ON ru.Id = ub.UserId
  LEFT JOIN LatestActivity la
    ON ru.Id = la.user_id
),
LatestActivity AS (
  SELECT
    u.Id AS user_id,
    MAX(p.LastActivityDate) AS last_seen
  FROM Users u
  LEFT JOIN Posts p ON p.OwnerUserId = u.Id
  GROUP BY u.Id
),
-- correlated subquery example: determine if a user has any post with more than 100 views
UsersWithPopularPosts AS (
  SELECT
    u.Id
  FROM Users u
  WHERE EXISTS (
    SELECT 1
    FROM Posts p
    WHERE p.OwnerUserId = u.Id
      AND p.ViewCount > 100
  )
),
-- window: rank posts per user by LastActivityDate
UserPostRecency AS (
  SELECT
    p.Id AS post_id,
    p.OwnerUserId,
    p.LastActivityDate,
    ROW_NUMBER() OVER (
      PARTITION BY p.OwnerUserId
      ORDER BY p.LastActivityDate DESC
    ) AS rn
  FROM Posts p
)
SELECT
  cu.user_id,
  cu.DisplayName,
  cu.Reputation,
  cu.location_group,
  cu.last_seen,
  cu.questions,
  cu.total_views,
  cu.badge_cnt,
  cu.badge_names,
  pR.post_id AS most_recent_post_id,
  pR.LastActivityDate AS most_recent_post_date,
  pR.rn AS post_rank
FROM ComplexQuery cu
LEFT JOIN UserPostRecency pR
  ON cu.user_id = pR.OwnerUserId AND pR.rn = 1
ORDER BY cu.Reputation DESC, cu.total_views DESC
LIMIT 100;