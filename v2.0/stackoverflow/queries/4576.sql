WITH RankedQuestions AS (
    SELECT
        p.Id AS QuestionId,
        p.Title,
        p.OwnerUserId,
        p.CreationDate AS QuestionCreationDate,
        u.DisplayName AS QuestionOwnerDisplayName,
        p.Tags,
        ROW_NUMBER() OVER(PARTITION BY p.OwnerUserId ORDER BY p.CreationDate DESC) AS rn
    FROM Posts p
    JOIN Users u ON p.OwnerUserId = u.Id
    WHERE p.PostTypeId = 1 AND p.OwnerUserId IS NOT NULL
),
AnswerQuality AS (
    SELECT
        a.ParentId AS QuestionId,
        COUNT(a.Id) AS TotalAnswers,
        SUM(CASE WHEN a.Score > 0 THEN 1 ELSE 0 END) AS PositiveScoreAnswers,
        AVG(a.Score) AS AverageAnswerScore,
        MAX(a.Score) AS MaxAnswerScore,
        MIN(a.Score) AS MinAnswerScore,
        SUM(CASE WHEN a.Id = p_q.AcceptedAnswerId THEN 1 ELSE 0 END) AS IsAcceptedAnswerPresent
    FROM Posts a
    JOIN Posts p_q ON a.ParentId = p_q.Id
    WHERE a.PostTypeId = 2 AND a.ParentId IS NOT NULL
    GROUP BY a.ParentId
),
TagPopularity AS (
    SELECT
        LOWER(TRIM(t.TagName)) AS TagName,
        t.Count AS TagCount,
        t.Id AS TagId,
        t.IsModeratorOnly
    FROM Tags t
    WHERE COALESCE(t.IsModeratorOnly, FALSE) = FALSE
),
UserActivitySummary AS (
    SELECT
        u.Id AS UserId,
        u.DisplayName,
        u.Reputation,
        u.CreationDate,
        COUNT(DISTINCT ph.PostId) AS PostHistoryCount,
        SUM(CASE WHEN ph.PostHistoryTypeId IN (2, 5) THEN 1 ELSE 0 END) AS BodyEditCount,
        MAX(u.LastAccessDate) AS MaxLastAccessDate
    FROM Users u
    LEFT JOIN PostHistory ph ON u.Id = ph.UserId
    WHERE u.Id > 0
    GROUP BY u.Id, u.DisplayName, u.Reputation, u.CreationDate
),
RecentHotQuestions AS (
    SELECT
        p.Id AS QuestionId,
        p.Title,
        p.ViewCount,
        p.FavoriteCount,
        p.CreationDate,
        ph.CreationDate AS HotQuestionDate
    FROM Posts p
    JOIN PostHistory ph ON p.Id = ph.PostId
    WHERE p.PostTypeId = 1 AND ph.PostHistoryTypeId = 52
      AND ph.CreationDate >= (cast('2024-10-01' as date) - INTERVAL '30 days')
)
SELECT
    rq.QuestionId,
    rq.Title AS QuestionTitle,
    rq.QuestionOwnerDisplayName,
    rq.QuestionCreationDate,
    COALESCE(aq.TotalAnswers, 0) AS TotalAnswers,
    COALESCE(aq.PositiveScoreAnswers, 0) AS PositiveScoreAnswers,
    aq.AverageAnswerScore,
    aq.MaxAnswerScore,
    aq.MinAnswerScore,
    CASE WHEN COALESCE(aq.IsAcceptedAnswerPresent, 0) > 0 THEN 'Yes' ELSE 'No' END AS HasAcceptedAnswer,
    (SELECT COUNT(*) FROM Comments c WHERE c.PostId = rq.QuestionId AND c.UserId IS NOT NULL) AS CommentCountOnQuestion,
    CASE
        WHEN rq.rn <= 5 THEN 'Top 5 Recent by Owner'
        WHEN rq.rn <= 10 THEN 'Next 5 Recent by Owner'
        ELSE 'Other Recent by Owner'
    END AS OwnerRecentRank,
    COUNT(DISTINCT pl.Id) AS RelatedPostLinkCount,
    (SELECT COUNT(*) FROM Posts p_a WHERE p_a.ParentId = rq.QuestionId AND p_a.OwnerUserId = rq.OwnerUserId) AS AnswersBySameOwner,
    STRING_AGG(DISTINCT tp.TagName, ',') AS PopularTags,
    MAX(rhq.HotQuestionDate) AS LastHotNetworkDate
FROM RankedQuestions rq
LEFT JOIN AnswerQuality aq ON rq.QuestionId = aq.QuestionId
LEFT JOIN PostLinks pl ON rq.QuestionId = pl.PostId OR rq.QuestionId = pl.RelatedPostId
LEFT JOIN TagPopularity tp ON POSITION(',' || tp.TagName || ',' IN ',' || LOWER(COALESCE(rq.Tags, '')) || ',') > 0
LEFT JOIN RecentHotQuestions rhq ON rq.QuestionId = rhq.QuestionId
GROUP BY
    rq.QuestionId,
    rq.Title,
    rq.OwnerUserId,
    rq.QuestionOwnerDisplayName,
    rq.QuestionCreationDate,
    rq.rn,
    aq.TotalAnswers,
    aq.PositiveScoreAnswers,
    aq.AverageAnswerScore,
    aq.MaxAnswerScore,
    aq.MinAnswerScore,
    aq.IsAcceptedAnswerPresent
HAVING COUNT(DISTINCT pl.Id) > 0 OR rq.QuestionId IN (SELECT PostId FROM Comments WHERE UserId IS NOT NULL)
ORDER BY rq.QuestionCreationDate DESC
LIMIT 100;