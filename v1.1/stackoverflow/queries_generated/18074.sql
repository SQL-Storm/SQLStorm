-- {"query": "18074.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gemini-2.5-flash-lite", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2111, "output_tokens": 1640} 

WITH
  RankedPostEdits AS (
    SELECT
      ph.PostId,
      ph.UserId,
      ph.PostHistoryTypeId,
      ph.CreationDate,
      ROW_NUMBER() OVER (PARTITION BY ph.PostId, ph.UserId ORDER BY ph.CreationDate DESC) as rn
    FROM PostHistory AS ph
    WHERE ph.PostHistoryTypeId IN (4, 5, 6) AND ph.UserId IS NOT NULL
  ),
  UserActivity AS (
    SELECT
      u.Id AS UserId,
      u.DisplayName,
      u.Reputation,
      COUNT(DISTINCT CASE WHEN p.PostTypeId = 1 THEN p.Id ELSE NULL END) AS QuestionCount,
      COUNT(DISTINCT CASE WHEN p.PostTypeId = 2 THEN p.Id ELSE NULL END) AS AnswerCount,
      SUM(CASE WHEN p.PostTypeId = 2 THEN p.Score ELSE 0 END) AS TotalAnswerScore,
      AVG(CASE WHEN p.PostTypeId = 1 THEN p.AnswerCount ELSE NULL END) AS AvgAnswerCountForQuestions,
      MAX(p.CreationDate) AS LastPostDate,
      COUNT(DISTINCT c.Id) AS CommentCount,
      SUM(CASE WHEN v.VoteTypeId = 2 THEN 1 ELSE 0 END) AS UpVoteCount,
      SUM(CASE WHEN v.VoteTypeId = 3 THEN 1 ELSE 0 END) AS DownVoteCount,
      COUNT(DISTINCT b.Id) AS BadgeCount,
      SUM(CASE WHEN rpe.rn = 1 THEN 1 ELSE 0 END) AS RecentEdits,
      DATEDIFF(day, u.CreationDate, GETDATE()) AS AccountAgeDays,
      CASE
        WHEN u.WebsiteUrl IS NOT NULL AND u.WebsiteUrl <> '' THEN 1
        ELSE 0
      END AS HasWebsite,
      CASE
        WHEN u.AboutMe IS NOT NULL AND u.AboutMe <> '' THEN 1
        ELSE 0
      END AS HasAboutMe
    FROM Users AS u
    LEFT JOIN Posts AS p
      ON u.Id = p.OwnerUserId
    LEFT JOIN Comments AS c
      ON u.Id = c.UserId
    LEFT JOIN Votes AS v
      ON u.Id = v.UserId
    LEFT JOIN Badges AS b
      ON u.Id = b.UserId
    LEFT JOIN RankedPostEdits AS rpe
      ON u.Id = rpe.UserId
    WHERE
      u.Id > 0
    GROUP BY
      u.Id,
      u.DisplayName,
      u.Reputation,
      u.CreationDate,
      u.WebsiteUrl,
      u.AboutMe
  )
SELECT
  ua.UserId,
  ua.DisplayName,
  ua.Reputation,
  ua.QuestionCount,
  ua.AnswerCount,
  ua.TotalAnswerScore,
  ua.AvgAnswerCountForQuestions,
  ua.LastPostDate,
  ua.CommentCount,
  ua.UpVoteCount,
  ua.DownVoteCount,
  ua.BadgeCount,
  ua.RecentEdits,
  ua.AccountAgeDays,
  ua.HasWebsite,
  ua.HasAboutMe,
  (ua.UpVoteCount - ua.DownVoteCount) AS NetVotes,
  CASE
    WHEN ua.AnswerCount > 0 THEN CAST(CAST(ua.TotalAnswerScore AS REAL) / ua.AnswerCount AS DECIMAL(10, 2))
    ELSE 0.00
  END AS AvgAnswerScore,
  COALESCE(ua.LastPostDate, '1900-01-01') AS LastActivityDateCoalesced,
  CASE
    WHEN ua.Reputation > 10000 THEN 'High Rep'
    WHEN ua.Reputation > 1000 THEN 'Medium Rep'
    ELSE 'Low Rep'
  END AS ReputationTier,
  DENSE_RANK() OVER (ORDER BY ua.Reputation DESC) AS ReputationRank,
  LAG(ua.Reputation, 1, 0) OVER (ORDER BY ua.Reputation DESC) AS PreviousReputation,
  LEAD(ua.Reputation, 1, 0) OVER (ORDER BY ua.Reputation DESC) AS NextReputation,
  SUM(ua.BadgeCount) OVER (ORDER BY ua.Reputation DESC ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW) AS CumulativeBadgeCount,
  CASE
    WHEN EXISTS (SELECT 1 FROM Badges WHERE UserId = ua.UserId AND Name LIKE '%Expert%') THEN 'Has Expert Badge'
    ELSE 'No Expert Badge'
  END AS ExpertBadgeStatus,
  -- Simulating a complex string calculation and NULL logic
  CASE
    WHEN ua.DisplayName IS NULL OR ua.DisplayName = '' THEN 'Anonymous User'
    ELSE UPPER(LEFT(ua.DisplayName, 1)) + LOWER(SUBSTRING(ua.DisplayName, 2, LEN(ua.DisplayName)))
  END AS FormattedDisplayName,
  -- Joining with PostTypes to get name, but handling potential missing PostTypes
  pt.Name AS PostTypeNameForSample, -- Selecting one arbitrary post type name for demonstration
  -- Union to combine with users who haven't posted anything (or have no activity recorded in the above joins)
  -- In a real scenario, this might be more targeted, e.g., finding users with no badges
  (SELECT TOP 1 u_dummy.DisplayName FROM Users AS u_dummy WHERE u_dummy.Id NOT IN (SELECT UserId FROM UserActivity) ORDER BY u_dummy.Id) AS ExampleNewUser
FROM UserActivity AS ua
LEFT JOIN Posts AS p_sample
  ON ua.UserId = p_sample.OwnerUserId AND p_sample.PostTypeId = 1 -- Arbitrary join to PostTypes via Posts for demonstration
LEFT JOIN PostTypes AS pt
  ON p_sample.PostTypeId = pt.Id
WHERE
  ua.Reputation > 10 AND ua.AccountAgeDays > 30
UNION
SELECT
  NULL AS UserId,
  'NoActivityUser' AS DisplayName,
  0 AS Reputation,
  0 AS QuestionCount,
  0 AS AnswerCount,
  0 AS TotalAnswerScore,
  0.0 AS AvgAnswerCountForQuestions,
  NULL AS LastPostDate,
  0 AS CommentCount,
  0 AS UpVoteCount,
  0 AS DownVoteCount,
  0 AS BadgeCount,
  0 AS RecentEdits,
  0 AS AccountAgeDays,
  0 AS HasWebsite,
  0 AS HasAboutMe,
  0 AS NetVotes,
  0.00 AS AvgAnswerScore,
  CAST('1900-01-01' AS DATE) AS LastActivityDateCoalesced,
  'Low Rep' AS ReputationTier,
  0 AS ReputationRank,
  0 AS PreviousReputation,
  0 AS NextReputation,
  0 AS CumulativeBadgeCount,
  'No Expert Badge' AS ExpertBadgeStatus,
  'NO DISPLAY NAME' AS FormattedDisplayName,
  NULL AS PostTypeNameForSample,
  NULL AS ExampleNewUser
WHERE
  NOT EXISTS (SELECT 1 FROM UserActivity); -- Ensure this part only runs if UserActivity is empty
