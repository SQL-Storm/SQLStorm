-- {"query": "4022.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gemini-2.5-flash-lite", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2111, "output_tokens": 1447}
WITH
  UserPostEngagement AS (
    SELECT
      p.OwnerUserId,
      COUNT(DISTINCT p.Id) AS PostCount,
      SUM(CASE WHEN p.PostTypeId = 1 THEN 1 ELSE 0 END) AS QuestionCount,
      SUM(CASE WHEN p.PostTypeId = 2 THEN 1 ELSE 0 END) AS AnswerCount,
      SUM(CASE WHEN c.Id IS NOT NULL THEN 1 ELSE 0 END) AS CommentCount,
      SUM(CASE WHEN v.VoteTypeId = 2 THEN 1 ELSE 0 END) AS UpVoteCount,
      SUM(CASE WHEN v.VoteTypeId = 3 THEN 1 ELSE 0 END) AS DownVoteCount
    FROM
      Posts p
      LEFT JOIN Comments c ON p.Id = c.PostId
      LEFT JOIN Votes v ON p.Id = v.PostId
    WHERE
      p.OwnerUserId IS NOT NULL
      AND p.OwnerUserId <> -1
    GROUP BY
      p.OwnerUserId
  ),
  UserReputationAndActivity AS (
    SELECT
      u.Id AS UserId,
      u.Reputation,
      u.CreationDate,
      u.LastAccessDate,
      u.DisplayName,
      u.Views,
      u.UpVotes AS UserUpVotes,
      u.DownVotes AS UserDownVotes,
      CAST('2024-10-01 12:34:56' AS timestamp) AS ReferenceTimestamp,
      (CAST('2024-10-01 12:34:56' AS timestamp) - u.CreationDate) AS AccountAgeInterval,
      EXTRACT(day FROM (CAST('2024-10-01 12:34:56' AS timestamp) - u.CreationDate)) +
        (EXTRACT(epoch FROM (CAST('2024-10-01 12:34:56' AS timestamp) - u.CreationDate)) -
         EXTRACT(day FROM (CAST('2024-10-01 12:34:56' AS timestamp) - u.CreationDate)) * 86400) / 86400 AS AccountAgeDays,
      EXTRACT(day FROM (CAST('2024-10-01 12:34:56' AS timestamp) - u.LastAccessDate)) +
        (EXTRACT(epoch FROM (CAST('2024-10-01 12:34:56' AS timestamp) - u.LastAccessDate)) -
         EXTRACT(day FROM (CAST('2024-10-01 12:34:56' AS timestamp) - u.LastAccessDate)) * 86400) / 86400 AS DaysSinceLastAccess,
      COALESCE(NULLIF(CONCAT(u.Location, ' | ', u.WebsiteUrl), ''), NULLIF(u.Location, ''), NULLIF(u.WebsiteUrl, ''), 'Unknown') AS LocationAndWebsite,
      ROW_NUMBER() OVER (ORDER BY u.Reputation DESC) AS ReputationRank,
      AVG(u.Reputation) OVER () AS AvgGlobalReputation
    FROM
      Users u
  ),
  PostMetrics AS (
    SELECT
      p.Id AS PostId,
      p.OwnerUserId,
      p.Title,
      p.Score,
      p.ViewCount,
      p.AnswerCount,
      p.CommentCount,
      p.FavoriteCount,
      p.CreationDate AS PostCreationDate,
      p.LastActivityDate AS PostLastActivityDate,
      EXTRACT(day FROM (p.LastActivityDate - p.CreationDate)) +
        (EXTRACT(epoch FROM (p.LastActivityDate - p.CreationDate)) -
         EXTRACT(day FROM (p.LastActivityDate - p.CreationDate)) * 86400) / 86400 AS PostAgeDays,
      CASE WHEN p.ClosedDate IS NOT NULL THEN 1 ELSE 0 END AS IsClosed,
      CASE WHEN p.CommunityOwnedDate IS NOT NULL THEN 1 ELSE 0 END AS IsCommunityOwned,
      (
        SELECT
          COALESCE(
            NULLIF(
              -- try JSON_EXTRACT/JSON_QUERY functions if they exist in the dialect; treat ph.Text as text
              NULLIF(
                (CASE
                   WHEN POSITION('"CloseReasonTypeId"' IN ph.Text) > 0 THEN
                     -- extract numeric value after "CloseReasonTypeId": using regexp_replace where available
                     REGEXP_REPLACE(ph.Text, '.*"CloseReasonTypeId"\s*:\s*([0-9]+).*', '\1')
                   ELSE NULL
                 END),
                ''
              ),
              ''
            ),
            NULLIF(
              (CASE
                 WHEN POSITION('"CloseReasonTypeId"' IN ph.Text) > 0 THEN
                   REGEXP_REPLACE(ph.Text, '.*"CloseReasonTypeId"\s*:\s*([0-9]+).*', '\1')
                 ELSE NULL
               END),
              ''
            )
          )
        FROM
          PostHistory ph
        WHERE
          ph.PostId = p.Id AND ph.PostHistoryTypeId = 10
        ORDER BY
          ph.CreationDate DESC
        LIMIT 1
      ) AS CloseReasonTypeId,
      ROW_NUMBER() OVER (PARTITION BY p.OwnerUserId ORDER BY p.Score DESC) AS PostScoreRankForUser,
      LAG(p.Score, 1, 0) OVER (PARTITION BY p.OwnerUserId ORDER BY p.Score DESC) AS PreviousPostScoreForUser,
      LEAD(p.Score, 1, 0) OVER (PARTITION BY p.OwnerUserId ORDER BY p.Score DESC) AS NextPostScoreForUser
    FROM
      Posts p
    WHERE
      p.PostTypeId IN (1, 2)
  )
