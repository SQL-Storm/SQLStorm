WITH
  UserPostActivity AS (
    SELECT
      p.OwnerUserId,
      COUNT(p.Id) AS PostCount,
      SUM(p.Score) AS TotalScore,
      MAX(p.CreationDate) AS LastPostDate,
      AVG(p.ViewCount) AS AvgViewCount,
      SUM(CASE WHEN p.PostTypeId = 1 THEN 1 ELSE 0 END) AS QuestionCount,
      SUM(CASE WHEN p.PostTypeId = 2 THEN 1 ELSE 0 END) AS AnswerCount
    FROM
      Posts p
    WHERE
      p.OwnerUserId IS NOT NULL
      AND p.OwnerUserId > 0
    GROUP BY
      p.OwnerUserId
  ),
  UserReputationChange AS (
    SELECT
      u.Id AS UserId,
      u.Reputation AS CurrentReputation,
      (u.Reputation - COALESCE(prev.Reputation, u.Reputation)) AS ReputationChange,
      u.CreationDate AS UserCreationDate,
      u.LastAccessDate AS UserLastAccessDate
    FROM
      Users u
    LEFT JOIN
      (
        SELECT
          Id,
          Reputation,
          ROW_NUMBER() OVER (PARTITION BY Id ORDER BY CreationDate DESC) as rn
        FROM Users
      ) prev ON u.Id = prev.Id AND prev.rn = 2
  ),
  HighEngagementUsers AS (
    SELECT
      upa.OwnerUserId
    FROM
      UserPostActivity upa
    WHERE
      upa.PostCount > 100
      AND upa.TotalScore > 500
      AND upa.AvgViewCount > 1000
  ),
  RecentActivityPosts AS (
    SELECT
      p.Id,
      p.OwnerUserId,
      p.Title,
      p.CreationDate,
      p.LastActivityDate,
      p.Score,
      p.ViewCount,
      CAST((EXTRACT(EPOCH FROM (p.LastActivityDate - p.CreationDate)) / 86400) AS INTEGER) AS ActivityLagDays,
      CASE WHEN p.ClosedDate IS NOT NULL THEN 1 ELSE 0 END AS IsClosed
    FROM
      Posts p
    WHERE
      p.CreationDate >= (TIMESTAMP '2024-10-01 12:34:56' - INTERVAL '6 months')
  ),
  PostHistorySummaries AS (
    SELECT
      ph.PostId,
      COUNT(CASE WHEN ph.PostHistoryTypeId IN (1, 4, 7) THEN 1 END) AS TitleEdits,
      COUNT(CASE WHEN ph.PostHistoryTypeId IN (2, 5, 8) THEN 1 END) AS BodyEdits,
      COUNT(CASE WHEN ph.PostHistoryTypeId IN (3, 6, 9) THEN 1 END) AS TagEdits,
      MAX(CASE WHEN ph.PostHistoryTypeId = 10 THEN ph.CreationDate END) AS LastCloseVoteDate,
      MAX(CASE WHEN ph.PostHistoryTypeId = 11 THEN ph.CreationDate END) AS LastReopenVoteDate,
      COUNT(DISTINCT ph.UserId) AS UniqueEditors
    FROM
      PostHistory ph
    GROUP BY
      ph.PostId
  ),
  TagUsage AS (
    SELECT
      t.TagName,
      COUNT(pl.PostId) AS LinkCount,
      AVG(p.Score) AS AvgPostScoreForTag
    FROM
      Tags t
    JOIN
      Posts p ON POSITION(CONCAT('<', t.TagName, '>') IN p.Tags) > 0
    LEFT JOIN
      PostLinks pl ON pl.PostId = p.Id AND pl.LinkTypeId = 1
    WHERE
      p.PostTypeId = 1
    GROUP BY
      t.TagName
    HAVING
      COUNT(pl.PostId) > 50
  ),
  UserScoreDistribution AS (
    SELECT
      OwnerUserId,
      SUM(CASE WHEN Score > 0 THEN 1 ELSE 0 END) AS PositiveScoreCount,
      SUM(CASE WHEN Score < 0 THEN 1 ELSE 0 END) AS NegativeScoreCount,
      COUNT(*) AS TotalPostsForUser
    FROM
      Posts
    WHERE
      OwnerUserId IS NOT NULL
      AND OwnerUserId > 0
      AND PostTypeId IN (1, 2)
    GROUP BY
      OwnerUserId
  )
