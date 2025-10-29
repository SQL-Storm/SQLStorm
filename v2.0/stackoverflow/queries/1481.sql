-- {"query": "1481.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gemini-2.5-flash", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2111, "output_tokens": 2772}
WITH UserActivitySummary AS (
    SELECT
        u.Id AS UserId,
        u.DisplayName,
        u.Reputation,
        u.CreationDate AS UserCreationDate,
        COUNT(DISTINCT p.Id) AS TotalPosts,
        COUNT(DISTINCT CASE WHEN p.PostTypeId = (SELECT Id FROM PostTypes WHERE Name = 'Question') THEN p.Id END) AS TotalQuestions,
        COUNT(DISTINCT CASE WHEN p.PostTypeId = (SELECT Id FROM PostTypes WHERE Name = 'Answer') THEN p.Id END) AS TotalAnswers,
        COUNT(DISTINCT c.Id) AS TotalComments,
        SUM(CASE WHEN v.VoteTypeId = (SELECT Id FROM VoteTypes WHERE Name = 'UpMod') THEN 1 ELSE 0 END) AS TotalUpVotesGiven,
        SUM(CASE WHEN v.VoteTypeId = (SELECT Id FROM VoteTypes WHERE Name = 'DownMod') THEN 1 ELSE 0 END) AS TotalDownVotesGiven,
        SUM(COALESCE(p.FavoriteCount, 0)) AS TotalQuestionFavoritesReceived,
        MAX(u.LastAccessDate) AS LastUserActivityDate
    FROM
        Users u
    LEFT JOIN Posts p ON u.Id = p.OwnerUserId
    LEFT JOIN Comments c ON u.Id = c.UserId
    LEFT JOIN Votes v ON u.Id = v.UserId
    GROUP BY
        u.Id, u.DisplayName, u.Reputation, u.CreationDate
    HAVING
        COUNT(DISTINCT p.Id) > 5 AND u.Reputation > 500
),
PostHistoricalEditMetrics AS (
    SELECT
        ph.PostId,
        COUNT(ph.Id) AS TotalHistoryEntries,
        COUNT(DISTINCT ph.UserId) AS UniqueEditors,
        MAX(ph.CreationDate) AS LastEditDate_History,
        SUM(CASE WHEN ph.PostHistoryTypeId IN (
            (SELECT Id FROM PostHistoryTypes WHERE Name = 'Title'),
            (SELECT Id FROM PostHistoryTypes WHERE Name = 'Body'),
            (SELECT Id FROM PostHistoryTypes WHERE Name = 'Tags')
        ) THEN 1 ELSE 0 END) AS MajorEditCount,
        SUM(CASE WHEN ph.PostHistoryTypeId = (SELECT Id FROM PostHistoryTypes WHERE Name = 'Post Closed') THEN 1 ELSE 0 END) AS CloseHistoryCount,
        SUM(CASE WHEN ph.PostHistoryTypeId = (SELECT Id FROM PostHistoryTypes WHERE Name = 'Post Reopened') THEN 1 ELSE 0 END) AS ReopenHistoryCount
    FROM
        PostHistory ph
    WHERE
        ph.UserId IS NOT NULL
    GROUP BY
        ph.PostId
),
QuestionDetailedMetrics AS (
    SELECT
        q.Id AS QuestionId,
        q.OwnerUserId,
        q.Title AS QuestionTitle,
        q.CreationDate AS QuestionCreationDate,
        q.Score AS QuestionScore,
        q.ViewCount,
        q.AnswerCount,
        q.CommentCount AS QuestionCommentCount,
        q.FavoriteCount AS QuestionFavoriteCount,
        q.Tags,
        q.ClosedDate,
        CASE WHEN q.AcceptedAnswerId IS NOT NULL THEN TRUE ELSE FALSE END AS HasAcceptedAnswer,
        COALESCE(aa.Score, 0) AS AcceptedAnswerScore,
        aa_user.Reputation AS AcceptedAnswerOwnerReputation,
        EXTRACT(EPOCH FROM (CAST('2024-10-01 12:34:56' AS timestamp) - q.CreationDate)) / (3600 * 24) AS QuestionAgeDays,
        (
            SELECT AVG(ans.Score)
            FROM Posts ans
            WHERE ans.ParentId = q.Id AND ans.PostTypeId = (SELECT Id FROM PostTypes WHERE Name = 'Answer')
        ) AS AvgAnswerScore,
        (
            SELECT COUNT(DISTINCT cmt.UserId)
            FROM Comments cmt
            WHERE cmt.PostId = q.Id AND cmt.UserId IS NOT NULL
        ) AS UniqueCommentersOnQuestion,
        cr.Name AS CloseReasonName
    FROM
        Posts q
    LEFT JOIN Posts aa ON q.AcceptedAnswerId = aa.Id AND aa.PostTypeId = (SELECT Id FROM PostTypes WHERE Name = 'Answer')
    LEFT JOIN Users aa_user ON aa.OwnerUserId = aa_user.Id
    LEFT JOIN PostHistory ph_close ON q.Id = ph_close.PostId
        AND ph_close.PostHistoryTypeId = (SELECT Id FROM PostHistoryTypes WHERE Name = 'Post Closed')
    LEFT JOIN CloseReasonTypes cr ON ph_close.Comment = CAST(cr.Id AS varchar)
    WHERE
        q.PostTypeId = (SELECT Id FROM PostTypes WHERE Name = 'Question')
),
AggregatedTagStats AS (
    SELECT
        Tag.TagName,
        COUNT(DISTINCT q.QuestionId) AS QuestionsWithTag,
        SUM(q.QuestionScore) AS TotalTagScore,
        SUM(q.ViewCount) AS TotalTagViews,
        AVG(q.QuestionScore) AS AverageTagQuestionScore,
        (SUM(q.ViewCount) * 1.0 / NULLIF(COUNT(DISTINCT q.QuestionId), 0)) AS AvgViewsPerQuestionWithTag
    FROM
        QuestionDetailedMetrics q,
        UNNEST(string_to_array(SUBSTRING(q.Tags FROM 2 FOR (CHAR_LENGTH(q.Tags) - 2)), '><')) AS Tag(TagName)
    GROUP BY
        Tag.TagName
    HAVING
        COUNT(DISTINCT q.QuestionId) > 50 AND SUM(q.ViewCount) > 10000
),
BadgeCounts AS (
    SELECT
        b.UserId,
        COUNT(CASE WHEN b.Class = 1 THEN 1 END) AS GoldBadges,
        COUNT(CASE WHEN b.Class = 2 THEN 1 END) AS SilverBadges,
        COUNT(CASE WHEN b.Class = 3 THEN 1 END) AS BronzeBadges,
        COUNT(DISTINCT b.Name) AS UniqueBadgeTypes
    FROM
        Badges b
    GROUP BY
        b.UserId
)
SELECT
    uas.UserId,
    uas.DisplayName,
    uas.Reputation,
    uas.TotalQuestions,
    uas.TotalAnswers,
    COALESCE(bc.GoldBadges, 0) AS GoldBadges,
    COALESCE(bc.SilverBadges, 0) AS SilverBadges,
    COALESCE(bc.BronzeBadges, 0) AS BronzeBadges,
    qdm.QuestionId,
    qdm.QuestionTitle,
    qdm.QuestionCreationDate,
    qdm.QuestionScore,
    qdm.ViewCount,
    qdm.AnswerCount,
    qdm.QuestionFavoriteCount,
    qdm.QuestionAgeDays,
    qdm.HasAcceptedAnswer,
    qdm.AcceptedAnswerScore,
    qdm.AcceptedAnswerOwnerReputation,
    COALESCE(qdm.AvgAnswerScore, 0.0) AS AvgAnswerScore,
    COALESCE(qdm.UniqueCommentersOnQuestion, 0) AS UniqueCommentersOnQuestion,
    COALESCE(phm.TotalHistoryEntries, 0) AS QuestionHistoryEntries,
    COALESCE(phm.UniqueEditors, 0) AS QuestionUniqueEditors,
    COALESCE(phm.MajorEditCount, 0) AS QuestionMajorEditCount,
    COALESCE(phm.CloseHistoryCount, 0) AS QuestionCloseHistoryCount,
    COALESCE(phm.ReopenHistoryCount, 0) AS QuestionReopenHistoryCount,
    qdm.CloseReasonName,
    ats.TagName AS PrimaryAssociatedTag,
    COALESCE(ats.AverageTagQuestionScore, 0.0) AS TagAvgScore,
    COALESCE(ats.AvgViewsPerQuestionWithTag, 0.0) AS TagAvgViews,
    RANK() OVER (PARTITION BY uas.UserId ORDER BY qdm.QuestionScore DESC, qdm.ViewCount DESC) AS UserQuestionRankByScore,
    NTILE(10) OVER (ORDER BY qdm.ViewCount DESC, qdm.QuestionScore DESC) AS GlobalViewScoreDecile,
    LAG(qdm.QuestionCreationDate, 1) OVER (PARTITION BY uas.UserId ORDER BY qdm.QuestionCreationDate) AS PreviousQuestionDate,
    COALESCE(EXTRACT(EPOCH FROM (qdm.QuestionCreationDate - LAG(qdm.QuestionCreationDate, 1) OVER (PARTITION BY uas.UserId ORDER BY qdm.QuestionCreationDate))) / (3600 * 24), 0) AS DaysSincePreviousQuestion,
    CASE
        WHEN qdm.QuestionScore >= 100 AND qdm.AnswerCount >= 5 AND qdm.ViewCount >= 20000 THEN 'Elite Impact'
        WHEN qdm.QuestionScore >= 50 AND qdm.AnswerCount >= 3 AND qdm.ViewCount >= 5000 THEN 'High Impact'
        WHEN qdm.ClosedDate IS NOT NULL AND COALESCE(phm.CloseHistoryCount, 0) > 0 THEN 'Closed/Potentially Problematic'
        WHEN qdm.QuestionAgeDays > 365 * 2 AND qdm.QuestionScore < 10 AND qdm.AnswerCount = 0 THEN 'Stale/Unanswered'
        ELSE 'Moderate Impact'
    END AS QuestionImpactCategory,
    UPPER(SUBSTRING(uas.DisplayName FROM 1 FOR 1)) AS DisplayNameFirstLetter,
    CHAR_LENGTH(qdm.QuestionTitle) AS QuestionTitleLength,
    CHAR_LENGTH(REPLACE(REPLACE(qdm.Tags, '><', ' '), '<', '')) - CHAR_LENGTH(REPLACE(qdm.Tags, '>', '')) AS TagsCharacterLength,
    (qdm.QuestionScore * 1.0 / NULLIF(qdm.QuestionAgeDays, 0)) AS ScorePerDay,
    (qdm.ViewCount * 1.0 / NULLIF(qdm.QuestionAgeDays, 0)) AS ViewsPerDay,
    (qdm.QuestionFavoriteCount * 1.0 / NULLIF(qdm.ViewCount, 0)) AS FavoriteRatio,
    (uas.TotalUpVotesGiven * 1.0 / NULLIF(uas.TotalUpVotesGiven + uas.TotalDownVotesGiven, 0)) AS UpvotePreferenceRatio,
    SUM(qdm.QuestionScore) OVER (PARTITION BY CAST(qdm.QuestionCreationDate AS date)) AS DailyTotalQuestionScore,
    ARRAY_TO_STRING(string_to_array(SUBSTRING(qdm.Tags FROM 2 FOR (CHAR_LENGTH(qdm.Tags) - 2)), '><'), ', ') AS FormattedTags
