-- {"query": "4379.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gemini-2.5-flash-lite", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2111, "output_tokens": 938} 
WITH
  RankedUserPosts AS (
    SELECT
      p.OwnerUserId,
      p.Id AS PostId,
      p.PostTypeId,
      p.Score,
      p.ViewCount,
      ROW_NUMBER() OVER (PARTITION BY p.OwnerUserId ORDER BY p.CreationDate DESC) AS rn
    FROM Posts AS p
    WHERE
      p.OwnerUserId IS NOT NULL AND p.OwnerUserId <> -1
  ),
  UserPostStats AS (
    SELECT
      rup.OwnerUserId,
      COUNT(rup.PostId) AS TotalPosts,
      SUM(CASE WHEN rup.PostTypeId = 1 THEN 1 ELSE 0 END) AS QuestionCount,
      SUM(CASE WHEN rup.PostTypeId = 2 THEN 1 ELSE 0 END) AS AnswerCount,
      AVG(rup.Score) AS AverageScore,
      SUM(rup.ViewCount) AS TotalViews,
      MAX(rup.Score) AS MaxScore
    FROM RankedUserPosts AS rup
    GROUP BY
      rup.OwnerUserId
  ),
  HighReputationUsers AS (
    SELECT
      Id,
      DisplayName,
      Reputation,
      CreationDate,
      Views,
      UpVotes,
      DownVotes
    FROM Users
    WHERE
      Reputation > 10000
  ),
  RecentEdits AS (
    SELECT
      ph.PostId,
      ph.UserId AS EditorUserId,
      ph.CreationDate AS EditDate,
      ROW_NUMBER() OVER (PARTITION BY ph.PostId ORDER BY ph.CreationDate DESC) AS edit_rn
    FROM PostHistory AS ph
    WHERE
      ph.PostHistoryTypeId IN (4, 5, 6) /* Edit Title, Edit Body, Edit Tags */
  )
SELECT
  hru.DisplayName AS HighReputationUserName,
  hru.Reputation,
  ups.TotalPosts,
  ups.QuestionCount,
  ups.AnswerCount,
  ups.AverageScore,
  ups.TotalViews,
  ups.MaxScore,
  (
    SELECT
      COUNT(*)
    FROM Badges AS b
    WHERE
      b.UserId = hru.Id AND b.Class = 1 /* Gold Badge */
  ) AS GoldBadgeCount,
  COALESCE(
    (
      SELECT
        COUNT(*)
      FROM Comments AS c
      WHERE
        c.UserId = hru.Id AND c.CreationDate >= hru.CreationDate
    ),
    0
  ) AS CommentsSinceAccountCreation,
  CASE
    WHEN ups.AverageScore > 50 AND ups.TotalPosts > 500 THEN 'Expert'
    WHEN ups.AverageScore > 10 AND ups.TotalPosts > 100 THEN 'Experienced'
    ELSE 'Novice'
  END AS UserExperienceLevel,
  COALESCE(
    (
      SELECT
        COUNT(DISTINCT p_links.RelatedPostId)
      FROM Posts AS p
      INNER JOIN PostLinks AS p_links
        ON p.Id = p_links.PostId
      WHERE
        p.OwnerUserId = hru.Id AND p_links.LinkTypeId = 3 /* Duplicate Link */
    ),
    0
  ) AS PostsMarkedAsDuplicate,
  CASE
    WHEN re.edit_rn = 1 AND re.EditorUserId = hru.Id THEN 'Last Editor'
    WHEN re.edit_rn = 1 AND re.EditorUserId <> hru.Id THEN 'Other Last Editor'
    ELSE 'No Recent Edits'
  END AS LastEditStatus
FROM HighReputationUsers AS hru
LEFT OUTER JOIN UserPostStats AS ups
  ON hru.Id = ups.OwnerUserId
LEFT OUTER JOIN RecentEdits AS re
  ON hru.Id = re.EditorUserId AND re.edit_rn = 1
WHERE
  hru.Views > 10000
  AND (ups.TotalPosts IS NULL OR ups.TotalPosts > 50)
ORDER BY
  hru.Reputation DESC,
  ups.AverageScore DESC;