-- {"query": "4597.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gemini-2.5-flash-lite", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2111, "output_tokens": 1786} 

WITH
  LatestPostEdits AS (
    SELECT
      ph.PostId,
      MAX(ph.CreationDate) AS LatestEditDate
    FROM
      PostHistory ph
    WHERE
      ph.PostHistoryTypeId IN (4, 5, 6) -- Edit Title, Edit Body, Edit Tags
    GROUP BY
      ph.PostId
  ),
  PostEditCounts AS (
    SELECT
      ph.PostId,
      COUNT(ph.Id) AS EditCount
    FROM
      PostHistory ph
    WHERE
      ph.PostHistoryTypeId IN (4, 5, 6)
    GROUP BY
      ph.PostId
  ),
  UserPostActivity AS (
    SELECT
      p.OwnerUserId,
      COUNT(DISTINCT p.Id) AS TotalPostsOwned,
      SUM(CASE WHEN p.PostTypeId = 1 THEN 1 ELSE 0 END) AS QuestionCount,
      SUM(CASE WHEN p.PostTypeId = 2 THEN 1 ELSE 0 END) AS AnswerCount,
      AVG(p.Score) AS AveragePostScore,
      MAX(p.LastActivityDate) AS LastPostActivityDate
    FROM
      Posts p
    WHERE
      p.OwnerUserId IS NOT NULL
      AND p.OwnerUserId <> -1
    GROUP BY
      p.OwnerUserId
  ),
  UserVoteSummary AS (
    SELECT
      v.UserId,
      SUM(CASE WHEN vt.Name = 'UpMod' THEN 1 ELSE 0 END) AS UpVotesGiven,
      SUM(CASE WHEN vt.Name = 'DownMod' THEN 1 ELSE 0 END) AS DownVotesGiven,
      COUNT(DISTINCT v.PostId) AS PostsVotedOn
    FROM
      Votes v
      JOIN VoteTypes vt ON v.VoteTypeId = vt.Id
    WHERE
      vt.Name IN ('UpMod', 'DownMod')
      AND v.UserId IS NOT NULL
    GROUP BY
      v.UserId
  ),
  HighlyRatedUsers AS (
    SELECT
      u.Id,
      u.DisplayName,
      u.Reputation,
      u.CreationDate,
      COALESCE(upa.QuestionCount, 0) AS QuestionsAsked,
      COALESCE(upa.AnswerCount, 0) AS AnswersGiven,
      COALESCE(uvs.UpVotesGiven, 0) AS UpVotesCast,
      COALESCE(uvs.DownVotesGiven, 0) AS DownVotesCast,
      ROW_NUMBER() OVER (ORDER BY u.Reputation DESC, u.CreationDate ASC) AS ReputationRank
    FROM
      Users u
      LEFT JOIN UserPostActivity upa ON u.Id = upa.OwnerUserId
      LEFT JOIN UserVoteSummary uvs ON u.Id = uvs.UserId
    WHERE
      u.Reputation > 1000
      AND u.CreationDate < '2023-01-01'
  )
