WITH
  RecentQuestions AS (
    SELECT
      Id,
      OwnerUserId,
      Title,
      Tags,
      CreationDate,
      Score,
      AnswerCount,
      FavoriteCount,
      ROW_NUMBER() OVER (ORDER BY CreationDate DESC) AS rn,
      ClosedDate
    FROM Posts
    WHERE PostTypeId = 1 AND CreationDate > TIMESTAMP '2023-01-01'
  ),
  HighScoringAnswers AS (
    SELECT
      p.Id,
      p.ParentId,
      p.Score,
      p.OwnerUserId,
      p.CreationDate,
      ROW_NUMBER() OVER (
        PARTITION BY p.ParentId
        ORDER BY p.Score DESC, p.CreationDate ASC
      ) AS answer_rank
    FROM Posts p
    WHERE p.PostTypeId = 2 AND p.Score > 5
  ),
  UserEngagement AS (
    SELECT
      u.Id AS UserId,
      u.DisplayName,
      u.Reputation,
      u.UpVotes AS UserUpVotes,
      u.DownVotes AS UserDownVotes,
      COUNT(DISTINCT b.Id) AS BadgeCount,
      SUM(CASE WHEN v.VoteTypeId = 2 THEN 1 ELSE 0 END) AS TotalUpvotesCast,
      SUM(CASE WHEN v.VoteTypeId = 3 THEN 1 ELSE 0 END) AS TotalDownvotesCast
    FROM Users u
    LEFT JOIN Badges b ON u.Id = b.UserId
    LEFT JOIN Votes v ON u.Id = v.UserId
    GROUP BY
      u.Id,
      u.DisplayName,
      u.Reputation,
      u.UpVotes,
      u.DownVotes
  )
SELECT
  rq.Id AS QuestionId,
  rq.Title AS QuestionTitle,
  u.DisplayName AS QuestionOwnerDisplayName,
  u.Reputation AS QuestionOwnerReputation,
  rq.Score AS QuestionScore,
  rq.AnswerCount AS QuestionAnswerCount,
  rq.FavoriteCount AS QuestionFavoriteCount,
  CASE WHEN rq.Tags LIKE '%<sql>%' THEN 'SQL Related' ELSE 'Other' END AS TagCategory,
  hsa.Id AS BestAnswerId,
  hsa.Score AS BestAnswerScore,
  hsa_owner.DisplayName AS BestAnswerOwnerDisplayName,
  hsa_owner.Reputation AS BestAnswerOwnerReputation,
  EXTRACT(EPOCH FROM (COALESCE(rq.ClosedDate, TIMESTAMP '2024-10-01 12:34:56') - rq.CreationDate)) / 60 AS TimeToCloseMinutes,
  ue.BadgeCount AS QuestionOwnerBadgeCount,
  ue.TotalUpvotesCast AS QuestionOwnerUpvotesCast,
  ue.TotalDownvotesCast AS QuestionOwnerDownvotesCast,
  CASE
    WHEN EXISTS(
      SELECT 1
      FROM PostLinks pl
      WHERE pl.PostId = rq.Id AND pl.LinkTypeId = 3
    ) THEN 'Linked as Duplicate'
    ELSE 'Not Linked as Duplicate'
  END AS DuplicateStatus
FROM RecentQuestions rq
JOIN Users u ON rq.OwnerUserId = u.Id
LEFT JOIN HighScoringAnswers hsa ON rq.Id = hsa.ParentId AND hsa.answer_rank = 1
LEFT JOIN Users hsa_owner ON hsa.OwnerUserId = hsa_owner.Id
LEFT JOIN UserEngagement ue ON rq.OwnerUserId = ue.UserId
WHERE
  rq.rn <= 1000
  AND (rq.Score > 10 OR rq.AnswerCount > 5)
  AND u.Location IS NOT NULL
  AND CHAR_LENGTH(COALESCE(u.AboutMe, '')) > 50

UNION ALL

SELECT
  CAST(NULL AS bigint),
  CAST(NULL AS text),
  CAST(NULL AS text),
  CAST(NULL AS integer),
  CAST(NULL AS integer),
  CAST(NULL AS integer),
  CAST(NULL AS integer),
  CAST(NULL AS text),
  CAST(NULL AS bigint),
  CAST(NULL AS integer),
  CAST(NULL AS text),
  CAST(NULL AS integer),
  CAST(NULL AS double precision),
  CAST(NULL AS integer),
  CAST(NULL AS bigint),
  CAST(NULL AS bigint),
  CAST(NULL AS text)
FROM PostHistoryTypes
WHERE Id = 1

UNION ALL

SELECT
  rq.Id,
  rq.Title,
  u.DisplayName,
  u.Reputation,
  rq.Score,
  rq.AnswerCount,
  rq.FavoriteCount,
  CASE WHEN rq.Tags LIKE '%<python>%' THEN 'Python Related' ELSE 'Other' END,
  hsa.Id,
  hsa.Score,
  hsa_owner.DisplayName,
  hsa_owner.Reputation,
  EXTRACT(EPOCH FROM (COALESCE(rq.ClosedDate, TIMESTAMP '2024-10-01 12:34:56') - rq.CreationDate)) / 60,
  ue.BadgeCount,
  ue.TotalUpvotesCast,
  ue.TotalDownvotesCast,
  CASE
    WHEN EXISTS(
      SELECT 1
      FROM PostLinks pl
      WHERE pl.PostId = rq.Id AND pl.LinkTypeId = 3
    ) THEN 'Linked as Duplicate'
    ELSE 'Not Linked as Duplicate'
  END
FROM RecentQuestions rq
JOIN Users u ON rq.OwnerUserId = u.Id
LEFT JOIN HighScoringAnswers hsa ON rq.Id = hsa.ParentId AND hsa.answer_rank = 1
LEFT JOIN Users hsa_owner ON hsa.OwnerUserId = hsa_owner.Id
LEFT JOIN UserEngagement ue ON rq.OwnerUserId = ue.UserId
WHERE
  rq.rn <= 1000
  AND (rq.Score > 5 OR rq.AnswerCount > 3)
  AND u.Location IS NULL
  AND CHAR_LENGTH(COALESCE(u.AboutMe, '')) <= 50;