FROM
    UserActivitySummary uas
INNER JOIN QuestionDetailedMetrics qdm ON uas.UserId = qdm.OwnerUserId
LEFT JOIN PostHistoricalEditMetrics phm ON qdm.QuestionId = phm.PostId
LEFT JOIN BadgeCounts bc ON uas.UserId = bc.UserId
LEFT JOIN LATERAL (
    SELECT t.TagName
    FROM UNNEST(string_to_array(SUBSTRING(qdm.Tags FROM 2 FOR (CHAR_LENGTH(qdm.Tags) - 2)), '><')) AS t(TagName)
    ORDER BY t.TagName
    LIMIT 1
) AS primary_tag ON TRUE
LEFT JOIN AggregatedTagStats ats ON primary_tag.TagName = ats.TagName
WHERE
    uas.Reputation >= 1000
    AND uas.TotalQuestions >= 5
    AND qdm.QuestionScore >= 5
    AND qdm.ViewCount >= 100
    AND qdm.QuestionAgeDays BETWEEN 60 AND 365 * 5
    AND (
        qdm.QuestionTitle ILIKE '%sql%' OR qdm.Tags ILIKE '%<database>%' OR qdm.Tags ILIKE '%<performance>%'
        OR (qdm.CloseReasonName IS NULL AND qdm.HasAcceptedAnswer IS TRUE AND qdm.AnswerCount >= 2)
    )
ORDER BY
    uas.Reputation DESC,
    UserQuestionRankByScore ASC,
    qdm.QuestionCreationDate DESC
LIMIT 2000;