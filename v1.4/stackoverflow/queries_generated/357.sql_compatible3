WITH
  -- Basic user context
  user_base AS (
    SELECT
      u.Id AS UserId,
      u.DisplayName,
      u.Reputation,
      u.CreationDate,
      u.LastAccessDate,
      COALESCE(u.Location, 'Unknown') AS Location
    FROM Users u
  ),
  -- Per-user post statistics
  post_agg AS (
    SELECT
      p.OwnerUserId AS UserId,
      COUNT(*) AS PostCount,
      AVG(p.Score) AS AvgPostScore,
      SUM(p.ViewCount) AS TotalViews,
      MAX(p.LastActivityDate) AS LastActive
    FROM Posts p
    GROUP BY p.OwnerUserId
  ),
  -- Per-user badge count
  badge_agg AS (
    SELECT b.UserId, COUNT(*) AS BadgeCount
    FROM Badges b
    GROUP BY b.UserId
  ),
  -- Per-user comment count on their posts
  comment_agg AS (
    SELECT p.OwnerUserId AS UserId, COUNT(c.Id) AS CommentCount
    FROM Posts p
    LEFT JOIN Comments c ON c.PostId = p.Id
    GROUP BY p.OwnerUserId
  ),
  -- Per-user linked posts
  link_agg AS (
    SELECT p.OwnerUserId AS UserId, COUNT(pl.Id) AS LinkedPostCount
    FROM Posts p
    LEFT JOIN PostLinks pl ON pl.PostId = p.Id
    GROUP BY p.OwnerUserId
  ),
  -- Last activity date across user's posts
  last_active AS (
    SELECT p.OwnerUserId AS UserId, MAX(p.LastActivityDate) AS LastActive
    FROM Posts p
    GROUP BY p.OwnerUserId
  ),
  -- Top tag per user (correlated subquery)
  top_tag_per_user AS (
    SELECT u.Id AS UserId,
           (
             SELECT tag
             FROM (
               SELECT
                 unnest(string_to_array(substring(p.Tags FROM 2 FOR char_length(p.Tags) - 2), '><')) AS tag
               FROM Posts p
               WHERE p.OwnerUserId = u.Id
             ) s
             GROUP BY tag
             ORDER BY COUNT(*) DESC
             LIMIT 1
           ) AS TopTag
    FROM Users u
  ),
  -- Composite metrics per user
  composite AS (
    SELECT
      bu.UserId,
      bu.DisplayName,
      bu.Reputation,
      bu.Location,
      COALESCE(po.PostCount, 0) AS PostCount,
      COALESCE(po.AvgPostScore, 0) AS AvgPostScore,
      COALESCE(po.TotalViews, 0) AS TotalViews,
      COALESCE(ba.BadgeCount, 0) AS BadgeCount,
      COALESCE(co.CommentCount, 0) AS CommentCount,
      COALESCE(li.LinkedPostCount, 0) AS LinkedPostCount,
      COALESCE(la.LastActive, bu.CreationDate) AS LastActive,
      COALESCE(tTop.TopTag, 'Unknown') AS TopTag,
      CONCAT(bu.DisplayName, ' [Rep=', bu.Reputation, ', TopTag=', COALESCE(tTop.TopTag, 'Unknown'), ', LastActive=', COALESCE(CAST(la.LastActive AS TEXT), 'NULL'), ']') AS DisplaySummary,
      (COALESCE(po.TotalViews, 0) * 0.5 +
       COALESCE(po.AvgPostScore, 0) * 1.5 +
       COALESCE(ba.BadgeCount, 0) * 2.0 +
       COALESCE(bu.Reputation, 0) * 1.0 -
       COALESCE(co.CommentCount, 0) * 0.25) AS CompositeScore
    FROM user_base bu
    LEFT JOIN post_agg po ON po.UserId = bu.UserId
    LEFT JOIN badge_agg ba ON ba.UserId = bu.UserId
    LEFT JOIN comment_agg co ON co.UserId = bu.UserId
    LEFT JOIN link_agg li ON li.UserId = bu.UserId
    LEFT JOIN last_active la ON la.UserId = bu.UserId
    LEFT JOIN top_tag_per_user tTop ON tTop.UserId = bu.UserId
  ),
  -- Rank users by composite score
  ranked AS (
    SELECT c.*,
           ROW_NUMBER() OVER (ORDER BY c.CompositeScore DESC) AS Rank
    FROM composite c
  ),
  -- A first set: top 120 by rank
  top_by_rank AS (
    SELECT *
    FROM ranked
    WHERE Rank <= 120
  )
SELECT *
FROM top_by_rank
UNION
SELECT *
FROM ranked
WHERE LastActive IS NULL
ORDER BY Rank
LIMIT 240;