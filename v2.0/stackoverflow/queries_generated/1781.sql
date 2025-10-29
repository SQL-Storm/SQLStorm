-- {"query": "1781.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gemini-2.5-flash", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2111, "output_tokens": 3237} 

WITH UserEngagement AS (
    SELECT
        u.Id AS UserId,
        u.DisplayName AS UserName,
        u.Reputation,
        u.CreationDate AS UserCreationDate,
        u.LastAccessDate,
        u.Views AS UserViews,
        u.UpVotes,
        u.DownVotes,
        COALESCE(u.Location, 'Unknown') AS UserLocation,
        SUM(CASE WHEN p.PostTypeId = 1 AND p.OwnerUserId = u.Id THEN 1 ELSE 0 END) AS QuestionsAsked,
        SUM(CASE WHEN p.PostTypeId = 2 AND p.OwnerUserId = u.Id THEN 1 ELSE 0 END) AS AnswersPosted,
        COUNT(DISTINCT c.Id) AS CommentsMade,
        CAST(u.UpVotes - u.DownVotes AS DECIMAL(10,2)) / NULLIF(u.Views + 1, 0) AS UpvoteToViewRatio,
        DENSE_RANK() OVER (ORDER BY u.Reputation DESC, u.CreationDate ASC) AS ReputationRank,
        ROW_NUMBER() OVER (PARTITION BY COALESCE(u.Location, 'Unknown') ORDER BY u.LastAccessDate DESC) AS LastAccessRankInLocation
    FROM Users AS u
    LEFT JOIN Posts AS p ON u.Id = p.OwnerUserId
    LEFT JOIN Comments AS c ON u.Id = c.UserId
    WHERE u.CreationDate >= '2020-01-01'
      AND u.Reputation > 500
    GROUP BY
        u.Id, u.DisplayName, u.Reputation, u.CreationDate, u.LastAccessDate, u.Views, u.UpVotes, u.DownVotes, u.Location
),
QuestionDetails AS (
    SELECT
        q.Id AS QuestionId,
        q.Title AS QuestionTitle,
        q.CreationDate AS QuestionCreationDate,
        q.Score AS QuestionScore,
        q.ViewCount,
        q.AnswerCount,
        q.OwnerUserId,
        q.AcceptedAnswerId,
        q.LastActivityDate,
        q.Tags,
        (LENGTH(q.Body) - LENGTH(REPLACE(q.Body, '<pre>', ''))) / LENGTH('<pre>') AS CodeBlockCount,
        CASE
            WHEN q.Tags LIKE '%<sql>%' OR q.Tags LIKE '%<database>%' THEN 'Database'
            WHEN q.Tags LIKE '%<python>%' OR q.Tags LIKE '%<java>%' THEN 'Programming'
            WHEN q.Tags LIKE '%<javascript>%' OR q.Tags LIKE '%<html>%' OR q.Tags LIKE '%<css>%' THEN 'Web Development'
            ELSE 'Other'
        END AS TagCategory,
        CAST(EXTRACT(EPOCH FROM (q.LastActivityDate - q.CreationDate)) / 3600 AS INT) AS HoursUntilLastActivity
    FROM Posts AS q
    WHERE q.PostTypeId = 1
      AND q.ViewCount > 100
      AND q.Tags IS NOT NULL
),
AnswerAggregates AS (
    SELECT
        a.ParentId AS QuestionId,
        COUNT(a.Id) AS TotalAnswers,
        AVG(a.Score) AS AvgAnswerScore,
        MAX(a.Score) AS TopAnswerScore,
        (SELECT COUNT(*) FROM Posts AS sa WHERE sa.ParentId = a.ParentId AND sa.OwnerUserId = (SELECT qd.OwnerUserId FROM QuestionDetails AS qd WHERE qd.QuestionId = a.ParentId)) AS SelfAnswers,
        PERCENTILE_CONT(0.5) WITHIN GROUP (ORDER BY a.Score) OVER (PARTITION BY a.ParentId) AS MedianAnswerScore,
        ROW_NUMBER() OVER (PARTITION BY a.ParentId ORDER BY a.Score DESC, a.CreationDate ASC) AS AnswerRankPerQuestion
    FROM Posts AS a
    WHERE a.PostTypeId = 2
    GROUP BY a.ParentId
),
PostHistoryTimeline AS (
    SELECT
        ph.PostId,
        ph.PostHistoryTypeId,
        ph.CreationDate AS HistoryDate,
        ph.UserId AS HistoryUserId,
        ROW_NUMBER() OVER (PARTITION BY ph.PostId ORDER BY ph.CreationDate ASC) AS EventSequence,
        CAST(EXTRACT(EPOCH FROM (ph.CreationDate - LAG(ph.CreationDate, 1, ph.CreationDate) OVER (PARTITION BY ph.PostId ORDER BY ph.CreationDate ASC))) / 60 AS INT) AS MinutesSincePreviousEvent,
        CASE
            WHEN ph.PostHistoryTypeId = 10 THEN 'Closed'
            WHEN ph.PostHistoryTypeId = 11 THEN 'Reopened'
            WHEN ph.PostHistoryTypeId = 12 THEN 'Deleted'
            WHEN ph.PostHistoryTypeId = 13 THEN 'Undeleted'
            WHEN ph.PostHistoryTypeId = 19 THEN 'Protected'
            WHEN ph.PostHistoryTypeId = 20 THEN 'Unprotected'
            ELSE 'Other'
        END AS HistoryEventType,
        cr.Name AS CloseReasonName,
        ph.Text AS HistoryTextContent
    FROM PostHistory AS ph
    LEFT JOIN CloseReasonTypes AS cr ON
        ph.PostHistoryTypeId = 10
        AND ph.Comment IS NOT NULL
        AND (CASE WHEN ph.Comment ~ '^[0-9]+$' THEN CAST(ph.Comment AS SMALLINT) ELSE NULL END) = cr.Id
    WHERE ph.PostHistoryTypeId IN (10, 11, 12, 13, 19, 20)
),
LinkedPostAnalysis AS (
    SELECT
        pl.PostId,
        MAX(CASE WHEN lt.Name = 'Linked' THEN 1 ELSE 0 END) AS HasLinkedPosts,
        MAX(CASE WHEN lt.Name = 'Duplicate' THEN 1 ELSE 0 END) AS IsDuplicateOfOther,
        COUNT(DISTINCT pl.RelatedPostId) AS TotalRelatedPosts,
        COALESCE(SUM(CASE WHEN v.VoteTypeId = 2 THEN 1 ELSE 0 END), 0) AS RelatedPostUpvotes,
        COALESCE(SUM(CASE WHEN v.VoteTypeId = 3 THEN 1 ELSE 0 END), 0) AS RelatedPostDownvotes,
        MAX(CASE WHEN EXISTS (SELECT 1 FROM Votes AS rv WHERE rv.PostId = pl.RelatedPostId AND rv.VoteTypeId = 4) THEN 1 ELSE 0 END) AS HasOffensiveRelatedPost
    FROM PostLinks AS pl
    JOIN LinkTypes AS lt ON pl.LinkTypeId = lt.Id
    LEFT JOIN Posts AS rp ON pl.RelatedPostId = rp.Id
    LEFT JOIN Votes AS v ON rp.Id = v.PostId
    GROUP BY pl.PostId
),
TagWikiStatus AS (
    SELECT
        t.TagName,
        t.Count AS TagUseCount,
        CASE WHEN twiki.Id IS NOT NULL THEN 1 ELSE 0 END AS HasWikiPost,
        CASE WHEN texcerpt.Id IS NOT NULL THEN 1 ELSE 0 END AS HasExcerptPost,
        DENSE_RANK() OVER (ORDER BY t.Count DESC) AS TagPopularityRank
    FROM Tags AS t
    LEFT JOIN Posts AS twiki ON t.WikiPostId = twiki.Id
    LEFT JOIN Posts AS texcerpt ON t.ExcerptPostId = texcerpt.Id
    WHERE t.Count > 500
),
HighlyActiveQuestions AS (
    SELECT
        q.Id AS PostId
    FROM Posts AS q
    WHERE q.PostTypeId = 1
      AND q.Score > 75
      AND q.AnswerCount > 10
      AND q.ViewCount > 50000
),
RecentlyClosedQuestions AS (
    SELECT
        ph.PostId
    FROM PostHistory AS ph
    WHERE ph.PostHistoryTypeId = 10
      AND ph.CreationDate > '2023-01-01'
),
ExclusiveEliteQuestions AS (
    SELECT PostId FROM HighlyActiveQuestions
    EXCEPT
    SELECT PostId FROM RecentlyClosedQuestions
)
SELECT
    ue.UserName,
    ue.Reputation,
    ue.QuestionsAsked,
    ue.AnswersPosted,
    qd.QuestionTitle,
    qd.QuestionScore,
    qd.ViewCount AS QuestionViewCount,
    qd.HoursUntilLastActivity,
    qd.CodeBlockCount,
    COALESCE(aa.AvgAnswerScore, 0.0) AS AverageAnswerScore,
    COALESCE(aa.TopAnswerScore, 0) AS HighestAnswerScore,
    COALESCE(aa.SelfAnswers, 0) AS SelfAnswersByQuestionOwner,
    COALESCE(lpa.TotalRelatedPosts, 0) AS NumberOfLinkedPosts,
    COALESCE(lpa.IsDuplicateOfOther, 0) AS IsKnownDuplicate,
    COALESCE(lpa.RelatedPostUpvotes, 0) AS SumUpvotesOnRelatedPosts,
    COALESCE(lpa.HasOffensiveRelatedPost, 0) AS HasOffensiveLinkedContent,
    ph_open.HistoryDate AS LastReopenedDate,
    ph_close.HistoryDate AS LastClosedDate,
    ph_close.CloseReasonName,
    tw_user_top.HasWikiPost AS TopTagHasWiki,
    tw_user_top.TagName AS TopTagForUser,
    CASE
        WHEN ee.PostId IS NOT NULL THEN 'Elite'
        ELSE 'Standard'
    END AS EliteQuestionStatus,
    (ue.Reputation * (ue.QuestionsAsked + ue.AnswersPosted + ue.CommentsMade) * COALESCE(qd.QuestionScore, 1)) / NULLIF(qd.ViewCount + 1, 0) AS UserPostEffectivenessScore,
    (
        SELECT COUNT(DISTINCT v.UserId)
        FROM Votes AS v
        WHERE v.PostId = qd.QuestionId
          AND v.VoteTypeId = 5
          AND v.UserId != ue.UserId
    ) AS OtherUserFavoritesCount,
    CASE
        WHEN qd.AcceptedAnswerId IS NOT NULL AND aa.TopAnswerScore >= 10 THEN 'HighQualityAcceptedAnswer'
        WHEN qd.AcceptedAnswerId IS NOT NULL THEN 'AcceptedAnswer'
        WHEN qd.AnswerCount > 0 AND COALESCE(aa.AvgAnswerScore, 0) >= 5 THEN 'GoodAnswersButNoAccept'
        WHEN qd.AnswerCount = 0 OR qd.AnswerCount IS NULL THEN 'NoAnswers'
        ELSE 'OtherAnswerStatus'
    END AS QuestionResolutionStatus,
    LAG(qd.QuestionCreationDate, 1, ue.UserCreationDate) OVER (PARTITION BY ue.UserId ORDER BY qd.QuestionCreationDate ASC) AS PreviousQuestionDate,
    ABS(CAST(EXTRACT(EPOCH FROM (qd.QuestionCreationDate - ph_close.HistoryDate)) / (3600*24) AS INT)) AS DaysToClose,
    SUBSTRING(qd.Tags, POSITION('<' IN qd.Tags) + 1, POSITION('>' IN qd.Tags) - POSITION('<' IN qd.Tags) - 1) AS FirstTag
