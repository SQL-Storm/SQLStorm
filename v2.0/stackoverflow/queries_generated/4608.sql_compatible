WITH
  RankedPostEdits AS (
    SELECT
      ph.PostId,
      ph.UserId,
      ph.CreationDate,
      pht.Name AS HistoryType,
      ROW_NUMBER() OVER (PARTITION BY ph.PostId, ph.UserId ORDER BY ph.CreationDate DESC) AS rn
    FROM PostHistory AS ph
    JOIN PostHistoryTypes AS pht
      ON ph.PostHistoryTypeId = pht.Id
    WHERE
      ph.PostHistoryTypeId IN (4, 5, 6)
  ),
  UserContribution AS (
    SELECT
      u.Id AS UserId,
      u.DisplayName,
      COUNT(DISTINCT p.Id) AS QuestionsAnswered,
      SUM(CASE WHEN p.PostTypeId = 2 THEN 1 ELSE 0 END) AS AnswersProvided,
      COUNT(DISTINCT b.Id) AS BadgesEarned,
      MAX(u.Reputation) AS MaxReputation
    FROM Users AS u
    LEFT JOIN Posts AS p
      ON u.Id = p.OwnerUserId
    LEFT JOIN Badges AS b
      ON u.Id = b.UserId
    WHERE
      u.CreationDate < (cast('2024-10-01' as date) - INTERVAL '1 year')
    GROUP BY
      u.Id,
      u.DisplayName
    HAVING
      COUNT(DISTINCT p.Id) > 50
  ),
  PostEngagement AS (
    SELECT
      p.Id AS PostId,
      p.Title,
      p.CreationDate,
      p.OwnerUserId,
      COALESCE(p.AnswerCount, 0) AS AnswerCount,
      COALESCE(p.CommentCount, 0) AS CommentCount,
      COALESCE(p.FavoriteCount, 0) AS FavoriteCount,
      COALESCE(p.ViewCount, 0) AS ViewCount,
      CASE WHEN p.ClosedDate IS NOT NULL THEN 1 ELSE 0 END AS IsClosed,
      (
        SELECT COUNT(*) FROM Votes AS v WHERE v.PostId = p.Id AND v.VoteTypeId = 2
      ) AS UpVotes,
      (
        SELECT COUNT(*) FROM Votes AS v WHERE v.PostId = p.Id AND v.VoteTypeId = 3
      ) AS DownVotes
    FROM Posts AS p
    WHERE
      p.PostTypeId = 1
  )
SELECT
  pe.PostId,
  pe.Title,
  uc.DisplayName AS OwnerDisplayName,
  uc.QuestionsAnswered,
  uc.AnswersProvided,
  uc.BadgesEarned,
  uc.MaxReputation,
  pe.AnswerCount,
  pe.CommentCount,
  pe.FavoriteCount,
  pe.ViewCount,
  pe.IsClosed,
  pe.UpVotes,
  pe.DownVotes,
  COALESCE(rpe.HistoryType, 'No Edits') AS LastEditType,
  (cast('2024-10-01' as date) - pe.CreationDate) AS DaysSinceCreation,
  CASE
    WHEN pe.ViewCount > 1000000 THEN 'Very High'
    WHEN pe.ViewCount > 100000 THEN 'High'
    WHEN pe.ViewCount > 10000 THEN 'Medium'
    ELSE 'Low'
  END AS ViewBucket,
  CASE
    WHEN pe.UpVotes - pe.DownVotes > 500 THEN 'Very Popular'
    WHEN pe.UpVotes - pe.DownVotes > 100 THEN 'Popular'
    ELSE 'Average'
  END AS EngagementLevel,
  CASE
    WHEN uc.MaxReputation IS NULL THEN 'New User'
    WHEN uc.MaxReputation < 1000 THEN 'Beginner'
    WHEN uc.MaxReputation < 10000 THEN 'Intermediate'
    ELSE 'Expert'
  END AS UserExperienceLevel
FROM PostEngagement AS pe
LEFT JOIN UserContribution AS uc
  ON pe.OwnerUserId = uc.UserId
LEFT JOIN RankedPostEdits AS rpe
  ON pe.PostId = rpe.PostId AND rpe.rn = 1
WHERE
  pe.CreationDate BETWEEN (cast('2024-10-01' as date) - INTERVAL '365 days') AND cast('2024-10-01' as date)
  AND pe.ViewCount > 1000
GROUP BY
  pe.PostId,
  pe.Title,
  uc.DisplayName,
  uc.QuestionsAnswered,
  uc.AnswersProvided,
  uc.BadgesEarned,
  uc.MaxReputation,
  pe.CreationDate,
  pe.OwnerUserId,
  pe.AnswerCount,
  pe.CommentCount,
  pe.FavoriteCount,
  pe.ViewCount,
  pe.IsClosed,
  pe.UpVotes,
  pe.DownVotes,
  rpe.HistoryType
ORDER BY
  pe.ViewCount DESC,
  pe.UpVotes DESC;