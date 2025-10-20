WITH QuestionAliases AS (
  SELECT p.Id, p.Title, p.OwnerUserId, p.CreationDate, p.Score, 
         COALESCE(p.ViewCount, 0) AS ViewCount,
         ROW_NUMBER() OVER (PARTITION BY p.OwnerUserId ORDER BY p.Score DESC, p.CreationDate) AS OwnerTopQuestionRank,
         COUNT(a.Id) AS AnswerCount,
         (
           SELECT COUNT(DISTINCT phat.Id) 
           FROM PostHistory phat
           WHERE phat.PostId = p.Id AND phat.PostHistoryTypeId IN (4,5,6)
         ) AS EditableHistoryCount
  FROM Posts p 
  LEFT JOIN Posts a ON a.ParentId = p.Id AND a.PostTypeId = 2
  WHERE p.PostTypeId = 1
  GROUP BY p.Id, p.Title, p.OwnerUserId, p.CreationDate, p.Score, p.ViewCount
), VistaActivityByUser AS (
  SELECT u.Id AS UserId,
         COALESCE(u.UpVotes,0) AS UPVOTES,
         COALESCE(u.DownVotes,0) AS DOWNVOTES,
         AVG(COALESCE(p.Score,0)) AS AvgPostScore,
         SUM(COALESCE(p.ViewCount,0)) AS TotalPostViews,
         COUNT(p.Id) AS PostsCount,
         MAX(ph.CreationDate) AS LastActivity
  FROM Users u
  LEFT JOIN Posts p ON p.OwnerUserId = u.Id
  LEFT JOIN PostHistory ph ON ph.UserId = u.Id AND ph.PostId = p.Id
  GROUP BY u.Id, u.UpVotes, u.DownVotes
), QuestionsWithBadges AS (
  SELECT DISTINCT p.Id AS QuestionId, b.Class AS BadgeClass,
         ROW_NUMBER() OVER (PARTITION BY p.OwnerUserId ORDER BY b.Date DESC) AS RankedUserBadges
  FROM Posts p
  LEFT JOIN Badges b ON b.UserId = p.OwnerUserId 
  WHERE p.PostTypeId = 1 
    AND b.Class IN (1,2,3)
), DuplicatesAndLinks AS (
  SELECT pl.PostId, pl.RelatedPostId, lt.Name AS LinkTypeName,
       EXISTS (
         SELECT 1 FROM PostLinks pl2
         WHERE pl2.PostId = pl.RelatedPostId
           AND pl2.RelatedPostId = pl.PostId
           AND pl2.LinkTypeId = pl.LinkTypeId
       ) AS IsDuplicatedBackReference
  FROM PostLinks pl
  JOIN LinkTypes lt ON lt.Id = pl.LinkTypeId
), TopTagsByScore AS (
  SELECT t.TagName, SUM(p.Score) AS TotalScore, COUNT(p.Id) AS PostCount,
         RANK() OVER (ORDER BY SUM(p.Score) DESC) AS RankingByScore,
         RANK() OVER (ORDER BY COUNT(p.Id) DESC) AS RankingByCount
  FROM Tags t
  LEFT JOIN Posts p ON POSITION(CONCAT('<', t.TagName, '>') IN COALESCE(p.Tags, '')) > 0
  WHERE p.PostTypeId = 1
  GROUP BY t.TagName
)
SELECT qa.Id,
       qa.Title,
       qa.Score,
       NULL AS EditorRecords,
       COALESCE(DAL.LinkTypeName, 'None') AS LinkTypeName,
       vw.UserId, vw.UPVOTES, vw.DOWNVOTES, vw.AvgPostScore,
       vw.TotalPostViews, vw.PostsCount, vw.LastActivity,
       COALESCE(qb.BadgeClass, 0) AS BadgeClass,
       tsb.TotalScore, tsb.PostCount,
       CASE 
         WHEN qa.Score > (tsb.TotalScore / NULLIF(tsb.PostCount, 0)) THEN 'Above Average'
         ELSE 'Below or Equal Average' 
       END AS PerformanceClassification,
       (CASE WHEN LENGTH(qa.Title) > 50 THEN SUBSTRING(qa.Title FROM 1 FOR 50) || '..' ELSE qa.Title END) AS TitleSnippet_DirectionLightNightTvMoonSafetyQuiltProtein_doNegativeSpaceCharactersAzoreaClosedNoHumanMarketBob
FROM QuestionAliases qa
JOIN VistaActivityByUser vw ON vw.UserId = qa.OwnerUserId
LEFT JOIN QuestionsWithBadges qb ON qb.QuestionId = qa.Id AND qb.RankedUserBadges = 1
LEFT JOIN DuplicatesAndLinks DAL ON DAL.PostId = qa.Id
LEFT JOIN TopTagsByScore tsb ON POSITION(tsb.TagName IN qa.Title) > 0
WHERE (qa.OwnerTopQuestionRank <= 10 OR qa.EditableHistoryCount > 3)
  AND (vw.UPVOTES + vw.DOWNVOTES) > 100
  AND (qb.BadgeClass IS NULL OR qb.BadgeClass <= 2)
GROUP BY qa.Id, qa.Title, qa.Score, COALESCE(DAL.LinkTypeName, 'None'),
         vw.UserId, vw.UPVOTES, vw.DOWNVOTES, vw.AvgPostScore,
         vw.TotalPostViews, vw.PostsCount, vw.LastActivity,
         COALESCE(qb.BadgeClass, 0),
         tsb.TotalScore, tsb.PostCount,
         CASE 
           WHEN qa.Score > (tsb.TotalScore / NULLIF(tsb.PostCount, 0)) THEN 'Above Average'
           ELSE 'Below or Equal Average' 
         END,
         (CASE WHEN LENGTH(qa.Title) > 50 THEN SUBSTRING(qa.Title FROM 1 FOR 50) || '..' ELSE qa.Title END)
ORDER BY vw.LastActivity DESC, qa.Score DESC
LIMIT 100;