SELECT
  ura.DisplayName,
  ura.Reputation,
  ura.AccountAgeDays,
  ura.DaysSinceLastAccess,
  ura.LocationAndWebsite,
  upe.PostCount,
  upe.QuestionCount,
  upe.AnswerCount,
  upe.CommentCount,
  upe.UpVoteCount,
  upe.DownVoteCount,
  pm.PostId,
  pm.Title,
  pm.Score AS PostScore,
  pm.ViewCount AS PostViewCount,
  pm.AnswerCount AS PostAnswerCount,
  pm.PostAgeDays,
  pm.IsClosed,
  pm.IsCommunityOwned,
  pm.CloseReasonTypeId,
  pm.PostScoreRankForUser,
  pm.PreviousPostScoreForUser,
  pm.NextPostScoreForUser,
  CASE
    WHEN pm.Score > pm.PreviousPostScoreForUser
      AND pm.Score > pm.NextPostScoreForUser THEN 'TopScoringPost'
    WHEN pm.Score < pm.PreviousPostScoreForUser
      AND pm.Score < pm.NextPostScoreForUser THEN 'LowScoringPost'
    ELSE 'MidScoringPost'
  END AS ScoreCategory,
  (
    SELECT
      COUNT(*)
    FROM
      PostLinks pl
    WHERE
      pl.PostId = pm.PostId OR pl.RelatedPostId = pm.PostId
  ) AS LinkCount,
  (
    SELECT
      COUNT(*)
    FROM
      Comments c
    WHERE
      c.PostId = pm.PostId
      AND c.UserId <> pm.OwnerUserId
      AND c.UserId IS NOT NULL
  ) AS CommentsByOthers,
  (
    SELECT
      SUM(v.BountyAmount)
    FROM
      Votes v
    WHERE
      v.PostId = pm.PostId AND v.VoteTypeId = 8
  ) AS TotalBountyAmount,
  CASE
    WHEN pm.PostScoreRankForUser = 1 THEN 'HighestScoring'
    WHEN pm.PostScoreRankForUser BETWEEN 2 AND 5 THEN 'Top5Scoring'
    ELSE 'OtherScoring'
  END AS UserPostRankTier
FROM
  UserReputationAndActivity ura
  INNER JOIN UserPostEngagement upe ON ura.UserId = upe.OwnerUserId
  INNER JOIN PostMetrics pm ON ura.UserId = pm.OwnerUserId
WHERE
  ura.Reputation > 1000
  AND pm.PostAgeDays > 30
  AND upe.PostCount > 10
  AND pm.Score > 0
  AND ura.DaysSinceLastAccess < 365
ORDER BY
  ura.Reputation DESC,
  pm.Score DESC;