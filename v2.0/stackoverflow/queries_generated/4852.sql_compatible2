WITH
  RankedUserActivity AS (
    SELECT
      u.Id AS UserId,
      u.DisplayName,
      u.Reputation,
      p.Id AS PostId,
      p.PostTypeId,
      p.CreationDate AS PostCreationDate,
      p.Score AS PostScore,
      pt.Name AS PostTypeName,
      ROW_NUMBER() OVER (PARTITION BY u.Id ORDER BY p.CreationDate DESC) AS rn,
      COUNT(c.Id) OVER (PARTITION BY u.Id) AS CommentCountForUser,
      SUM(CASE WHEN v.VoteTypeId = 2 THEN 1 ELSE 0 END) OVER (PARTITION BY u.Id) AS UpVoteCountForUser,
      SUM(CASE WHEN v.VoteTypeId = 3 THEN 1 ELSE 0 END) OVER (PARTITION BY u.Id) AS DownVoteCountForUser,
      AVG(p.Score) OVER (PARTITION BY u.Id, p.PostTypeId) AS AvgPostScoreForUserAndType
    FROM Users AS u
    JOIN Posts AS p
      ON u.Id = p.OwnerUserId
    JOIN PostTypes AS pt
      ON p.PostTypeId = pt.Id
    LEFT JOIN Comments AS c
      ON p.Id = c.PostId
    LEFT JOIN Votes AS v
      ON p.Id = v.PostId
    WHERE
      p.CreationDate >= CAST('2024-10-01' AS DATE) - INTERVAL '365 days'
    GROUP BY
      u.Id,
      u.DisplayName,
      u.Reputation,
      p.Id,
      p.PostTypeId,
      p.CreationDate,
      p.Score,
      pt.Name,
      c.Id,
      v.VoteTypeId
  ),
  UserActivitySummary AS (
    SELECT
      UserId,
      DisplayName,
      Reputation,
      CommentCountForUser,
      UpVoteCountForUser,
      DownVoteCountForUser,
      COUNT(CASE WHEN PostTypeId = 1 THEN PostId END) AS QuestionCount,
      COUNT(CASE WHEN PostTypeId = 2 THEN PostId END) AS AnswerCount,
      SUM(PostScore) AS TotalScore,
      MAX(AvgPostScoreForUserAndType) AS MaxAvgScore,
      MIN(AvgPostScoreForUserAndType) AS MinAvgScore,
      (
        SELECT
          COUNT(DISTINCT ph.PostId)
        FROM PostHistory AS ph
        WHERE
          ph.UserId = r.UserId
          AND ph.PostHistoryTypeId IN (4, 5, 6)
      ) AS EditsMade
    FROM RankedUserActivity AS r
    WHERE
      rn <= 10
    GROUP BY
      UserId,
      DisplayName,
      Reputation,
      CommentCountForUser,
      UpVoteCountForUser,
      DownVoteCountForUser
  )
SELECT
  uas.DisplayName,
  uas.Reputation,
  uas.QuestionCount,
  uas.AnswerCount,
  uas.TotalScore,
  COALESCE(uas.CommentCountForUser, 0) AS TotalComments,
  COALESCE(uas.UpVoteCountForUser, 0) AS TotalUpVotes,
  COALESCE(uas.DownVoteCountForUser, 0) AS TotalDownVotes,
  uas.EditsMade,
  CASE
    WHEN uas.Reputation > 100000 THEN 'Guru'
    WHEN uas.Reputation BETWEEN 50000 AND 100000 THEN 'Expert'
    WHEN uas.Reputation BETWEEN 10000 AND 50000 THEN 'Master'
    WHEN uas.Reputation BETWEEN 5000 AND 10000 THEN 'Sage'
    WHEN uas.Reputation BETWEEN 1000 AND 5000 THEN 'Experienced'
    WHEN uas.Reputation BETWEEN 500 AND 1000 THEN 'Novice'
    ELSE 'Beginner'
  END AS ReputationLevel,
  (
    SELECT
      COUNT(*)
    FROM Badges AS b
    WHERE
      b.UserId = uas.UserId
      AND b.Class = 1
  ) AS GoldBadgeCount,
  (
    SELECT
      COUNT(*)
    FROM Badges AS b
    WHERE
      b.UserId = uas.UserId
      AND b.Class = 2
  ) AS SilverBadgeCount,
  (
    SELECT
      COUNT(*)
    FROM Badges AS b
    WHERE
      b.UserId = uas.UserId
      AND b.Class = 3
  ) AS BronzeBadgeCount,
  CASE
    WHEN EXISTS(
      SELECT
        1
      FROM PostLinks AS pl
      WHERE
        pl.PostId = (
          SELECT
            p.Id
          FROM Posts AS p
          WHERE
            p.OwnerUserId = uas.UserId
            AND p.PostTypeId = 1
          ORDER BY
            p.CreationDate ASC
          LIMIT 1
        )
        AND pl.LinkTypeId = 3
    ) THEN 'HasDuplicateLink'
    ELSE 'NoDuplicateLink'
  END AS DuplicateLinkStatus,
  CAST(uas.MaxAvgScore AS REAL) - CAST(uas.MinAvgScore AS REAL) AS ScoreRangeDifferential,
  uas.UserId
FROM UserActivitySummary AS uas
WHERE
  uas.TotalScore > 0
UNION
SELECT
  NULL AS DisplayName,
  NULL AS Reputation,
  NULL AS QuestionCount,
  NULL AS AnswerCount,
  NULL AS TotalScore,
  COUNT(c.Id) AS TotalComments,
  NULL AS TotalUpVotes,
  NULL AS TotalDownVotes,
  NULL AS EditsMade,
  NULL AS ReputationLevel,
  NULL AS GoldBadgeCount,
  NULL AS SilverBadgeCount,
  NULL AS BronzeBadgeCount,
  NULL AS DuplicateLinkStatus,
  NULL AS ScoreRangeDifferential,
  c.UserId
FROM Comments AS c
WHERE
  c.CreationDate >= CAST('2024-10-01' AS DATE) - INTERVAL '365 days'
GROUP BY
  c.UserId
HAVING
  COUNT(c.Id) > 50
ORDER BY
  Reputation DESC NULLS LAST;