WITH RECURSIVE RecursivePostLinks AS (
    SELECT pl.PostId, pl.RelatedPostId, pl.LinkTypeId, 1 AS Depth
    FROM PostLinks pl
    WHERE pl.LinkTypeId = 1
    UNION ALL
    SELECT pl.PostId, pl.RelatedPostId, pl.LinkTypeId, rpl.Depth + 1
    FROM PostLinks pl
    JOIN RecursivePostLinks rpl ON pl.PostId = rpl.RelatedPostId
    WHERE pl.LinkTypeId = 1 AND rpl.Depth < 3
),
RecursiveTaggedPosts AS (
    SELECT p.Id, p.Title, p.Tags, p.PostTypeId, p.CreationDate, p.Score, p.ViewCount, p.OwnerUserId,
           array_remove(string_to_array(substring(p.Tags FROM 2 FOR length(p.Tags) - 2), '><'), '') AS TagArray
    FROM Posts p
    WHERE p.PostTypeId = 1 AND p.Tags IS NOT NULL
),
TagHierarchy AS (
    SELECT t.Id, t.TagName, t.Count, t.IsModeratorOnly, t.IsRequired,
           COALESCE(t.ExcerptPostId, 0) AS ExcerptPostId,
           COALESCE(t.WikiPostId, 0) AS WikiPostId
    FROM Tags t
),
UserBadgeCounts AS (
    SELECT u.Id AS UserId, 
           COALESCE(SUM(CASE WHEN b.Class = 1 THEN 1 ELSE 0 END),0) AS GoldBadges,
           COALESCE(SUM(CASE WHEN b.Class = 2 THEN 1 ELSE 0 END),0) AS SilverBadges,
           COALESCE(SUM(CASE WHEN b.Class = 3 THEN 1 ELSE 0 END),0) AS BronzeBadges
    FROM Users u
    LEFT JOIN Badges b ON b.UserId = u.Id
    GROUP BY u.Id
),
AnswerStats AS (
    SELECT a.ParentId AS QuestionId,
           COUNT(*) FILTER (WHERE a.Score > 0) AS PositiveAnswerCount,
           COUNT(*) FILTER (WHERE a.Score <= 0) AS NonPositiveAnswerCount,
           MAX(a.Score) AS MaxAnswerScore,
           AVG(a.Score) AS AvgAnswerScore,
           BOOL_OR(a.OwnerUserId IS NULL) AS HasAnonymousAnswer
    FROM Posts a
    WHERE a.PostTypeId = 2
    GROUP BY a.ParentId
),
QuestionCommentsAgg AS (
    SELECT c.PostId,
           COUNT(c.Id) AS TotalComments,
           SUM(COALESCE(c.Score,0)) AS CommentsScoreSum,
           STRING_AGG(DISTINCT COALESCE(c.UserDisplayName, 'Anonymous'), ', ' ORDER BY COALESCE(c.UserDisplayName, 'Anonymous')) AS Commenters
    FROM Comments c
    GROUP BY c.PostId
),
QuestionPostWithMetadata AS (
    SELECT q.Id, q.Title, q.CreationDate, q.Score, q.ViewCount, q.Tags, q.OwnerUserId,
           ub.GoldBadges, ub.SilverBadges, ub.BronzeBadges,
           asv.PositiveAnswerCount, asv.NonPositiveAnswerCount, asv.MaxAnswerScore, asv.AvgAnswerScore, asv.HasAnonymousAnswer,
           qca.TotalComments, qca.CommentsScoreSum, qca.Commenters,
           row_number() OVER (PARTITION BY q.OwnerUserId ORDER BY q.CreationDate DESC) AS UserLatestQuestionRank
    FROM Posts q
    LEFT JOIN UserBadgeCounts ub ON ub.UserId = q.OwnerUserId
    LEFT JOIN AnswerStats asv ON asv.QuestionId = q.Id
    LEFT JOIN QuestionCommentsAgg qca ON qca.PostId = q.Id
    WHERE q.PostTypeId = 1
),
TaggedQuestionDetails AS (
    SELECT q.Id AS QuestionId,
           q.Title,
           q.CreationDate,
           q.Score,
           q.ViewCount,
           unnest(array_remove(string_to_array(substring(q.Tags FROM 2 FOR length(q.Tags) - 2), '><'), '')) AS Tag,
           q.GoldBadges, q.SilverBadges, q.BronzeBadges,
           q.PositiveAnswerCount, q.NonPositiveAnswerCount, q.MaxAnswerScore, q.AvgAnswerScore, q.HasAnonymousAnswer,
           q.TotalComments, q.CommentsScoreSum, q.Commenters,
           q.UserLatestQuestionRank
    FROM QuestionPostWithMetadata q
    WHERE q.UserLatestQuestionRank <= 5
),
TagAggregates AS (
    SELECT t.TagName,
           COUNT(DISTINCT tq.QuestionId) AS QuestionCount,
           AVG(tq.Score) AS AvgQuestionScore,
           AVG(tq.ViewCount) AS AvgQuestionViews,
           AVG(tq.PositiveAnswerCount) AS AvgPositiveAnswers,
           AVG(tq.NonPositiveAnswerCount) AS AvgNonPositiveAnswers,
           SUM(COALESCE(tq.GoldBadges,0)) AS TotalGoldBadgesOfAskers,
           SUM(COALESCE(tq.SilverBadges,0)) AS TotalSilverBadgesOfAskers,
           SUM(COALESCE(tq.BronzeBadges,0)) AS TotalBronzeBadgesOfAskers,
           AVG(COALESCE(tq.AvgAnswerScore,0)) AS AvgAnswerScorePerQuestion
    FROM TaggedQuestionDetails tq
    JOIN Tags t ON t.TagName = tq.Tag
    GROUP BY t.TagName
),
DuplicatedLinkedQuestions AS (
    SELECT DISTINCT pl.PostId AS QuestionId, pl.RelatedPostId AS DuplicateOfQuestionId
    FROM PostLinks pl
    WHERE pl.LinkTypeId = 3
      AND EXISTS (SELECT 1 FROM Posts p WHERE p.Id = pl.PostId AND p.PostTypeId = 1)
      AND EXISTS (SELECT 1 FROM Posts p2 WHERE p2.Id = pl.RelatedPostId AND p2.PostTypeId = 1)
)
SELECT t.TagName,
       t.QuestionCount,
       t.AvgQuestionScore,
       t.AvgQuestionViews,
       t.AvgPositiveAnswers,
       t.AvgNonPositiveAnswers,
       t.TotalGoldBadgesOfAskers,
       t.TotalSilverBadgesOfAskers,
       t.TotalBronzeBadgesOfAskers,
       t.AvgAnswerScorePerQuestion,
       COALESCE(dq.DuplicateOfQuestionId, -1) AS SampleDuplicateQuestionId,
       COALESCE(q.Title, '(no duplicate question found)') AS SampleDuplicateTitle,
       SUBSTR(COALESCE(q.Body,''), 1, 100) AS DuplicateExcerpt,
       CASE WHEN tq.HasAnonymousAnswer THEN 'Yes' ELSE 'No' END AS HasAnonymousAnswersInSample,
       tq.UserLatestQuestionRank
FROM TagAggregates t
LEFT JOIN DuplicatedLinkedQuestions dq ON dq.QuestionId = (
    SELECT QuestionId
    FROM TaggedQuestionDetails
    WHERE Tag = t.TagName
    ORDER BY CreationDate DESC, QuestionId DESC
    LIMIT 1
)
LEFT JOIN Posts q ON q.Id = dq.DuplicateOfQuestionId
LEFT JOIN TaggedQuestionDetails tq ON tq.QuestionId = dq.QuestionId
WHERE t.QuestionCount > 50
ORDER BY t.QuestionCount DESC, t.AvgQuestionScore DESC
LIMIT 50;