WITH
TopQuestions AS (
  SELECT
    p.Id AS PostId,
    p.Title,
    p.CreationDate,
    p.Score,
    p.ViewCount,
    p.AnswerCount,
    p.CommentCount,
    p.Tags,
    p.OwnerUserId,
    p.LastActivityDate,
    ROW_NUMBER() OVER (
      ORDER BY
        p.Score DESC,
        p.ViewCount DESC,
        p.LastActivityDate DESC
    ) AS rn
  FROM Posts p
  WHERE p.PostTypeId = 1
    AND p.ClosedDate IS NULL
),
UserStats AS (
  SELECT
    u.Id AS UserId,
    u.DisplayName,
    u.Reputation,
    NTILE(10) OVER (ORDER BY u.Reputation ASC) AS ReputationDecile,
    SUM(CASE WHEN b.Class = 1 THEN 1 ELSE 0 END) AS GoldBadges,
    SUM(CASE WHEN b.Class = 2 THEN 1 ELSE 0 END) AS SilverBadges,
    SUM(CASE WHEN b.Class = 3 THEN 1 ELSE 0 END) AS BronzeBadges,
    COUNT(b.Id) AS TotalBadges
  FROM Users u
  LEFT JOIN Badges b ON b.UserId = u.Id
  GROUP BY u.Id, u.DisplayName, u.Reputation
),
RecentEditor AS (
  SELECT
    t.PostId,
    CAST(NULL AS VARCHAR) AS EditorName,
    CAST(NULL AS TIMESTAMP) AS EditorDate
  FROM TopQuestions t
  WHERE 1=0
),
VoteCounts AS (
  SELECT
    v.PostId,
    SUM(CASE WHEN vt.Id = 2 THEN 1 ELSE 0 END) AS UpCount,
    SUM(CASE WHEN vt.Id = 3 THEN 1 ELSE 0 END) AS DownCount
  FROM Votes v
  JOIN VoteTypes vt ON vt.Id = v.VoteTypeId
  GROUP BY v.PostId
),
VoteTypesPerPost AS (
  SELECT
    v.PostId,
    vt.Name AS VoteTypeName
  FROM Votes v
  JOIN VoteTypes vt ON vt.Id = v.VoteTypeId
  WHERE v.PostId IN (SELECT Id FROM Posts WHERE PostTypeId = 1)
)

SELECT
  tq.PostId,
  tq.Title,
  tq.CreationDate,
  tq.Score,
  tq.ViewCount,
  tq.AnswerCount,
  tq.CommentCount,
  tq.Tags,
  uq.Id AS OwnerUserId,
  uq.DisplayName AS OwnerDisplayName,
  sud.Reputation,
  sud.ReputationDecile,
  sud.GoldBadges,
  sud.SilverBadges,
  sud.BronzeBadges,
  sud.TotalBadges,
  tq.LastActivityDate,
  COALESCE(vc_counts.UpCount, 0) AS UpvotesMinusDownvotes,
  STRING_AGG(vtp.VoteTypeName, ', ' ORDER BY vtp.VoteTypeName) AS VoteTypes,
  tq.rn
FROM TopQuestions tq
LEFT JOIN Users uq ON uq.Id = tq.OwnerUserId
LEFT JOIN UserStats sud ON sud.UserId = uq.Id
LEFT JOIN VoteCounts vc_counts ON vc_counts.PostId = tq.PostId
LEFT JOIN VoteTypesPerPost vtp ON vtp.PostId = tq.PostId
WHERE tq.rn <= 100
GROUP BY
  tq.PostId,
  tq.Title,
  tq.CreationDate,
  tq.Score,
  tq.ViewCount,
  tq.AnswerCount,
  tq.CommentCount,
  tq.Tags,
  uq.Id,
  uq.DisplayName,
  sud.Reputation,
  sud.ReputationDecile,
  sud.GoldBadges,
  sud.SilverBadges,
  sud.BronzeBadges,
  sud.TotalBadges,
  tq.LastActivityDate,
  COALESCE(vc_counts.UpCount, 0),
  tq.rn
ORDER BY tq.rn;