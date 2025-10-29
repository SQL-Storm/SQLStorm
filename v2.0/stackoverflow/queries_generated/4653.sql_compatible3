WITH RECURSIVE PostHierarchy AS (
  SELECT
    p.Id AS PostId,
    p.PostTypeId,
    p.ParentId,
    p.OwnerUserId,
    p.Score,
    p.CreationDate,
    p.Title,
    p.AnswerCount,
    p.FavoriteCount,
    0 AS Level,
    CAST(p.Id AS VARCHAR(255)) AS Path
  FROM Posts AS p
  WHERE
    p.PostTypeId = 1
  UNION ALL
  SELECT
    p.Id AS PostId,
    p.PostTypeId,
    p.ParentId,
    p.OwnerUserId,
    p.Score,
    p.CreationDate,
    p.Title,
    p.AnswerCount,
    p.FavoriteCount,
    ph.Level + 1 AS Level,
    CAST(ph.Path || '->' || CAST(p.Id AS VARCHAR(255)) AS VARCHAR(255)) AS Path
  FROM Posts AS p
  INNER JOIN PostHierarchy AS ph
    ON p.ParentId = ph.PostId
  WHERE
    p.PostTypeId = 2
), AggregatedPostData AS (
  SELECT
    ph.PostId,
    ph.Title,
    ph.Score AS QuestionScore,
    ph.AnswerCount,
    ph.FavoriteCount AS QuestionFavoriteCount,
    COUNT(CASE WHEN c.Score > 0 THEN 1 END) AS PositiveCommentCount,
    SUM(CASE WHEN c.Score > 0 THEN c.Score ELSE 0 END) AS TotalPositiveCommentScore,
    ph.Level,
    ph.Path,
    u.Reputation AS OwnerReputation,
    u.CreationDate AS OwnerCreationDate,
    ph.PostTypeId,
    CASE WHEN ph.PostTypeId = 1 THEN ph.AnswerCount ELSE 0 END AS AnswerCountForQuestions,
    CASE WHEN ph.PostTypeId = 2 THEN ph.Score ELSE 0 END AS AnswerScore,
    CASE WHEN ph.PostTypeId = 1 AND ph.FavoriteCount IS NOT NULL THEN 1 ELSE 0 END AS IsFavoritedQuestion,
    ph.CreationDate AS PostCreationDate,
    CAST(EXTRACT(EPOCH FROM (TIMESTAMP '2024-10-01 12:34:56' - ph.CreationDate)) / 60 AS BIGINT) AS MinutesSinceCreation,
    CASE WHEN ph.Title IS NULL THEN 'No Title' ELSE SUBSTRING(ph.Title FROM 1 FOR 50) END AS ShortTitle,
    RANK() OVER (PARTITION BY ph.PostTypeId ORDER BY ph.Score DESC) AS ScoreRankPerPostType,
    ROW_NUMBER() OVER (ORDER BY ph.CreationDate DESC) AS GlobalCreationOrder
  FROM PostHierarchy AS ph
  LEFT JOIN Comments AS c
    ON ph.PostId = c.PostId
  LEFT JOIN Users AS u
    ON ph.OwnerUserId = u.Id
  WHERE
    ph.PostTypeId IN (1, 2)
  GROUP BY
    ph.PostId,
    ph.Title,
    ph.Score,
    ph.AnswerCount,
    ph.FavoriteCount,
    ph.Level,
    ph.Path,
    u.Reputation,
    u.CreationDate,
    ph.PostTypeId,
    ph.CreationDate
), UserInteraction AS (
  SELECT
    u.Id AS UserId,
    COUNT(v.Id) AS TotalVotes,
    SUM(CASE WHEN v.VoteTypeId = 2 THEN 1 ELSE 0 END) AS TotalUpvotes,
    SUM(CASE WHEN v.VoteTypeId = 3 THEN 1 ELSE 0 END) AS TotalDownvotes,
    COUNT(DISTINCT ph.PostId) AS PostsParticipatedIn
  FROM Users AS u
  LEFT JOIN Votes AS v
    ON u.Id = v.UserId
  LEFT JOIN PostHierarchy AS ph
    ON u.Id = ph.OwnerUserId OR u.Id = v.UserId
  WHERE
    u.Reputation > 1000
  GROUP BY
    u.Id
), PostLinkMetrics AS (
  SELECT
    pl.PostId,
    COUNT(pl.Id) AS LinkCount,
    SUM(CASE WHEN lt.Name = 'Duplicate' THEN 1 ELSE 0 END) AS DuplicateLinkCount,
    SUM(CASE WHEN lt.Name = 'Linked' THEN 1 ELSE 0 END) AS LinkedLinkCount
  FROM PostLinks AS pl
  JOIN LinkTypes AS lt
    ON pl.LinkTypeId = lt.Id
  GROUP BY
    pl.PostId
)
SELECT
  apd.PostId,
  apd.Title,
  apd.QuestionScore,
  apd.AnswerCountForQuestions,
  apd.QuestionFavoriteCount,
  apd.PositiveCommentCount,
  apd.TotalPositiveCommentScore,
  apd.OwnerReputation,
  apd.OwnerCreationDate,
  apd.AnswerScore,
  apd.IsFavoritedQuestion,
  apd.PostCreationDate,
  apd.MinutesSinceCreation,
  apd.ShortTitle,
  apd.ScoreRankPerPostType,
  apd.GlobalCreationOrder,
  COALESCE(uil.TotalVotes, 0) AS UserTotalVotes,
  COALESCE(uil.TotalUpvotes, 0) AS UserTotalUpvotes,
  COALESCE(uil.TotalDownvotes, 0) AS UserTotalDownvotes,
  COALESCE(uil.PostsParticipatedIn, 0) AS UserPostsParticipatedIn,
  COALESCE(plm.LinkCount, 0) AS TotalPostLinks,
  COALESCE(plm.DuplicateLinkCount, 0) AS TotalDuplicateLinks,
  COALESCE(plm.LinkedLinkCount, 0) AS TotalLinkedLinks,
  CASE
    WHEN apd.QuestionScore > 100 AND apd.AnswerCountForQuestions > 10 AND apd.OwnerReputation > 5000
    THEN 'High Engagement'
    WHEN apd.QuestionScore <= 0 AND apd.AnswerCountForQuestions = 0
    THEN 'Low Engagement'
    ELSE 'Moderate Engagement'
  END AS EngagementCategory,
  UPPER(COALESCE(SUBSTRING(apd.Title FROM 1 FOR 3), '???')) AS FirstThreeCharsOfTitleUpper,
  CASE
    WHEN apd.Level = 0 THEN 'Root Question'
    WHEN apd.Level = 1 THEN 'Direct Answer'
    ELSE 'Deeper Level Content'
  END AS HierarchyLevelDescription,
  CASE
    WHEN apd.PostCreationDate BETWEEN (TIMESTAMP '2024-10-01 12:34:56' - INTERVAL '7 days') AND TIMESTAMP '2024-10-01 12:34:56' THEN 'Recent'
    WHEN apd.PostCreationDate BETWEEN (TIMESTAMP '2024-10-01 12:34:56' - INTERVAL '1 month') AND (TIMESTAMP '2024-10-01 12:34:56' - INTERVAL '7 days') THEN 'Last Month'
    ELSE 'Older'
  END AS PostAgeGroup,
  CASE WHEN apd.ScoreRankPerPostType BETWEEN 1 AND 100 THEN 'Top 100' ELSE 'Outside Top 100' END AS TopScoreIndicator,
  apd.Path,
  (
    SELECT
      COUNT(*)
    FROM Comments AS sub_c
    WHERE
      sub_c.PostId = apd.PostId AND POSITION('interesting' IN sub_c.Text) > 0
  ) AS CountOfInterestingComments,
  (
    SELECT
      COUNT(*)
    FROM PostHistory AS ph_hist
    WHERE
      ph_hist.PostId = apd.PostId AND ph_hist.PostHistoryTypeId IN (4, 5)
  ) AS EditHistoryCount,
  CASE
    WHEN apd.OwnerCreationDate IS NULL THEN 'Unknown User'
    WHEN DATE_PART('year', AGE(TIMESTAMP '2024-10-01 12:34:56', apd.OwnerCreationDate)) < 1 THEN 'New User'
    ELSE 'Established User'
  END AS UserAgeCategory
FROM AggregatedPostData AS apd
LEFT JOIN UserInteraction AS uil
  ON apd.OwnerReputation IS NOT NULL AND apd.OwnerReputation >= 0 AND apd.PostId = uil.UserId
LEFT JOIN PostLinkMetrics AS plm
  ON apd.PostId = plm.PostId
WHERE
  apd.OwnerReputation >= 50
  AND apd.ScoreRankPerPostType <= 500
  AND apd.PostCreationDate >= (TIMESTAMP '2024-10-01 12:34:56' - INTERVAL '5 years')
ORDER BY
  apd.GlobalCreationOrder DESC
LIMIT 1000;