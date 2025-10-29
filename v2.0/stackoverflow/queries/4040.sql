-- {"query": "4040.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gemini-2.5-flash-lite", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2111, "output_tokens": 1424} 
WITH
  RankedQuestions AS (
    SELECT
      p.Id AS PostId,
      p.OwnerUserId,
      p.Title,
      p.CreationDate,
      p.Score,
      p.AnswerCount,
      p.FavoriteCount,
      ROW_NUMBER() OVER (
        PARTITION BY
          p.OwnerUserId
        ORDER BY
          p.CreationDate DESC
      ) AS rn
    FROM Posts AS p
    WHERE
      p.PostTypeId = 1
      AND p.OwnerUserId IS NOT NULL
      AND p.CreationDate > '2023-01-01'
  ),
  UserQuestionStats AS (
    SELECT
      r.OwnerUserId,
      COUNT(r.PostId) AS TotalQuestions,
      AVG(r.Score) AS AvgQuestionScore,
      SUM(r.FavoriteCount) AS TotalFavorites,
      MAX(r.PostId) AS LatestQuestionId
    FROM RankedQuestions AS r
    WHERE
      r.rn <= 10
    GROUP BY
      r.OwnerUserId
  ),
  UserAnswers AS (
    SELECT
      p.OwnerUserId,
      COUNT(p.Id) AS TotalAnswers,
      AVG(p.Score) AS AvgAnswerScore
    FROM Posts AS p
    WHERE
      p.PostTypeId = 2
      AND p.OwnerUserId IS NOT NULL
      AND p.CreationDate > '2023-01-01'
    GROUP BY
      p.OwnerUserId
  ),
  UserComments AS (
    SELECT
      c.UserId,
      COUNT(c.Id) AS TotalComments,
      AVG(c.Score) AS AvgCommentScore
    FROM Comments AS c
    WHERE
      c.UserId IS NOT NULL
      AND c.CreationDate > '2023-01-01'
    GROUP BY
      c.UserId
  ),
  UserVotes AS (
    SELECT
      v.UserId,
      COUNT(CASE WHEN v.VoteTypeId = 2 THEN 1 ELSE NULL END) AS UpVotes,
      COUNT(CASE WHEN v.VoteTypeId = 3 THEN 1 ELSE NULL END) AS DownVotes,
      COUNT(CASE WHEN v.VoteTypeId = 8 THEN 1 ELSE NULL END) AS BountyStartVotes
    FROM Votes AS v
    WHERE
      v.UserId IS NOT NULL
      AND v.CreationDate > '2023-01-01'
    GROUP BY
      v.UserId
  ),
  UserPostHistory AS (
    SELECT
      ph.UserId,
      COUNT(CASE WHEN ph.PostHistoryTypeId IN (1, 2, 3) THEN 1 ELSE NULL END) AS InitialEdits,
      COUNT(CASE WHEN ph.PostHistoryTypeId IN (4, 5, 6) THEN 1 ELSE NULL END) AS Edits,
      COUNT(CASE WHEN ph.PostHistoryTypeId IN (10, 11, 12, 13, 14, 15, 19, 20, 35, 36) THEN 1 ELSE NULL END) AS ModerationActions
    FROM PostHistory AS ph
    WHERE
      ph.UserId IS NOT NULL
      AND ph.CreationDate > '2023-01-01'
    GROUP BY
      ph.UserId
  )
SELECT
  u.DisplayName,
  u.Reputation,
  u.CreationDate AS UserCreationDate,
  COALESCE(uqs.TotalQuestions, 0) AS TotalQuestions,
  COALESCE(uqs.AvgQuestionScore, 0.0) AS AvgQuestionScore,
  COALESCE(ua.TotalAnswers, 0) AS TotalAnswers,
  COALESCE(ua.AvgAnswerScore, 0.0) AS AvgAnswerScore,
  COALESCE(uc.TotalComments, 0) AS TotalComments,
  COALESCE(uc.AvgCommentScore, 0.0) AS AvgCommentScore,
  COALESCE(uv.UpVotes, 0) AS UpVotes,
  COALESCE(uv.DownVotes, 0) AS DownVotes,
  COALESCE(uvh.InitialEdits, 0) AS InitialEdits,
  COALESCE(uvh.Edits, 0) AS Edits,
  COALESCE(uvh.ModerationActions, 0) AS ModerationActions,
  CASE
    WHEN u.LastAccessDate < cast('2024-10-01 12:34:56' as timestamp) - INTERVAL '1 year' THEN 'Inactive'
    WHEN u.Views > 100000 THEN 'Power User'
    WHEN u.UpVotes > u.DownVotes * 5 THEN 'Helpful Contributor'
    ELSE 'Standard User'
  END AS UserStatus,
  LENGTH(u.AboutMe) AS AboutMeLength,
  SUBSTRING(u.WebsiteUrl FROM '://(?:www\.)?([^/]+)') AS WebsiteDomain,
  CONCAT(
    COALESCE(uqs.TotalQuestions, 0),
    '-',
    COALESCE(ua.TotalAnswers, 0),
    '-',
    COALESCE(uc.TotalComments, 0)
  ) AS ContentContributionSummary,
  CASE
    WHEN RANK() OVER (ORDER BY u.Reputation DESC) <= 100 THEN 'Top 100 Reputation'
    WHEN RANK() OVER (ORDER BY u.CreationDate ASC) <= 50 THEN 'Early Adopter'
    ELSE 'Regular User'
  END AS UserTier
FROM Users AS u
LEFT OUTER JOIN UserQuestionStats AS uqs
  ON u.Id = uqs.OwnerUserId
LEFT OUTER JOIN UserAnswers AS ua
  ON u.Id = ua.OwnerUserId
LEFT OUTER JOIN UserComments AS uc
  ON u.Id = uc.UserId
LEFT OUTER JOIN UserVotes AS uv
  ON u.Id = uv.UserId
LEFT OUTER JOIN UserPostHistory AS uvh
  ON u.Id = uvh.UserId
WHERE
  u.DisplayName IS NOT NULL
  AND u.DisplayName <> ''
  AND u.Id > 0
ORDER BY
  u.Reputation DESC,
  u.CreationDate ASC
LIMIT 1000;