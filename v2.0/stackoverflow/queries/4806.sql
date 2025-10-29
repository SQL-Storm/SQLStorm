-- {"query": "4806.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gemini-2.5-flash-lite", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2111, "output_tokens": 1179}
WITH
  RankedPostEdits AS (
    SELECT
      ph.PostId,
      ph.UserId,
      ph.CreationDate,
      ph.PostHistoryTypeId,
      ROW_NUMBER() OVER (PARTITION BY ph.PostId, ph.UserId ORDER BY ph.CreationDate DESC) AS rn
    FROM
      PostHistory ph
    WHERE
      ph.PostHistoryTypeId IN (4, 5, 6) AND ph.UserId IS NOT NULL
  ),
  UserContributionSummary AS (
    SELECT
      u.Id AS UserId,
      u.DisplayName,
      COUNT(DISTINCT p.Id) AS TotalPosts,
      SUM(CASE WHEN p.PostTypeId = 1 THEN 1 ELSE 0 END) AS QuestionsCount,
      SUM(CASE WHEN p.PostTypeId = 2 THEN 1 ELSE 0 END) AS AnswersCount,
      AVG(p.Score) AS AveragePostScore,
      COUNT(DISTINCT b.Id) AS BadgeCount,
      SUM(CASE WHEN b.Class = 1 THEN 1 ELSE 0 END) AS GoldBadges,
      SUM(CASE WHEN b.Class = 2 THEN 1 ELSE 0 END) AS SilverBadges,
      SUM(CASE WHEN b.Class = 3 THEN 1 ELSE 0 END) AS BronzeBadges
    FROM
      Users u
      LEFT JOIN Posts p
        ON u.Id = p.OwnerUserId
      LEFT JOIN Badges b
        ON u.Id = b.UserId
    GROUP BY
      u.Id,
      u.DisplayName
  ),
  HighReputationUsers AS (
    SELECT
      Id,
      DisplayName,
      Reputation,
      CreationDate
    FROM
      Users
    WHERE
      Reputation > 50000
  )
SELECT
  p.Id AS PostId,
  p.Title,
  pt.Name AS PostType,
  p.CreationDate AS PostCreationDate,
  p.Score AS PostScore,
  COALESCE(p.AnswerCount, 0) AS AnswerCount,
  p.ViewCount AS PostViewCount,
  u.DisplayName AS OwnerDisplayName,
  u.Reputation AS OwnerReputation,
  COUNT(DISTINCT c.Id) AS CommentCountOnPost,
  (
    SELECT
      COUNT(*)
    FROM
      PostHistory ph_inner
    WHERE
      ph_inner.PostId = p.Id AND ph_inner.PostHistoryTypeId IN (4, 5, 6)
  ) AS EditCountForPost,
  CASE
    WHEN p.ClosedDate IS NOT NULL THEN 'Closed'
    WHEN p.CommunityOwnedDate IS NOT NULL THEN 'Community Owned'
    ELSE 'Active'
  END AS PostStatus,
  CASE
    WHEN hr.Id IS NOT NULL THEN 'High Reputation User'
    ELSE 'Standard User'
  END AS OwnerPrivilegeLevel,
  CASE
    WHEN rpe.UserId IS NOT NULL THEN 'Has Recent Edits'
    ELSE 'No Recent Edits'
  END AS EditStatus,
  COALESCE(lr.Name, 'N/A') AS LastPostLinkType,
  COALESCE(
    (
      SELECT
        STRING_AGG(sub.UserDisplayName, '; ' ORDER BY sub.min_ct)
      FROM
        (
          SELECT
            c_inner.UserDisplayName,
            MIN(c_inner.CreationDate) AS min_ct,
            c_inner.PostId
          FROM
            Comments c_inner
          WHERE
            c_inner.PostId = p.Id AND c_inner.UserId IS NOT NULL
          GROUP BY
            c_inner.PostId,
            c_inner.UserDisplayName
        ) sub
    ),
    'No Comments'
  ) AS CommentersList
FROM
  Posts p
  JOIN PostTypes pt
    ON p.PostTypeId = pt.Id
  LEFT JOIN Users u
    ON p.OwnerUserId = u.Id
  LEFT JOIN Comments c
    ON p.Id = c.PostId
  LEFT JOIN (
    SELECT DISTINCT
      pl.PostId,
      lt.Name
    FROM
      PostLinks pl
      JOIN LinkTypes lt
        ON pl.LinkTypeId = lt.Id
    WHERE
      lt.Name = 'Duplicate'
  ) dl
    ON p.Id = dl.PostId
  LEFT JOIN RankedPostEdits rpe
    ON p.Id = rpe.PostId AND rpe.rn = 1
  LEFT JOIN HighReputationUsers hr
    ON u.Id = hr.Id
  LEFT JOIN PostLinks pl_last
    ON p.Id = pl_last.PostId
  LEFT JOIN LinkTypes lr
    ON pl_last.LinkTypeId = lr.Id
GROUP BY
  p.Id,
  p.Title,
  pt.Name,
  p.CreationDate,
  p.Score,
  p.AnswerCount,
  p.ViewCount,
  u.DisplayName,
  u.Reputation,
  CASE
    WHEN p.ClosedDate IS NOT NULL THEN 'Closed'
    WHEN p.CommunityOwnedDate IS NOT NULL THEN 'Community Owned'
    ELSE 'Active'
  END,
  CASE
    WHEN hr.Id IS NOT NULL THEN 'High Reputation User'
    ELSE 'Standard User'
  END,
  CASE
    WHEN rpe.UserId IS NOT NULL THEN 'Has Recent Edits'
    ELSE 'No Recent Edits'
  END,
  COALESCE(lr.Name, 'N/A')
HAVING
  COUNT(DISTINCT c.Id) > 5 OR p.Score > 100 OR p.AnswerCount > 10 OR p.ViewCount > 10000;