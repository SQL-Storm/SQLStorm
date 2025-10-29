WITH RankedPopularQuestions AS (
  SELECT
    p.Id AS PostId,
    p.Title,
    p.CreationDate,
    p.OwnerUserId,
    p.ViewCount,
    p.Score,
    p.Tags,
    COALESCE(a.Id, NULL) AS AcceptedAnswerId,
    ROW_NUMBER() OVER (
      PARTITION BY p.OwnerUserId
      ORDER BY p.ViewCount * 0.6 + p.Score * 1.2 + COALESCE(p.FavoriteCount, 0) * 2 DESC,
               p.CreationDate DESC
    ) AS rn_owner
  FROM Posts p
  LEFT JOIN Posts a ON p.AcceptedAnswerId = a.Id
  WHERE p.PostTypeId = 1
    AND p.ClosedDate IS NULL
),
RecentActivity AS (
  SELECT
    p.Id AS PostId,
    p.Title,
    p.CreationDate,
    p.LastActivityDate,
    p.OwnerUserId,
    p.Tags,
    ROW_NUMBER() OVER (
      ORDER BY p.LastActivityDate DESC,
               p.ViewCount DESC
    ) AS recent_rank
  FROM Posts p
  WHERE p.PostTypeId = 1
),
TagPopularity AS (
  SELECT
    t.TagName,
    t.Count,
    t.ExcerptPostId
  FROM Tags t
  WHERE t.IsModeratorOnly = FALSE
)
SELECT
  rp.PostId,
  rp.Title AS QuestionTitle,
  rp.CreationDate AS QuestionCreationDate,
  rp.OwnerUserId,
  rp.ViewCount,
  rp.Score,
  rp.Tags,
  ra.Id AS AcceptedAnswerId,
  rp.rn_owner AS OwnerRank,
  (ra.Id IS NOT NULL) AS HasAcceptedAnswer,
  ra.FavoriteCount,
  ra.LastActivityDate,
  ra_recent.recent_rank AS RecentRank,
  u.DisplayName AS OwnerDisplayName,
  u.Reputation,
  u.Location,
  u.AccountId,
  b.Name AS BadgeName,
  v_vote.Name AS LastVoteTypeName,
  v_type.Name AS VoteTypeName
FROM RankedPopularQuestions rp
LEFT JOIN Posts ra ON ra.Id = rp.AcceptedAnswerId
LEFT JOIN Users u ON rp.OwnerUserId = u.Id
LEFT JOIN Badges b ON b.UserId = u.Id
LEFT JOIN (
  SELECT
    PostId,
    MAX(CASE WHEN VoteTypeId = 6 THEN CreationDate END) AS LastCloseVoteDate,
    MAX(CASE WHEN VoteTypeId = 2 THEN CreationDate END) AS LastUpvoteDate,
    MAX(CASE WHEN VoteTypeId = 10 THEN CreationDate END) AS LastDeletionDate
  FROM Votes
  GROUP BY PostId
) v ON v.PostId = rp.PostId
LEFT JOIN VoteTypes v_type ON v_type.Id = 2
LEFT JOIN (
  SELECT CAST(column1 AS VARCHAR) AS Name, CAST(column2 AS INTEGER) AS Id FROM (VALUES ('UpMod',2), ('DownMod',3), ('Accepted',1)) AS x(column1, column2)
) AS v_vote ON v_vote.Id = 2
LEFT JOIN RecentActivity ra_recent ON ra_recent.PostId = rp.PostId
GROUP BY
  rp.PostId,
  rp.Title,
  rp.CreationDate,
  rp.OwnerUserId,
  rp.ViewCount,
  rp.Score,
  rp.Tags,
  ra.Id,
  rp.rn_owner,
  ra.FavoriteCount,
  ra.LastActivityDate,
  ra_recent.recent_rank,
  u.DisplayName,
  u.Reputation,
  u.Location,
  u.AccountId,
  b.Name,
  v_vote.Name,
  v_type.Name
ORDER BY rp.rn_owner ASC
FETCH FIRST 100 ROWS ONLY;