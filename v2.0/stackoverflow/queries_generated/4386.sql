-- {"query": "4386.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gemini-2.5-flash-lite", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2111, "output_tokens": 1472} 

WITH
  RankedPostEdits AS (
    SELECT
      ph.PostId,
      ph.UserId,
      ph.CreationDate AS EditDate,
      ph.Comment AS EditComment,
      pht.Name AS EditType,
      ROW_NUMBER() OVER (PARTITION BY ph.PostId, ph.UserId ORDER BY ph.CreationDate DESC) AS rn
    FROM PostHistory AS ph
    JOIN PostHistoryTypes AS pht
      ON ph.PostHistoryTypeId = pht.Id
    WHERE
      ph.PostHistoryTypeId IN (4, 5, 6) -- Edit Title, Edit Body, Edit Tags
  ),
  UserPostContribution AS (
    SELECT
      p.OwnerUserId,
      COUNT(DISTINCT p.Id) AS QuestionCount,
      SUM(CASE WHEN p.PostTypeId = 2 THEN 1 ELSE 0 END) AS AnswerCount
    FROM Posts AS p
    WHERE
      p.OwnerUserId IS NOT NULL
    GROUP BY
      p.OwnerUserId
  ),
  RecentActivity AS (
    SELECT
      p.Id AS PostId,
      p.OwnerUserId,
      p.CreationDate AS PostCreationDate,
      p.LastActivityDate,
      p.Title,
      p.Score,
      p.ViewCount,
      ROW_NUMBER() OVER (PARTITION BY p.OwnerUserId ORDER BY p.LastActivityDate DESC) AS LastActivityRank
    FROM Posts AS p
    WHERE
      p.PostTypeId = 1 -- Questions
      AND p.OwnerUserId IS NOT NULL
  ),
  UserEngagement AS (
    SELECT
      u.Id AS UserId,
      u.DisplayName,
      u.Reputation,
      u.CreationDate AS UserCreationDate,
      u.LastAccessDate,
      COUNT(DISTINCT c.Id) AS CommentCount,
      SUM(CASE WHEN v.VoteTypeId = 2 THEN 1 ELSE 0 END) AS UpVoteCount,
      SUM(CASE WHEN v.VoteTypeId = 3 THEN 1 ELSE 0 END) AS DownVoteCount,
      MAX(CASE WHEN b.Class = 1 THEN b.Name ELSE NULL END) AS GoldBadge,
      MAX(CASE WHEN b.Class = 2 THEN b.Name ELSE NULL END) AS SilverBadge,
      MAX(CASE WHEN b.Class = 3 THEN b.Name ELSE NULL END) AS BronzeBadge
    FROM Users AS u
    LEFT JOIN Comments AS c
      ON u.Id = c.UserId
    LEFT JOIN Votes AS v
      ON u.Id = v.UserId
    LEFT JOIN Badges AS b
      ON u.Id = b.UserId
    WHERE
      u.Id > 0 -- Exclude community user and deleted users if represented by -1 or 0
    GROUP BY
      u.Id,
      u.DisplayName,
      u.Reputation,
      u.CreationDate,
      u.LastAccessDate
  )
SELECT
  ue.UserId,
  ue.DisplayName,
  ue.Reputation,
  ue.UserCreationDate,
  ue.LastAccessDate,
  COALESCE(upc.QuestionCount, 0) AS TotalQuestionsPosted,
  COALESCE(upc.AnswerCount, 0) AS TotalAnswersPosted,
  ue.CommentCount,
  ue.UpVoteCount,
  ue.DownVoteCount,
  ue.GoldBadge,
  ue.SilverBadge,
  ue.BronzeBadge,
  ra.Title AS LatestQuestionTitle,
  ra.PostCreationDate AS LatestQuestionCreationDate,
  ra.LastActivityDate AS LatestQuestionActivityDate,
  ra.Score AS LatestQuestionScore,
  ra.ViewCount AS LatestQuestionViewCount,
  rpe.EditDate AS LatestEditDate,
  rpe.EditType AS LatestEditType,
  rpe.EditComment,
  CASE
    WHEN ue.LastAccessDate < DATE('now', '-30 day') THEN 'Inactive'
    WHEN ue.LastAccessDate < DATE('now', '-7 day') THEN 'Less Active'
    ELSE 'Active'
  END AS UserActivityStatus,
  CASE
    WHEN LENGTH(ue.DisplayName) > 20 THEN SUBSTRING(ue.DisplayName, 1, 17) || '...'
    ELSE ue.DisplayName
  END AS TruncatedDisplayName,
  CASE
    WHEN ue.Reputation BETWEEN 0 AND 1000 THEN 'Novice'
    WHEN ue.Reputation BETWEEN 1001 AND 10000 THEN 'Experienced'
    WHEN ue.Reputation > 10000 THEN 'Expert'
    ELSE 'Unknown'
  END AS ReputationTier
FROM UserEngagement AS ue
LEFT JOIN UserPostContribution AS upc
  ON ue.UserId = upc.OwnerUserId
LEFT JOIN RecentActivity AS ra
  ON ue.UserId = ra.OwnerUserId AND ra.LastActivityRank = 1
LEFT JOIN RankedPostEdits AS rpe
  ON ue.UserId = rpe.UserId AND rpe.rn = 1
WHERE
  ue.Reputation > 500
  AND ue.UserCreationDate < DATE('now', '-365 day')
UNION
SELECT
  NULL AS UserId,
  'Community' AS DisplayName,
  0 AS Reputation,
  NULL AS UserCreationDate,
  NULL AS LastAccessDate,
  COUNT(CASE WHEN p.PostTypeId = 1 THEN 1 END) AS TotalQuestionsPosted,
  COUNT(CASE WHEN p.PostTypeId = 2 THEN 1 END) AS TotalAnswersPosted,
  COUNT(DISTINCT c.Id) AS CommentCount,
  0 AS UpVoteCount,
  0 AS DownVoteCount,
  NULL AS GoldBadge,
  NULL AS SilverBadge,
  NULL AS BronzeBadge,
  NULL AS LatestQuestionTitle,
  NULL AS LatestQuestionCreationDate,
  NULL AS LatestQuestionActivityDate,
  NULL AS LatestQuestionScore,
  NULL AS LatestQuestionViewCount,
  NULL AS LatestEditDate,
  NULL AS LatestEditType,
  NULL AS EditComment,
  'N/A' AS UserActivityStatus,
  'Community' AS TruncatedDisplayName,
  'Community' AS ReputationTier
FROM Posts AS p
LEFT JOIN Comments AS c
  ON p.Id = c.PostId
WHERE
  p.OwnerUserId IS NULL OR p.OwnerUserId = -1
  OR p.CommunityOwnedDate IS NOT NULL;
