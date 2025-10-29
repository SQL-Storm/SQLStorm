-- {"query": "4252.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gemini-2.5-flash-lite", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2111, "output_tokens": 1286} 

WITH
  RankedPostEdits AS (
    SELECT
      ph.PostId,
      ph.UserId,
      ph.CreationDate AS EditDate,
      ROW_NUMBER() OVER (PARTITION BY ph.PostId, ph.UserId ORDER BY ph.CreationDate DESC) AS rn
    FROM PostHistory AS ph
    WHERE
      ph.PostHistoryTypeId IN (4, 5, 6) -- Edit Title, Edit Body, Edit Tags
  ),
  UserActivity AS (
    SELECT
      p.OwnerUserId,
      COUNT(DISTINCT p.Id) AS QuestionCount,
      SUM(CASE WHEN p.PostTypeId = 2 THEN 1 ELSE 0 END) AS AnswerCount,
      COUNT(DISTINCT c.Id) AS CommentCount,
      SUM(CASE WHEN p.PostTypeId = 1 AND p.AcceptedAnswerId IS NOT NULL THEN 1 ELSE 0 END) AS AcceptedAnswerCount,
      MAX(p.CreationDate) AS LastPostDate
    FROM Posts AS p
    LEFT JOIN Comments AS c
      ON p.Id = c.PostId
    WHERE
      p.OwnerUserId IS NOT NULL
      AND p.OwnerUserId <> -1
    GROUP BY
      p.OwnerUserId
  ),
  UserEditStats AS (
    SELECT
      rpe.UserId,
      COUNT(DISTINCT rpe.PostId) AS EditedPostCount,
      AVG(DATEDIFF(day, p.CreationDate, rpe.EditDate)) AS AvgDaysToFirstEdit
    FROM RankedPostEdits AS rpe
    JOIN Posts AS p
      ON rpe.PostId = p.Id
    WHERE
      rpe.rn = 1
    GROUP BY
      rpe.UserId
  ),
  UserReputationChange AS (
    SELECT
      u.Id AS UserId,
      u.Reputation,
      LAG(u.Reputation, 1, u.Reputation) OVER (ORDER BY u.CreationDate) AS PreviousReputation,
      u.UpVotes AS TotalUpVotes,
      u.DownVotes AS TotalDownVotes
    FROM Users AS u
  )
SELECT
  u.Id AS UserId,
  u.DisplayName,
  COALESCE(ua.QuestionCount, 0) AS TotalQuestions,
  COALESCE(ua.AnswerCount, 0) AS TotalAnswers,
  COALESCE(ua.CommentCount, 0) AS TotalComments,
  COALESCE(ua.AcceptedAnswerCount, 0) AS AcceptedAnswers,
  ues.EditedPostCount AS PostsEdited,
  (
    ues.EditedPostCount * 100.0 / NULLIF(ua.QuestionCount + ua.AnswerCount, 0)
  ) AS EditPercentage,
  CASE
    WHEN urc.Reputation > urc.PreviousReputation THEN 'Increased'
    WHEN urc.Reputation < urc.PreviousReputation THEN 'Decreased'
    ELSE 'Stable'
  END AS ReputationTrend,
  urc.TotalUpVotes,
  urc.TotalDownVotes,
  CASE
    WHEN u.WebsiteUrl IS NULL THEN 'No Website'
    WHEN u.WebsiteUrl LIKE '%stackoverflow.com%' THEN 'Stack Overflow Related'
    ELSE 'External Website'
  END AS WebsiteCategory,
  CASE
    WHEN u.Location IS NULL OR u.Location = '' THEN 'Unknown'
    WHEN u.Location LIKE '%USA%' OR u.Location LIKE '%United States%' THEN 'USA'
    ELSE 'Other'
  END AS LocationCategory,
  DATEDIFF(day, u.CreationDate, GETDATE()) AS AccountAgeDays,
  ua.LastPostDate,
  CASE
    WHEN EXISTS (
      SELECT
        1
      FROM Badges AS b
      WHERE
        b.UserId = u.Id AND b.Name LIKE '%Tagger%'
    ) THEN 'Yes'
    ELSE 'No'
  END AS HasTaggerBadge,
  DATEDIFF(day, u.LastAccessDate, GETDATE()) AS DaysSinceLastAccess,
  COUNT(DISTINCT p.Id) AS PostsWithAtLeastOneComment,
  SUM(p.FavoriteCount) AS TotalFavoriteCount,
  CASE
    WHEN EXISTS (
      SELECT
        1
      FROM PostLinks AS pl
      WHERE
        pl.PostId = p.Id AND pl.LinkTypeId = 3
    ) THEN 'Has Duplicate Link'
    ELSE 'No Duplicate Link'
  END AS DuplicateLinkStatus
FROM Users AS u
LEFT JOIN UserActivity AS ua
  ON u.Id = ua.OwnerUserId
LEFT JOIN UserEditStats AS ues
  ON u.Id = ues.UserId
LEFT JOIN UserReputationChange AS urc
  ON u.Id = urc.UserId
LEFT JOIN Posts AS p
  ON u.Id = p.OwnerUserId
GROUP BY
  u.Id,
  u.DisplayName,
  ua.QuestionCount,
  ua.AnswerCount,
  ua.CommentCount,
  ua.AcceptedAnswerCount,
  ues.EditedPostCount,
  urc.Reputation,
  urc.PreviousReputation,
  urc.TotalUpVotes,
  urc.TotalDownVotes,
  u.WebsiteUrl,
  u.Location,
  u.CreationDate,
  u.LastAccessDate
HAVING
  (
    COALESCE(ua.QuestionCount, 0) + COALESCE(ua.AnswerCount, 0) + COALESCE(ua.CommentCount, 0)
  ) > 10
ORDER BY
  AccountAgeDays DESC,
  TotalFavoriteCount DESC;