SELECT
  'BenchmarkQuery' AS QueryDescription,
  u.DisplayName AS UserName,
  u.Reputation,
  u.CreationDate,
  COALESCE(upa.TotalPostsOwned, 0) AS TotalOwned,
  COALESCE(upa.AveragePostScore, 0.0) AS AvgScore,
  COALESCE(pec.EditCount, 0) AS NumberOfEdits,
  COALESCE(lp.LatestEditDate, u.CreationDate) AS LastEditOrCreation,
  CASE
    WHEN upa.LastPostActivityDate IS NULL THEN 'Never Active'
    WHEN upa.LastPostActivityDate < CURRENT_TIMESTAMP - INTERVAL '1 year' THEN 'Inactive'
    ELSE 'Active'
  END AS ActivityStatus,
  CASE
    WHEN hr.ReputationRank <= 100 THEN 'Top 100 User'
    WHEN hr.ReputationRank <= 1000 THEN 'Top 1000 User'
    ELSE 'Regular User'
  END AS UserTier,
  CONCAT(
    'User ID: ',
    u.Id,
    ' | Displayed As: ',
    u.DisplayName,
    ' | Posts Owned: ',
    COALESCE(upa.TotalPostsOwned, 0)
  ) AS UserSummaryString,
  UPPER(SUBSTRING(u.DisplayName FROM 1 FOR 1)) AS FirstInitialOfName,
  CASE
    WHEN u.WebsiteUrl IS NOT NULL AND u.WebsiteUrl LIKE '%stackoverflow.com%' THEN 'Stack Overflow Related Site'
    WHEN u.WebsiteUrl IS NOT NULL THEN 'External Site'
    ELSE 'No Website'
  END AS WebsiteType,
  (
    SELECT
      COUNT(*)
    FROM
      Badges b
    WHERE
      b.UserId = u.Id
      AND b.Class = 1 -- Gold Badge
  ) AS GoldBadgeCount,
  COALESCE(
    (
      SELECT
        COUNT(*)
      FROM
        Comments c
      WHERE
        c.UserId = u.Id
        AND c.CreationDate > u.LastAccessDate
    ),
    0
  ) AS CommentsAfterLastAccess,
  'N/A' AS PlaceholderColumn
FROM
  Users u
  LEFT JOIN UserPostActivity upa ON u.Id = upa.OwnerUserId
  LEFT JOIN LatestPostEdits lp ON u.Id = lp.PostId
  LEFT JOIN PostEditCounts pec ON u.Id = pec.PostId
  LEFT JOIN HighlyRatedUsers hr ON u.Id = hr.Id
WHERE
  u.Reputation BETWEEN 1000 AND 10000
  AND u.DisplayName IS NOT NULL
  AND u.DisplayName <> ''
  AND u.DownVotes > 0
  AND EXISTS (
    SELECT
      1
    FROM
      Posts p
    WHERE
      p.OwnerUserId = u.Id
      AND p.CreationDate BETWEEN '2022-01-01' AND '2023-01-01'
      AND p.AnswerCount > 5
  )
UNION ALL
SELECT
  'BenchmarkQuery' AS QueryDescription,
  NULL AS UserName,
  NULL AS Reputation,
  NULL AS CreationDate,
  COUNT(DISTINCT p.Id) AS TotalPostsOwned,
  AVG(p.Score) AS AveragePostScore,
  COUNT(ph.Id) AS NumberOfEdits,
  MIN(p.CreationDate) AS LastEditOrCreation,
  CASE
    WHEN MAX(p.LastActivityDate) IS NULL THEN 'Never Active'
    WHEN MAX(p.LastActivityDate) < CURRENT_TIMESTAMP - INTERVAL '1 year' THEN 'Inactive'
    ELSE 'Active'
  END AS ActivityStatus,
  'Aggregated Data' AS UserTier,
  CONCAT(
    'Total Posts: ',
    COUNT(DISTINCT p.Id),
    ' | Avg Score: ',
    CAST(AVG(p.Score) AS VARCHAR)
  ) AS UserSummaryString,
  NULL AS FirstInitialOfName,
  'Overall' AS WebsiteType,
  COUNT(b.Id) FILTER (WHERE b.Class = 1) AS GoldBadgeCount,
  NULL AS CommentsAfterLastAccess,
  'Aggregated Metrics' AS PlaceholderColumn
FROM
  Posts p
  LEFT JOIN PostHistory ph ON p.Id = ph.PostId AND ph.PostHistoryTypeId IN (4, 5, 6)
  LEFT JOIN Badges b ON p.OwnerUserId = b.UserId AND b.Class = 1
WHERE
  p.PostTypeId = 1 -- Questions only
  AND p.Score > 10
GROUP BY
  p.OwnerUserId
HAVING
  COUNT(DISTINCT p.Id) > 10
ORDER BY
  Reputation DESC,
  TotalPostsOwned DESC NULLS LAST;
