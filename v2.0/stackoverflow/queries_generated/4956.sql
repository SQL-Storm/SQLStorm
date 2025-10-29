-- {"query": "4956.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gemini-2.5-flash-lite", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2111, "output_tokens": 1715} 

WITH
  RankedPostEdits AS (
    SELECT
      ph.PostId,
      ph.UserId,
      ph.UserDisplayName,
      ph.CreationDate AS EditDate,
      pht.Name AS EditType,
      ROW_NUMBER() OVER (PARTITION BY ph.PostId ORDER BY ph.CreationDate DESC) AS rn
    FROM
      PostHistory AS ph
      JOIN PostHistoryTypes AS pht
        ON ph.PostHistoryTypeId = pht.Id
    WHERE
      ph.PostHistoryTypeId IN (4, 5, 7, 8)
  ),
  UserPostActivity AS (
    SELECT
      p.OwnerUserId,
      COUNT(DISTINCT p.Id) AS PostCount,
      SUM(p.Score) AS TotalScore,
      AVG(p.Score) AS AvgScore,
      MAX(p.CreationDate) AS LastPostDate
    FROM
      Posts AS p
    WHERE
      p.OwnerUserId IS NOT NULL
    GROUP BY
      p.OwnerUserId
  ),
  UserVoteSummary AS (
    SELECT
      v.UserId,
      COUNT(CASE WHEN v.VoteTypeId = 2 THEN 1 END) AS UpVotesGiven,
      COUNT(CASE WHEN v.VoteTypeId = 3 THEN 1 END) AS DownVotesGiven,
      COUNT(CASE WHEN v.VoteTypeId = 16 THEN 1 END) AS ApprovedEdits
    FROM
      Votes AS v
    WHERE
      v.UserId IS NOT NULL
    GROUP BY
      v.UserId
  ),
  QuestionAnswerRatio AS (
    SELECT
      p.OwnerUserId,
      CAST(SUM(CASE WHEN p.PostTypeId = 1 THEN 1 ELSE 0 END) AS REAL) / NULLIF(SUM(CASE WHEN p.PostTypeId = 2 THEN 1 ELSE 0 END), 0) AS QuestionToAnswerRatio,
      COUNT(CASE WHEN p.PostTypeId = 1 THEN 1 END) AS QuestionCount,
      COUNT(CASE WHEN p.PostTypeId = 2 THEN 1 END) AS AnswerCount
    FROM
      Posts AS p
    WHERE
      p.OwnerUserId IS NOT NULL
    GROUP BY
      p.OwnerUserId
  ),
  UserBadgeAnalysis AS (
    SELECT
      b.UserId,
      COUNT(CASE WHEN b.Class = 1 THEN 1 END) AS GoldBadges,
      COUNT(CASE WHEN b.Class = 2 THEN 1 END) AS SilverBadges,
      COUNT(CASE WHEN b.Class = 3 THEN 1 END) AS BronzeBadges,
      MAX(b.Date) AS LastBadgeDate
    FROM
      Badges AS b
    GROUP BY
      b.UserId
  )
SELECT
  u.DisplayName,
  u.Reputation,
  u.Views,
  u.UpVotes AS UserUpVotes,
  u.DownVotes AS UserDownVotes,
  u.CreationDate AS UserCreationDate,
  upa.PostCount,
  upa.TotalScore,
  upa.AvgScore,
  qra.QuestionToAnswerRatio,
  qra.QuestionCount,
  qra.AnswerCount,
  uvs.UpVotesGiven,
  uvs.DownVotesGiven,
  uvs.ApprovedEdits,
  uba.GoldBadges,
  uba.SilverBadges,
  uba.BronzeBadges,
  rpe.EditType AS LatestEditType,
  rpe.EditDate AS LatestEditDate,
  CASE
    WHEN u.WebsiteUrl IS NULL THEN 'No Website'
    WHEN u.WebsiteUrl LIKE '%stackoverflow.com%' THEN 'Stack Overflow Related'
    ELSE 'External Website'
  END AS WebsiteCategory,
  CASE
    WHEN upa.LastPostDate < DATE('now', '-365 day') THEN 'Inactive'
    WHEN upa.LastPostDate < DATE('now', '-90 day') THEN 'Moderately Active'
    ELSE 'Active'
  END AS UserActivityStatus,
  COALESCE(uba.GoldBadges, 0) + COALESCE(uba.SilverBadges, 0) + COALESCE(uba.BronzeBadges, 0) AS TotalBadges
