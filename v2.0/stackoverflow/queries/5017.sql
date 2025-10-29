WITH
TopUsers AS (
  SELECT
    u.Id,
    u.DisplayName,
    u.Reputation,
    u.CreationDate,
    u.LastAccessDate,
    ROW_NUMBER() OVER (ORDER BY u.Reputation DESC, u.LastAccessDate DESC) AS rn
  FROM Users u
  WHERE u.AccountId IS NOT NULL
),
UserActivity AS (
  SELECT
    p.OwnerUserId AS UserId,
    COUNT(*) AS PostCount,
    SUM(CASE WHEN p.PostTypeId = 1 THEN 1 ELSE 0 END) AS Questions,
    SUM(CASE WHEN p.PostTypeId = 2 THEN 1 ELSE 0 END) AS Answers,
    SUM(p.ViewCount) AS TotalViews,
    MAX(p.LastActivityDate) AS LastActive
  FROM Posts p
  GROUP BY p.OwnerUserId
),
RecentTagActivity AS (
  SELECT
    u.Id AS UserId,
    (
      SELECT STRING_AGG(tag, ',')
      FROM (
        SELECT TRIM(BOTH '<>' FROM elem) AS tag
        FROM (
          SELECT regexp_split_to_table(p.Tags, '><') AS elem
          FROM Posts p
          WHERE p.OwnerUserId = u.Id
            AND p.Tags IS NOT NULL
          ORDER BY p.LastActivityDate DESC NULLS LAST, p.Id DESC
          LIMIT 5
        ) s1
      ) s2
    ) AS RecentTags
  FROM Users u
),
ComplexPosts AS (
  SELECT
    pr.Id AS PostId,
    pr.OwnerUserId,
    pr.PostTypeId,
    pr.Score,
    pr.ViewCount,
    pr.Title,
    pr.Tags,
    pr.LastActivityDate,
    CASE
      WHEN pr.ClosedDate IS NULL THEN 'Open'
      ELSE 'Closed'
    END AS Status
  FROM Posts pr
  LEFT JOIN PostHistory ph ON ph.PostId = pr.Id
  WHERE (pr.Score > 5 OR pr.ViewCount > 100)
    AND pr.LastActivityDate IS NOT NULL
    AND (pr.OwnerUserId IS NULL OR pr.OwnerUserId > 0)
)
SELECT
  tu.Id AS UserId,
  tu.DisplayName,
  tu.Reputation,
  ta.PostCount,
  ta.Questions,
  ta.Answers,
  ta.TotalViews,
  ra.RecentTags,
  COALESCE(cv.UpvotesFromRecent, 0) AS UpvotesFromRecent,
  COALESCE(bn.BountyTotal, 0) AS BountyTotal,
  c.Statuses AS PostStatuses
FROM TopUsers tu
JOIN UserActivity ta ON ta.UserId = tu.Id
LEFT JOIN RecentTagActivity ra ON ra.UserId = tu.Id
LEFT JOIN (
  SELECT
    v.UserId,
    SUM(CASE WHEN v.VoteTypeId = 2 THEN 1 ELSE 0 END) AS UpvotesFromRecent
  FROM Votes v
  WHERE v.CreationDate >= (CAST('2024-10-01 12:34:56' AS timestamp) - INTERVAL '30 days')
  GROUP BY v.UserId
) cv ON cv.UserId = tu.Id
LEFT JOIN (
  SELECT
    p.OwnerUserId,
    SUM(COALESCE(v.BountyAmount, 0)) AS BountyTotal
  FROM Posts p
  LEFT JOIN Votes v ON v.PostId = p.Id AND v.VoteTypeId = 8
  GROUP BY p.OwnerUserId
) bn ON bn.OwnerUserId = tu.Id
LEFT JOIN (
  SELECT
    p.OwnerUserId AS UserId,
    STRING_AGG(CONCAT('Post', p.PostId, ' (', p.Status, ')'), ', ') AS Statuses
  FROM ComplexPosts p
  GROUP BY p.OwnerUserId
) c ON c.UserId = tu.Id
WHERE tu.rn <= 100
GROUP BY
  tu.Id,
  tu.DisplayName,
  tu.Reputation,
  ta.PostCount,
  ta.Questions,
  ta.Answers,
  ta.TotalViews,
  ra.RecentTags,
  cv.UpvotesFromRecent,
  bn.BountyTotal,
  c.Statuses,
  tu.rn
ORDER BY ta.PostCount DESC, ta.TotalViews DESC
LIMIT 100;