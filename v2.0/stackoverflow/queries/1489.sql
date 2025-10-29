WITH RecentActiveUsers AS (
    SELECT
        u.Id AS UserId,
        u.DisplayName,
        u.Reputation,
        u.UpVotes,
        u.DownVotes,
        u.CreationDate AS UserCreationDate,
        u.LastAccessDate,
        COALESCE(u.Location, 'Unknown') AS UserLocation,
        CASE
            WHEN (u.UpVotes + u.DownVotes) > 0
            THEN CAST(u.UpVotes AS NUMERIC) / (u.UpVotes + u.DownVotes)
            ELSE 0.0
        END AS NetVoteRatio,
        COUNT(DISTINCT b.Id) FILTER (WHERE b.Class = 1) AS GoldBadges,
        COUNT(DISTINCT b.Id) FILTER (WHERE b.Class = 2) AS SilverBadges,
        COUNT(DISTINCT b.Id) FILTER (WHERE b.Class = 3) AS BronzeBadges
    FROM
        Users u
    LEFT JOIN Badges b ON u.Id = b.UserId
    WHERE
        u.LastAccessDate >= CAST('2024-10-01 12:34:56' AS TIMESTAMP) - INTERVAL '6 months'
        AND u.Reputation >= 1000
    GROUP BY
        u.Id, u.DisplayName, u.Reputation, u.UpVotes, u.DownVotes, u.CreationDate, u.LastAccessDate, u.Location
),
QuestionEventSummary AS (
    SELECT
        p.Id AS PostId,
        p.OwnerUserId,
        p.CreationDate AS QuestionCreationDate,
        p.AcceptedAnswerId,
        p.Score AS QuestionScore,
        p.ViewCount AS QuestionViewCount,
        p.AnswerCount AS QuestionAnswerCount,
        p.CommentCount AS QuestionCommentCount,
        p.FavoriteCount AS QuestionFavoriteCount,
        p.ClosedDate AS QuestionClosedDate,
        p.Title AS QuestionTitle,
        p.Tags AS QuestionTagsRaw,
        STRING_TO_ARRAY(SUBSTRING(p.Tags FROM 2 FOR LENGTH(p.Tags)-2), '><') AS QuestionTagsArray,
        ph_closed.CreationDate AS ClosedEventDate,
        ph_closed.Comment AS CloseReasonComment,
        clrt.Name AS CloseReasonTypeName,
        EXTRACT(EPOCH FROM (ph_closed.CreationDate - p.CreationDate)) / 3600.0 AS HoursToClose,
        (SELECT COUNT(DISTINCT pl_dup.RelatedPostId)
         FROM PostLinks pl_dup
         WHERE pl_dup.PostId = p.Id AND pl_dup.LinkTypeId = 3) AS DuplicateLinkCount,
        MAX(CASE WHEN ph.PostHistoryTypeId IN (4, 5, 6) THEN ph.CreationDate ELSE NULL END) AS LastEditDateHistory
    FROM
        Posts p
    LEFT JOIN PostHistory ph_closed ON p.Id = ph_closed.PostId
        AND ph_closed.PostHistoryTypeId = 10
    LEFT JOIN CloseReasonTypes clrt ON (ph_closed.Comment IS NOT NULL AND ph_closed.PostHistoryTypeId = 10 AND clrt.Id = CAST(ph_closed.Comment AS SMALLINT))
    LEFT JOIN PostHistory ph ON p.Id = ph.PostId
    WHERE
        p.PostTypeId = 1
    GROUP BY
        p.Id, p.OwnerUserId, p.CreationDate, p.AcceptedAnswerId, p.Score, p.ViewCount, p.AnswerCount, p.CommentCount, p.FavoriteCount, p.ClosedDate, p.Title, p.Tags,
        ph_closed.CreationDate, ph_closed.Comment, clrt.Name
),
AnswerPerformance AS (
    SELECT
        a.Id AS AnswerId,
        a.ParentId AS QuestionId,
        a.OwnerUserId AS AnswerOwnerUserId,
        a.CreationDate AS AnswerCreationDate,
        a.Score AS AnswerScore,
        a.CommentCount AS AnswerCommentCount,
        p.AcceptedAnswerId,
        -- compute accepted answer date by finding the posthistory entry where an answer was accepted
        MIN(CASE WHEN ph_accept.PostHistoryTypeId = 22 THEN ph_accept.CreationDate ELSE NULL END) AS AcceptedAnswerDate,
        EXTRACT(EPOCH FROM (MIN(CASE WHEN ph_accept.PostHistoryTypeId = 22 THEN ph_accept.CreationDate ELSE NULL END) - a.CreationDate)) / 3600.0 AS AnswerLagHours,
        (SELECT SUM(v.BountyAmount) FROM Votes v WHERE v.PostId = a.Id AND v.VoteTypeId = 9 AND v.BountyAmount IS NOT NULL) AS BountyReceived
    FROM
        Posts a
    INNER JOIN Posts p ON a.ParentId = p.Id
    LEFT JOIN PostHistory ph_accept ON p.Id = ph_accept.PostId AND ph_accept.PostHistoryTypeId = 22
    WHERE
        a.PostTypeId = 2
    GROUP BY
        a.Id, a.ParentId, a.OwnerUserId, a.CreationDate, a.Score, a.CommentCount, p.AcceptedAnswerId
),
UserPostActivity AS (
    SELECT
        qes.OwnerUserId AS UserId,
        COUNT(DISTINCT qes.PostId) AS QuestionsAsked,
        SUM(qes.QuestionScore) AS TotalQuestionScore,
        AVG(qes.HoursToClose) FILTER (WHERE qes.QuestionClosedDate IS NOT NULL) AS AvgCloseTimeHours,
        COUNT(qes.PostId) FILTER (WHERE qes.AcceptedAnswerId IS NOT NULL) AS QuestionsWithAcceptedAnswer,
        COALESCE(SUM(ap.AnswerScore), 0) AS TotalAnswerScore,
        COALESCE(COUNT(DISTINCT ap.AnswerId), 0) AS AnswersProvided,
        NTILE(4) OVER (ORDER BY SUM(qes.QuestionScore) DESC) AS QuestionScoreQuartile
    FROM
        QuestionEventSummary qes
    LEFT JOIN AnswerPerformance ap ON qes.AcceptedAnswerId = ap.AnswerId AND qes.PostId = ap.QuestionId
    GROUP BY
        qes.OwnerUserId
)
SELECT * FROM (
    SELECT
        rau.UserId,
        COALESCE(rau.DisplayName, 'Anonymous User') AS UserDisplayName,
        rau.Reputation,
        rau.NetVoteRatio,
        rau.GoldBadges,
        rau.SilverBadges,
        rau.BronzeBadges,
        upa.QuestionsAsked,
        upa.TotalQuestionScore,
        upa.AnswersProvided,
        upa.TotalAnswerScore,
        upa.AvgCloseTimeHours,
        upa.QuestionsWithAcceptedAnswer,
        (SELECT AVG(ap_sub.AnswerLagHours)
         FROM AnswerPerformance ap_sub
         JOIN Posts p_sub ON ap_sub.QuestionId = p_sub.Id
         WHERE p_sub.OwnerUserId = rau.UserId AND p_sub.AcceptedAnswerId IS NOT NULL AND p_sub.AcceptedAnswerId = ap_sub.AnswerId) AS AvgAcceptedAnswerTimeForUser,
        SUM(CASE WHEN qes.QuestionTagsRaw LIKE '%<sql>%' THEN 1 ELSE 0 END) AS SqlQuestionsCount,
        SUM(CASE WHEN qes.QuestionClosedDate IS NOT NULL AND qes.CloseReasonTypeName LIKE '%Duplicate%' THEN 1 ELSE 0 END) AS DuplicateClosedQuestions,
        AVG(qes.QuestionScore) AS AvgQuestionScore,
        RANK() OVER (ORDER BY rau.Reputation DESC, upa.QuestionsAsked DESC) AS UserRankByActivity,
        NTILE(5) OVER (PARTITION BY rau.UserLocation ORDER BY rau.Reputation DESC) AS LocationReputationQuintile,
        SUM(CASE WHEN POSITION('benchmark' IN LOWER(qes.QuestionTitle)) > 0 OR qes.QuestionTagsRaw LIKE '%<performance>%' THEN 1 ELSE 0 END) AS BenchmarkPerformanceQuestionCount,
        SUM(qes.DuplicateLinkCount) AS TotalDuplicateLinksFromQuestions,
        'Mostly_Open_Questions_User' AS UserCategory,
        NULLIF(SUM(CASE WHEN qes.QuestionClosedDate IS NULL THEN 1 ELSE 0 END), 0) AS OpenQuestionsCount,
        NULLIF(SUM(CASE WHEN qes.QuestionClosedDate IS NOT NULL THEN 1 ELSE 0 END), 0) AS ClosedQuestionsCount,
        CAST(NULL AS NUMERIC) AS OffTopicClosedQuestionsRatio
    FROM
        RecentActiveUsers rau
    INNER JOIN UserPostActivity upa ON rau.UserId = upa.UserId
    LEFT JOIN QuestionEventSummary qes ON rau.UserId = qes.OwnerUserId
    GROUP BY
        rau.UserId, rau.DisplayName, rau.Reputation, rau.NetVoteRatio, rau.GoldBadges, rau.SilverBadges, rau.BronzeBadges,
        upa.QuestionsAsked, upa.TotalQuestionScore, upa.AnswersProvided, upa.TotalAnswerScore,
        upa.AvgCloseTimeHours, upa.QuestionsWithAcceptedAnswer, rau.UserLocation
    HAVING
        COUNT(DISTINCT qes.PostId) > 5
        AND (CAST(SUM(CASE WHEN qes.QuestionClosedDate IS NULL THEN 1 ELSE 0 END) AS NUMERIC) / NULLIF(COUNT(DISTINCT qes.PostId), 0)) >= 0.7
) AS OpenQuestionUsers

