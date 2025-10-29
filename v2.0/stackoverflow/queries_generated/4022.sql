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
      Posts AS p
      LEFT JOIN Comments AS c ON p.Id = c.PostId
      LEFT JOIN Votes AS v ON p.Id = v.PostId
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
      DATEDIFF(day, u.CreationDate, GETDATE()) AS AccountAgeDays,
      DATEDIFF(day, u.LastAccessDate, GETDATE()) AS DaysSinceLastAccess,
      COALESCE(CONCAT(u.Location, ' | ', u.WebsiteUrl), u.Location, u.WebsiteUrl, 'Unknown') AS LocationAndWebsite,
      ROW_NUMBER() OVER (ORDER BY u.Reputation DESC) AS ReputationRank,
      AVG(u.Reputation) OVER () AS AvgGlobalReputation
    FROM
      Users AS u
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
      DATEDIFF(day, p.CreationDate, p.LastActivityDate) AS PostAgeDays,
      CASE WHEN p.ClosedDate IS NOT NULL THEN 1 ELSE 0 END AS IsClosed,
      CASE WHEN p.CommunityOwnedDate IS NOT NULL THEN 1 ELSE 0 END AS IsCommunityOwned,
      JSON_VALUE(
        (
          SELECT
            Text
          FROM
            PostHistory
          WHERE
            PostId = p.Id AND PostHistoryTypeId = 10
          ORDER BY
            CreationDate DESC
          FETCH FIRST 1 ROWS ONLY
        ),
        '$[0].CloseReasonTypeId'
      ) AS CloseReasonTypeId,
      ROW_NUMBER() OVER (PARTITION BY p.OwnerUserId ORDER BY p.Score DESC) AS PostScoreRankForUser,
      LAG(p.Score, 1, 0) OVER (PARTITION BY p.OwnerUserId ORDER BY p.Score DESC) AS PreviousPostScoreForUser,
      LEAD(p.Score, 1, 0) OVER (PARTITION BY p.OwnerUserId ORDER BY p.Score DESC) AS NextPostScoreForUser
    FROM
      Posts AS p
    WHERE
      p.PostTypeId IN (1, 2) -- Questions and Answers
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
      PostLinks AS pl
    WHERE
      pl.PostId = pm.PostId OR pl.RelatedPostId = pm.PostId
  ) AS LinkCount,
  (
    SELECT
      COUNT(*)
    FROM
      Comments AS c
    WHERE
      c.PostId = pm.PostId
      AND c.UserId <> pm.OwnerUserId
      AND c.UserId IS NOT NULL
  ) AS CommentsByOthers,
  (
    SELECT
      SUM(v.BountyAmount)
    FROM
      Votes AS v
    WHERE
      v.PostId = pm.PostId AND v.VoteTypeId = 8
  ) AS TotalBountyAmount,
  CASE
    WHEN pm.PostScoreRankForUser = 1 THEN 'HighestScoring'
    WHEN pm.PostScoreRankForUser BETWEEN 2 AND 5 THEN 'Top5Scoring'
    ELSE 'OtherScoring'
  END AS UserPostRankTier
FROM
  UserReputationAndActivity AS ura
  INNER JOIN UserPostEngagement AS upe ON ura.UserId = upe.OwnerUserId
  INNER JOIN PostMetrics AS pm ON ura.UserId = pm.OwnerUserId
WHERE
  ura.Reputation > 1000
  AND pm.PostAgeDays > 30
  AND upe.PostCount > 10
  AND pm.Score > 0
  AND ura.DaysSinceLastAccess < 365
ORDER BY
  ura.Reputation DESC,
  pm.PostScore DESC;
