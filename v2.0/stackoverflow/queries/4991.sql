-- {"query": "4991.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gemini-2.5-flash-lite", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2111, "output_tokens": 1042}
WITH RankedPostEdits AS (
  SELECT
    ph.PostId,
    ph.UserId,
    ph.CreationDate,
    pht.Name AS HistoryTypeName,
    ROW_NUMBER() OVER (PARTITION BY ph.PostId, ph.UserId ORDER BY ph.CreationDate DESC) AS rn
  FROM PostHistory ph
  JOIN PostHistoryTypes pht
    ON ph.PostHistoryTypeId = pht.Id
  WHERE
    ph.UserId IS NOT NULL AND ph.PostHistoryTypeId IN (4, 5, 6, 7, 8, 9)
), UserPostCounts AS (
  SELECT
    OwnerUserId,
    COUNT(Id) AS PostCount
  FROM Posts
  GROUP BY
    OwnerUserId
), UserVoteCounts AS (
  SELECT
    UserId,
    COUNT(Id) AS VoteCount
  FROM Votes
  WHERE
    VoteTypeId IN (2, 3)
  GROUP BY
    UserId
), RecentQuestions AS (
  SELECT
    Id,
    Title,
    OwnerUserId,
    CommunityOwnedDate,
    CAST('2024-10-01 12:34:56' AS TIMESTAMP) AS RefTimestamp,
    EXTRACT(EPOCH FROM (CAST('2024-10-01 12:34:56' AS TIMESTAMP) - CreationDate)) / 86400.0 AS DaysSinceCreation,
    CreationDate
  FROM Posts
  WHERE
    PostTypeId = 1
    AND CreationDate >= (CAST('2024-10-01 12:34:56' AS TIMESTAMP) - INTERVAL '1 year')
), TaggedQuestions AS (
  SELECT
    p.Id,
    p.Title,
    p.OwnerUserId,
    p.CommunityOwnedDate,
    p.Tags,
    EXTRACT(EPOCH FROM (CAST('2024-10-01 12:34:56' AS TIMESTAMP) - p.CreationDate)) / 86400.0 AS DaysSinceCreation,
    p.CreationDate
  FROM Posts p
  WHERE
    p.PostTypeId = 1 AND p.Tags LIKE '%<sql>%'
), HighReputationUsers AS (
  SELECT
    Id,
    DisplayName,
    Reputation
  FROM Users
  WHERE
    Reputation >= 10000
), MergedPostData AS (
  SELECT
    COALESCE(u.DisplayName, 'Deleted User') AS UserName,
    COALESCE(upc.PostCount, 0) AS TotalPosts,
    COALESCE(uvc.VoteCount, 0) AS TotalVotes,
    rpe.HistoryTypeName AS LatestEditType,
    rq.Title AS RecentQuestionTitle,
    tq.Title AS TaggedSqlQuestionTitle,
    CASE WHEN COALESCE(rq.CommunityOwnedDate, CAST('2024-10-01 12:34:56' AS TIMESTAMP)) < rq.CreationDate THEN 'Community Owned' ELSE 'User Owned' END AS QuestionOwnership,
    CASE WHEN COALESCE(tq.CommunityOwnedDate, CAST('2024-10-01 12:34:56' AS TIMESTAMP)) < tq.CreationDate THEN 'Community Owned' ELSE 'User Owned' END AS TaggedSqlQuestionOwnership
  FROM HighReputationUsers u
  LEFT JOIN UserPostCounts upc
    ON u.Id = upc.OwnerUserId
  LEFT JOIN UserVoteCounts uvc
    ON u.Id = uvc.UserId
  LEFT JOIN RankedPostEdits rpe
    ON u.Id = rpe.UserId AND rpe.rn = 1
  LEFT JOIN RecentQuestions rq
    ON u.Id = rq.OwnerUserId AND rq.DaysSinceCreation < 30
  LEFT JOIN TaggedQuestions tq
    ON u.Id = tq.OwnerUserId AND tq.DaysSinceCreation < 30
)
SELECT
  UserName,
  TotalPosts,
  TotalVotes,
  LatestEditType,
  RecentQuestionTitle,
  TaggedSqlQuestionTitle,
  QuestionOwnership,
  TaggedSqlQuestionOwnership,
  (
    TotalPosts * 1.5 + TotalVotes * 0.8 +
    CASE
      WHEN LatestEditType IN ('Edit Body', 'Edit Title') THEN 10
      WHEN LatestEditType IN ('Rollback Body', 'Rollback Title') THEN -5
      ELSE 0
    END +
    CASE WHEN RecentQuestionTitle IS NOT NULL THEN 20 ELSE 0 END +
    CASE WHEN TaggedSqlQuestionTitle IS NOT NULL THEN 30 ELSE 0 END +
    CASE WHEN QuestionOwnership = 'Community Owned' THEN 5 ELSE 0 END +
    CASE WHEN TaggedSqlQuestionOwnership = 'Community Owned' THEN 7 ELSE 0 END
  ) AS PerformanceScore
FROM MergedPostData
WHERE
  TotalPosts > 100 OR TotalVotes > 500 OR RecentQuestionTitle IS NOT NULL OR TaggedSqlQuestionTitle IS NOT NULL
ORDER BY
  PerformanceScore DESC,
  TotalPosts DESC;