UNION ALL

SELECT * FROM (
    SELECT
        rau.UserId,
        COALESCE(rau.DisplayName, 'Anonymous User') AS UserDisplayName,
        rau.Reputation,
        rau.NetVoteRatio,
        rau.GoldBadges,
        rau.SilverBadges,
        rau.BronzeBadges,
        upa.QuestionsAsked,
        upa.TotalQuestionScore,
        upa.AnswersProvided,
        upa.TotalAnswerScore,
        upa.AvgCloseTimeHours,
        upa.QuestionsWithAcceptedAnswer,
        (SELECT AVG(ap_sub.AnswerLagHours)
         FROM AnswerPerformance ap_sub
         JOIN Posts p_sub ON ap_sub.QuestionId = p_sub.Id
         WHERE p_sub.OwnerUserId = rau.UserId AND p_sub.AcceptedAnswerId IS NOT NULL AND p_sub.AcceptedAnswerId = ap_sub.AnswerId) AS AvgAcceptedAnswerTimeForUser,
        SUM(CASE WHEN qes.QuestionTagsRaw LIKE '%<java>%' THEN 1 ELSE 0 END) AS JavaQuestionsCount,
        SUM(CASE WHEN qes.QuestionClosedDate IS NOT NULL AND qes.CloseReasonTypeName LIKE '%Off-topic%' THEN 1 ELSE 0 END) AS OffTopicClosedQuestions,
        AVG(qes.QuestionScore) AS AvgQuestionScore,
        RANK() OVER (ORDER BY rau.Reputation DESC, upa.TotalAnswerScore DESC) AS UserRankByActivity,
        NTILE(5) OVER (PARTITION BY rau.UserLocation ORDER BY upa.TotalAnswerScore DESC) AS LocationReputationQuintile,
        SUM(CASE WHEN POSITION('bug' IN LOWER(qes.QuestionTitle)) > 0 OR qes.QuestionTagsRaw LIKE '%<debugging>%' THEN 1 ELSE 0 END) AS BugDebuggingQuestionCount,
        SUM(qes.DuplicateLinkCount) AS TotalDuplicateLinksFromQuestions,
        'Mostly_Closed_Questions_User' AS UserCategory,
        NULLIF(SUM(CASE WHEN qes.QuestionClosedDate IS NULL THEN 1 ELSE 0 END), 0) AS OpenQuestionsCount,
        NULLIF(SUM(CASE WHEN qes.QuestionClosedDate IS NOT NULL THEN 1 ELSE 0 END), 0) AS ClosedQuestionsCount,
        (CAST(SUM(CASE WHEN qes.QuestionClosedDate IS NOT NULL AND qes.CloseReasonTypeName LIKE '%Off-topic%' THEN 1 ELSE 0 END) AS NUMERIC) / NULLIF(SUM(CASE WHEN qes.QuestionClosedDate IS NOT NULL THEN 1 ELSE 0 END), 0)) AS OffTopicClosedQuestionsRatio
    FROM
        RecentActiveUsers rau
    INNER JOIN UserPostActivity upa ON rau.UserId = upa.UserId
    LEFT JOIN QuestionEventSummary qes ON rau.UserId = qes.OwnerUserId
    GROUP BY
        rau.UserId, rau.DisplayName, rau.Reputation, rau.NetVoteRatio, rau.GoldBadges, rau.SilverBadges, rau.BronzeBadges,
        upa.QuestionsAsked, upa.TotalQuestionScore, upa.AnswersProvided, upa.TotalAnswerScore,
        upa.AvgCloseTimeHours, upa.QuestionsWithAcceptedAnswer, rau.UserLocation
    HAVING
        COUNT(DISTINCT qes.PostId) > 5
        AND (CAST(SUM(CASE WHEN qes.QuestionClosedDate IS NOT NULL THEN 1 ELSE 0 END) AS NUMERIC) / NULLIF(COUNT(DISTINCT qes.PostId), 0)) >= 0.7
) AS ClosedQuestionUsers
ORDER BY UserCategory ASC, UserRankByActivity ASC
LIMIT 200;