SELECT
  COALESCE(h.OwnerUserId, rap.OwnerUserId, upc.UserId) AS UserId,
  COALESCE(upc.UserCreationDate, h.LastPostDate, rap.CreationDate) AS UserCreationDate,
  COALESCE(upc.UserLastAccessDate, h.LastPostDate, rap.LastActivityDate) AS UserLastAccessDate,
  COALESCE(upc.CurrentReputation, 0) AS CurrentReputation,
  COALESCE(upc.ReputationChange, 0) AS ReputationChange,
  COALESCE(h.PostCount, 0) AS TotalPostCount,
  COALESCE(h.TotalScore, 0) AS TotalPostScore,
  COALESCE(h.AvgViewCount, 0) AS AveragePostViewCount,
  COALESCE(h.QuestionCount, 0) AS TotalQuestions,
  COALESCE(h.AnswerCount, 0) AS TotalAnswers,
  COALESCE(rap.Title, 'N/A') AS RecentPostTitle,
  COALESCE(rap.Score, 0) AS RecentPostScore,
  COALESCE(rap.ViewCount, 0) AS RecentPostViewCount,
  COALESCE(rap.ActivityLagDays, 0) AS RecentPostActivityLag,
  COALESCE(rap.IsClosed, 0) AS IsRecentPostClosed,
  COALESCE(phs.TitleEdits, 0) AS PostTitleEditCount,
  COALESCE(phs.BodyEdits, 0) AS PostBodyEditCount,
  COALESCE(phs.TagEdits, 0) AS PostTagEditCount,
  COALESCE(phs.UniqueEditors, 0) AS PostUniqueEditorCount,
  COALESCE(phs.LastCloseVoteDate, TIMESTAMP '1900-01-01') AS LastPostCloseVote,
  COALESCE(phs.LastReopenVoteDate, TIMESTAMP '1900-01-01') AS LastPostReopenVote,
  tu.TagName AS TopTagName,
  tu.LinkCount AS TopTagLinkCount,
  tu.AvgPostScoreForTag AS TopTagAvgPostScore,
  us.PositiveScoreCount AS UserPositiveScorePosts,
  us.NegativeScoreCount AS UserNegativeScorePosts,
  us.TotalPostsForUser AS UserTotalPostsForScoreDist,
  CASE WHEN h.OwnerUserId IS NULL THEN 'No' ELSE 'Yes' END AS IsHighEngagementUser,
  CASE WHEN upc.ReputationChange > 1000 THEN 'Significant Increase' WHEN upc.ReputationChange < -500 THEN 'Significant Decrease' ELSE 'Stable' END AS ReputationTrend
FROM
  UserReputationChange upc
FULL OUTER JOIN
  UserPostActivity h
  ON upc.UserId = h.OwnerUserId
FULL OUTER JOIN
  RecentActivityPosts rap
  ON COALESCE(h.OwnerUserId, upc.UserId) = rap.OwnerUserId
LEFT JOIN
  PostHistorySummaries phs
  ON rap.Id = phs.PostId
LEFT JOIN
  TagUsage tu
  ON tu.TagName = (
    SELECT
      TagName
    FROM
      TagUsage tu_inner
    WHERE
      tu_inner.AvgPostScoreForTag = (
        SELECT
          MAX(AvgPostScoreForTag)
        FROM
          TagUsage
      )
    LIMIT 1
  )
LEFT JOIN
  UserScoreDistribution us
  ON COALESCE(h.OwnerUserId, upc.UserId) = us.OwnerUserId
WHERE
  COALESCE(h.OwnerUserId, upc.UserId, rap.OwnerUserId) IS NOT NULL
GROUP BY
  COALESCE(h.OwnerUserId, rap.OwnerUserId, upc.UserId),
  COALESCE(upc.UserCreationDate, h.LastPostDate, rap.CreationDate),
  COALESCE(upc.UserLastAccessDate, h.LastPostDate, rap.LastActivityDate),
  COALESCE(upc.CurrentReputation, 0),
  COALESCE(upc.ReputationChange, 0),
  COALESCE(h.PostCount, 0),
  COALESCE(h.TotalScore, 0),
  COALESCE(h.AvgViewCount, 0),
  COALESCE(h.QuestionCount, 0),
  COALESCE(h.AnswerCount, 0),
  COALESCE(rap.Title, 'N/A'),
  COALESCE(rap.Score, 0),
  COALESCE(rap.ViewCount, 0),
  COALESCE(rap.ActivityLagDays, 0),
  COALESCE(rap.IsClosed, 0),
  COALESCE(phs.TitleEdits, 0),
  COALESCE(phs.BodyEdits, 0),
  COALESCE(phs.TagEdits, 0),
  COALESCE(phs.UniqueEditors, 0),
  COALESCE(phs.LastCloseVoteDate, TIMESTAMP '1900-01-01'),
  COALESCE(phs.LastReopenVoteDate, TIMESTAMP '1900-01-01'),
  tu.TagName,
  tu.LinkCount,
  tu.AvgPostScoreForTag,
  us.PositiveScoreCount,
  us.NegativeScoreCount,
  us.TotalPostsForUser,
  CASE WHEN h.OwnerUserId IS NULL THEN 'No' ELSE 'Yes' END,
  CASE WHEN upc.ReputationChange > 1000 THEN 'Significant Increase' WHEN upc.ReputationChange < -500 THEN 'Significant Decrease' ELSE 'Stable' END
ORDER BY
  COALESCE(upc.CurrentReputation, 0) DESC,
  COALESCE(h.TotalScore, 0) DESC
LIMIT 100;