WITH
  RankedAnswers AS (
    SELECT
      p.Id AS PostId,
      p.ParentId AS QuestionId,
      p.OwnerUserId,
      p.CreationDate AS AnswerDate,
      p.Score AS AnswerScore,
      p.Id AS AnswerId,
      ROW_NUMBER() OVER (PARTITION BY p.ParentId ORDER BY p.Score DESC, p.CreationDate ASC) AS AnswerRank,
      LAG(p.Score, 1, -1) OVER (PARTITION BY p.ParentId ORDER BY p.Score DESC, p.CreationDate ASC) AS PreviousScore,
      LEAD(p.Score, 1, -1) OVER (PARTITION BY p.ParentId ORDER BY p.Score DESC, p.CreationDate ASC) AS NextScore,
      RANK() OVER (PARTITION BY p.ParentId ORDER BY p.CreationDate DESC) AS LatestAnswerRank
    FROM Posts p
    WHERE
      p.PostTypeId = 2
  ),
  QuestionsWithRanks AS (
    SELECT
      q.Id AS QuestionId,
      q.OwnerUserId AS QuestionOwnerUserId,
      q.CreationDate AS QuestionDate,
      q.Score AS QuestionScore,
      q.AnswerCount,
      q.FavoriteCount,
      q.ClosedDate,
      CASE
        WHEN q.ClosedDate IS NOT NULL THEN 'Closed'
        WHEN q.FavoriteCount > 100 THEN 'Highly Favorited'
        WHEN q.Score > 1000 THEN 'High Score'
        ELSE 'Regular'
      END AS QuestionCategory,
      ra.AnswerId,
      ra.AnswerScore,
      ra.AnswerRank,
      ra.LatestAnswerRank,
      u.DisplayName AS QuestionOwnerDisplayName,
      COALESCE(q.ViewCount, 0) AS ActualViewCount,
      (
        (COALESCE(q.Score, 0) * 5) + (COALESCE(q.FavoriteCount, 0) * 10) + (COALESCE(q.AnswerCount, 0) * 2) + (COALESCE(u.Reputation, 0) / 1000)
      ) AS QuestionQualityScore
    FROM Posts q
    JOIN RankedAnswers ra
      ON q.Id = ra.QuestionId
    LEFT JOIN Users u
      ON q.OwnerUserId = u.Id
    WHERE
      q.PostTypeId = 1
      AND ra.AnswerRank <= 3
  ),
  UserActivity AS (
    SELECT
      UserId,
      COUNT(Id) AS TotalVotes,
      SUM(CASE WHEN VoteTypeId = 2 THEN 1 ELSE 0 END) AS UpVotes,
      SUM(CASE WHEN VoteTypeId = 3 THEN 1 ELSE 0 END) AS DownVotes,
      SUM(CASE WHEN VoteTypeId = 5 THEN 1 ELSE 0 END) AS FavoriteVotes
    FROM Votes
    WHERE
      UserId IS NOT NULL
    GROUP BY
      UserId
  ),
  PostHistorySummary AS (
    SELECT
      PostId,
      MAX(CASE WHEN PostHistoryTypeId = 5 THEN CreationDate ELSE NULL END) AS LastBodyEditDate,
      MAX(CASE WHEN PostHistoryTypeId = 6 THEN CreationDate ELSE NULL END) AS LastTagEditDate,
      COUNT(DISTINCT CASE WHEN PostHistoryTypeId = 10 THEN UserId ELSE NULL END) AS CloseVoteCount
    FROM PostHistory
    GROUP BY
      PostId
  )
SELECT
  q.QuestionId,
  q.QuestionDate,
  q.QuestionScore,
  q.AnswerCount,
  q.FavoriteCount,
  q.QuestionCategory,
  q.QuestionOwnerDisplayName,
  q.QuestionQualityScore,
  q.AnswerId AS TopAnswerId,
  q.AnswerScore AS TopAnswerScore,
  q.AnswerRank AS TopAnswerRank,
  q.LatestAnswerRank AS LatestAnswerRank,
  ua.TotalVotes AS QuestionOwnerTotalVotes,
  ua.UpVotes AS QuestionOwnerUpVotes,
  ua.DownVotes AS QuestionOwnerDownVotes,
  phs.LastBodyEditDate,
  phs.LastTagEditDate,
  phs.CloseVoteCount,
  CASE
    WHEN q.QuestionDate IS NOT NULL AND phs.LastBodyEditDate IS NOT NULL THEN
      (EXTRACT(EPOCH FROM phs.LastBodyEditDate) - EXTRACT(EPOCH FROM q.QuestionDate)) / 60.0
    ELSE NULL
  END AS QuestionResponseTimeMinutes,
  CASE
    WHEN EXISTS (
      SELECT 1
      FROM PostLinks pl
      WHERE
        pl.RelatedPostId = q.QuestionId AND pl.LinkTypeId = 3
    ) THEN 'Linked as Duplicate'
    ELSE 'Not Linked as Duplicate'
  END AS DuplicateStatus,
  CASE
    WHEN q.QuestionScore > 500 AND p.Tags IS NOT NULL THEN REPLACE(REPLACE(SUBSTRING(p.Tags FROM 2 FOR CHAR_LENGTH(p.Tags) - 2), '><', ' | '), '<', '')
    ELSE NULL
  END AS FormattedTags
FROM QuestionsWithRanks q
LEFT JOIN UserActivity ua
  ON q.QuestionOwnerUserId = ua.UserId
LEFT JOIN PostHistorySummary phs
  ON q.QuestionId = phs.PostId
LEFT JOIN Posts p
  ON q.QuestionId = p.Id
WHERE
  q.QuestionOwnerUserId IS NOT NULL
  AND q.AnswerScore >= 0
  AND (ua.TotalVotes IS NULL OR ua.TotalVotes > 10)
  AND q.QuestionQualityScore > (
    SELECT
      AVG(
        (
          (COALESCE(p2.Score, 0) * 5) + (COALESCE(p2.FavoriteCount, 0) * 10) + (COALESCE(p2.AnswerCount, 0) * 2) + (COALESCE(u2.Reputation, 0) / 1000)
        )
      )
    FROM Posts p2
    LEFT JOIN Users u2
      ON p2.OwnerUserId = u2.Id
    WHERE
      p2.PostTypeId = 1
  )
ORDER BY
  q.QuestionQualityScore DESC,
  q.QuestionDate ASC
LIMIT 100;