FROM
  Users AS u
LEFT OUTER JOIN
  UserPostActivity AS upa
  ON u.Id = upa.OwnerUserId
LEFT OUTER JOIN
  UserVoteSummary AS uvs
  ON u.Id = uvs.UserId
LEFT OUTER JOIN
  QuestionAnswerRatio AS qra
  ON u.Id = qra.OwnerUserId
LEFT OUTER JOIN
  UserBadgeAnalysis AS uba
  ON u.Id = uba.UserId
LEFT OUTER JOIN
  RankedPostEdits AS rpe
  ON u.Id = rpe.UserId AND rpe.rn = 1
WHERE
  u.Id > 0 AND u.DisplayName IS NOT NULL AND u.DisplayName NOT LIKE '%[^a-zA-Z0-9 ]%'
UNION
SELECT
  'Community User' AS DisplayName,
  MAX(u.Reputation) AS Reputation,
  SUM(u.Views) AS Views,
  SUM(u.UpVotes) AS UserUpVotes,
  SUM(u.DownVotes) AS UserDownVotes,
  MIN(u.CreationDate) AS UserCreationDate,
  COUNT(DISTINCT p.Id) AS PostCount,
  SUM(p.Score) AS TotalScore,
  AVG(p.Score) AS AvgScore,
  CAST(SUM(CASE WHEN p.PostTypeId = 1 THEN 1 ELSE 0 END) AS REAL) / NULLIF(SUM(CASE WHEN p.PostTypeId = 2 THEN 1 ELSE 0 END), 0) AS QuestionToAnswerRatio,
  COUNT(CASE WHEN p.PostTypeId = 1 THEN 1 END) AS QuestionCount,
  COUNT(CASE WHEN p.PostTypeId = 2 THEN 1 END) AS AnswerCount,
  SUM(CASE WHEN v.VoteTypeId = 2 THEN 1 ELSE 0 END) AS UpVotesGiven,
  SUM(CASE WHEN v.VoteTypeId = 3 THEN 1 ELSE 0 END) AS DownVotesGiven,
  SUM(CASE WHEN v.VoteTypeId = 16 THEN 1 ELSE 0 END) AS ApprovedEdits,
  COUNT(CASE WHEN b.Class = 1 THEN 1 END) AS GoldBadges,
  COUNT(CASE WHEN b.Class = 2 THEN 1 END) AS SilverBadges,
  COUNT(CASE WHEN b.Class = 3 THEN 1 END) AS BronzeBadges,
  MAX(rpe.EditType) AS LatestEditType,
  MAX(rpe.EditDate) AS LatestEditDate,
  'System Generated' AS WebsiteCategory,
  'Community' AS UserActivityStatus,
  COUNT(b.Id) AS TotalBadges
FROM
  Users AS u
JOIN
  Posts AS p
  ON u.Id = p.OwnerUserId AND p.OwnerUserId = -1
LEFT OUTER JOIN
  Votes AS v
  ON u.Id = v.UserId
LEFT OUTER JOIN
  Badges AS b
  ON u.Id = b.UserId
LEFT OUTER JOIN
  PostHistory AS ph
  ON u.Id = ph.UserId AND ph.PostHistoryTypeId IN (4, 5, 7, 8)
LEFT OUTER JOIN
  PostHistoryTypes AS rpe
  ON ph.PostHistoryTypeId = rpe.Id
GROUP BY
  p.OwnerUserId
HAVING
  p.OwnerUserId = -1;