FROM UserEngagement AS ue
LEFT JOIN QuestionDetails AS qd ON ue.UserId = qd.OwnerUserId
LEFT JOIN AnswerAggregates AS aa ON qd.QuestionId = aa.QuestionId
LEFT JOIN LinkedPostAnalysis AS lpa ON qd.QuestionId = lpa.PostId
LEFT JOIN (
    SELECT PostId, HistoryDate, CloseReasonName
    FROM (SELECT PostId, HistoryDate, CloseReasonName, ROW_NUMBER() OVER (PARTITION BY PostId ORDER BY HistoryDate DESC) AS rn FROM PostHistoryTimeline WHERE HistoryEventType = 'Closed') AS sub
    WHERE rn = 1
) AS ph_close ON qd.QuestionId = ph_close.PostId
LEFT JOIN (
    SELECT PostId, HistoryDate
    FROM (SELECT PostId, HistoryDate, ROW_NUMBER() OVER (PARTITION BY PostId ORDER BY HistoryDate DESC) AS rn FROM PostHistoryTimeline WHERE HistoryEventType = 'Reopened') AS sub
    WHERE rn = 1
) AS ph_open ON qd.QuestionId = ph_open.PostId
LEFT JOIN (
    SELECT
        ph_user.UserId,
        tw.TagName,
        tw.HasWikiPost,
        ROW_NUMBER() OVER (PARTITION BY ph_user.UserId ORDER BY COUNT(DISTINCT ph_user.PostId) DESC, tw.TagName) AS rn
    FROM PostHistory AS ph_user
    JOIN Posts AS p_tag ON ph_user.PostId = p_tag.Id
    JOIN TagWikiStatus AS tw ON p_tag.Tags LIKE '%' || tw.TagName || '%'
    WHERE ph_user.UserId IS NOT NULL
      AND p_tag.Tags IS NOT NULL
      AND ph_user.PostHistoryTypeId IN (1, 3, 4, 6)
    GROUP BY ph_user.UserId, tw.TagName, tw.HasWikiPost
    HAVING ROW_NUMBER() OVER (PARTITION BY ph_user.UserId ORDER BY COUNT(DISTINCT ph_user.PostId) DESC, tw.TagName) = 1
) AS tw_user_top ON ue.UserId = tw_user_top.UserId
LEFT JOIN ExclusiveEliteQuestions AS ee ON qd.QuestionId = ee.PostId
WHERE ue.QuestionsAsked > 0
  AND (qd.QuestionTitle IS NOT NULL OR ue.AnswersPosted > 0)
  AND (qd.Tags IS NOT NULL AND qd.Tags NOT LIKE '%<meta>%')
  AND (aa.AvgAnswerScore IS NULL OR aa.AvgAnswerScore >= 0)
  AND (ph_close.HistoryDate IS NULL OR CAST(EXTRACT(EPOCH FROM (ph_close.HistoryDate - qd.QuestionCreationDate)) / (3600*24) AS INT) > 7)
  AND (ue.UserLocation IS NULL OR ue.UserLocation NOT LIKE '%Mars%')
ORDER BY UserPostEffectivenessScore DESC, ue.Reputation DESC, qd.QuestionCreationDate DESC
LIMIT 200;
