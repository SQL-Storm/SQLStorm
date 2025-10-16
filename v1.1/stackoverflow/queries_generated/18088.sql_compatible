WITH
  RankedPostEdits AS (
    SELECT
      ph.PostId,
      ph.UserId,
      ph.CreationDate AS EditDate,
      ph.PostHistoryTypeId,
      pht.Name AS HistoryTypeName,
      ROW_NUMBER() OVER (PARTITION BY ph.PostId ORDER BY ph.CreationDate DESC) AS rn
    FROM
      PostHistory ph
    JOIN
      PostHistoryTypes pht
      ON ph.PostHistoryTypeId = pht.Id
    WHERE
      ph.PostHistoryTypeId IN (4, 5, 6)
  ),
  UserPostActivity AS (
    SELECT
      p.OwnerUserId,
      COUNT(DISTINCT p.Id) AS QuestionCount,
      SUM(CASE WHEN p.PostTypeId = 2 THEN 1 ELSE 0 END) AS AnswerCount,
      SUM(p.ViewCount) AS TotalViews,
      MAX(p.CreationDate) AS LatestPostDate
    FROM
      Posts p
    WHERE
      p.OwnerUserId IS NOT NULL
      AND p.OwnerUserId <> -1
      AND p.PostTypeId IN (1, 2)
    GROUP BY
      p.OwnerUserId
  ),
  HighReputationUsers AS (
    SELECT
      u.Id,
      u.DisplayName,
      u.Reputation,
      u.CreationDate,
      u.UpVotes,
      u.DownVotes,
      u.Views AS ProfileViews,
      CASE
        WHEN u.WebsiteUrl IS NOT NULL AND u.WebsiteUrl <> '' THEN 'Has Website'
        WHEN u.Location IS NOT NULL AND u.Location <> '' THEN 'Has Location'
        ELSE 'No External Info'
      END AS UserInfoStatus
    FROM
      Users u
    WHERE
      u.Reputation > 10000
  )
SELECT
  hru.DisplayName,
  hru.Reputation,
  hru.UserInfoStatus,
  upa.QuestionCount,
  upa.AnswerCount,
  upa.TotalViews,
  rpe.EditDate AS LatestEditDate,
  rpe.HistoryTypeName AS LatestEditType,
  COALESCE(
    (
      SELECT COUNT(*) FROM Badges b WHERE b.UserId = hru.Id AND b.Class = 1
    ), 0
  ) AS GoldBadgeCount,
  COALESCE(
    (
      SELECT SUM(CASE WHEN v.VoteTypeId = 2 THEN 1 ELSE 0 END) FROM Votes v WHERE v.UserId = hru.Id
    ), 0
  ) AS TotalUpvotesCast,
  p.Title AS SamplePostTitle,
  p.CreationDate AS SamplePostDate,
  p.Score AS SamplePostScore,
  CASE
    WHEN p.ClosedDate IS NOT NULL THEN 'Closed'
    WHEN p.CommunityOwnedDate IS NOT NULL THEN 'Community Owned'
    ELSE 'Active'
  END AS PostStatus,
  '--' || LOWER(SUBSTRING(p.Tags FROM 2 FOR (POSITION('>' IN p.Tags) - 2))) || '--' AS TagSubstringExample
FROM
  HighReputationUsers hru
LEFT JOIN
  UserPostActivity upa
  ON hru.Id = upa.OwnerUserId
LEFT JOIN
  RankedPostEdits rpe
  ON hru.Id = rpe.UserId AND rpe.rn = 1
LEFT JOIN
  Posts p
  ON hru.Id = p.OwnerUserId AND p.PostTypeId = 1
WHERE
  (upa.LatestPostDate BETWEEN hru.CreationDate AND (CAST('2024-10-01 12:34:56' AS timestamp) - INTERVAL '1 year'))
  OR upa.AnswerCount > 50

UNION ALL

SELECT
  hru.DisplayName,
  hru.Reputation,
  hru.UserInfoStatus,
  upa.QuestionCount,
  upa.AnswerCount,
  upa.TotalViews,
  rpe.EditDate AS LatestEditDate,
  rpe.HistoryTypeName AS LatestEditType,
  COALESCE(
    (
      SELECT COUNT(*) FROM Badges b WHERE b.UserId = hru.Id AND b.Class = 2
    ), 0
  ) AS SilverBadgeCount,
  COALESCE(
    (
      SELECT SUM(CASE WHEN v.VoteTypeId = 3 THEN 1 ELSE 0 END) FROM Votes v WHERE v.UserId = hru.Id
    ), 0
  ) AS TotalDownvotesCast,
  p.Title AS SamplePostTitle,
  p.CreationDate AS SamplePostDate,
  p.Score AS SamplePostScore,
  CASE
    WHEN p.ClosedDate IS NOT NULL THEN 'Closed'
    WHEN p.CommunityOwnedDate IS NOT NULL THEN 'Community Owned'
    ELSE 'Active'
  END AS PostStatus,
  '--' || UPPER(SUBSTRING(p.Tags FROM 2 FOR (POSITION('>' IN p.Tags) - 2))) || '--' AS TagSubstringExample
FROM
  HighReputationUsers hru
JOIN
  UserPostActivity upa
  ON hru.Id = upa.OwnerUserId
JOIN
  RankedPostEdits rpe
  ON hru.Id = rpe.UserId AND rpe.rn = 1
JOIN
  Posts p
  ON hru.Id = p.OwnerUserId AND p.PostTypeId = 2
WHERE
  upa.TotalViews > 1000000
  OR (upa.QuestionCount > 0 AND upa.AnswerCount = 0)
ORDER BY
  Reputation DESC
LIMIT 100;