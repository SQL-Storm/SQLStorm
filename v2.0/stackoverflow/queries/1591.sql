-- {"query": "1591.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gemini-2.5-flash", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2111, "output_tokens": 2919}
WITH UserEngagement AS (
    SELECT
        u.Id AS UserId,
        u.DisplayName,
        u.Reputation,
        u.UpVotes,
        u.DownVotes,
        u.Views AS UserViews,
        COUNT(DISTINCT p.Id) AS TotalPosts,
        COUNT(DISTINCT CASE WHEN p.PostTypeId = 1 THEN p.Id END) AS TotalQuestions,
        COUNT(DISTINCT CASE WHEN p.PostTypeId = 2 THEN p.Id END) AS TotalAnswers,
        SUM(COALESCE(p.Score, 0)) AS TotalPostScore,
        AVG(CASE WHEN p.Score IS NOT NULL THEN p.Score ELSE 0 END) AS AvgPostScore,
        COUNT(DISTINCT b.Id) AS TotalBadges,
        MAX(b.Class) AS MaxBadgeClassAchieved,
        EXTRACT(EPOCH FROM (CAST('2024-10-01 12:34:56' AS timestamp) - u.CreationDate)) / 86400.0 AS DaysSinceCreation,
        u.Reputation / NULLIF(EXTRACT(EPOCH FROM (CAST('2024-10-01 12:34:56' AS timestamp) - u.CreationDate)) / 86400.0, 0) AS ReputationPerDay,
        COUNT(DISTINCT c.Id) AS TotalCommentsMade,
        SUM(COALESCE(c.Score, 0)) AS TotalCommentScore,
        MAX(ph.CreationDate) AS LastUserActivityDate
    FROM Users u
    LEFT JOIN Posts p ON u.Id = p.OwnerUserId
    LEFT JOIN Badges b ON u.Id = b.UserId
    LEFT JOIN Comments c ON u.Id = c.UserId
    LEFT JOIN PostHistory ph ON u.Id = ph.UserId
    GROUP BY
        u.Id, u.DisplayName, u.Reputation, u.UpVotes, u.DownVotes, u.Views, u.CreationDate
),
QuestionActivity AS (
    SELECT
        q.Id AS QuestionId,
        q.OwnerUserId,
        q.AcceptedAnswerId,
        q.Title,
        q.CreationDate AS QuestionCreationDate,
        q.Score AS QuestionScore,
        q.ViewCount AS QuestionViewCount,
        q.AnswerCount,
        q.FavoriteCount,
        q.ClosedDate,
        q.LastActivityDate,
        (SELECT COUNT(DISTINCT co.UserId) FROM Comments co WHERE co.PostId = q.Id) AS DistinctCommentersOnQuestion,
        (SELECT AVG(co.Score) FROM Comments co WHERE co.PostId = q.Id) AS AvgCommentScoreOnQuestion,
        (SELECT STRING_AGG(t.TagName, ', ' ORDER BY t.TagName) FROM Tags t WHERE t.TagName IN (SELECT UNNEST(string_to_array(SUBSTRING(q.Tags, 2, LENGTH(q.Tags) - 2), '><')))) AS FormattedTags,
        DENSE_RANK() OVER (ORDER BY q.ViewCount DESC, q.Score DESC) AS ViewScoreRank,
        ROW_NUMBER() OVER (PARTITION BY q.OwnerUserId ORDER BY q.CreationDate DESC) AS UserQuestionSequence,
        MAX(ph_q.CreationDate) OVER (PARTITION BY q.Id) AS LastQuestionEditDate,
        q.Tags
    FROM Posts q
    LEFT JOIN PostHistory ph_q ON q.Id = ph_q.PostId AND ph_q.PostHistoryTypeId IN (4, 5, 6)
    WHERE q.PostTypeId = 1
),
AnswerQuality AS (
    SELECT
        a.Id AS AnswerId,
        a.ParentId AS QuestionId,
        a.OwnerUserId AS AnswerOwnerUserId,
        a.CreationDate AS AnswerCreationDate,
        a.Score AS AnswerScore,
        a.LastActivityDate AS AnswerLastActivityDate,
        LAG(a.CreationDate, 1, a.CreationDate) OVER (PARTITION BY a.OwnerUserId ORDER BY a.CreationDate) AS PrevAnswerDate,
        EXTRACT(EPOCH FROM (a.CreationDate - LAG(a.CreationDate, 1, a.CreationDate) OVER (PARTITION BY a.OwnerUserId ORDER BY a.CreationDate))) / 3600.0 AS HoursSincePrevAnswer,
        (SELECT COUNT(DISTINCT co.UserId) FROM Comments co WHERE co.PostId = a.Id) AS DistinctCommentersOnAnswer,
        (SELECT AVG(co.Score) FROM Comments co WHERE co.PostId = a.Id) AS AvgCommentScoreOnAnswer,
        SUM(CASE WHEN v.VoteTypeId = 2 THEN 1 ELSE 0 END) AS UpvoteCount,
        SUM(CASE WHEN v.VoteTypeId = 3 THEN 1 ELSE 0 END) AS DownvoteCount
    FROM Posts a
    LEFT JOIN Votes v ON a.Id = v.PostId
    WHERE a.PostTypeId = 2
    GROUP BY a.Id, a.ParentId, a.OwnerUserId, a.CreationDate, a.Score, a.LastActivityDate
),
RelatedPostInfluence AS (
    SELECT
        pl.PostId,
        COUNT(DISTINCT CASE WHEN pl.LinkTypeId = 1 THEN pl.RelatedPostId END) AS LinkedPostsCount,
        COUNT(DISTINCT CASE WHEN pl.LinkTypeId = 3 THEN pl.RelatedPostId END) AS DuplicatePostsCount,
        COALESCE(SUM(CASE WHEN pl.LinkTypeId = 1 THEN rp.ViewCount ELSE 0 END), 0) AS TotalLinkedPostViews,
        COALESCE(SUM(CASE WHEN pl.LinkTypeId = 3 THEN rp.Score ELSE 0 END), 0) AS TotalDuplicatePostScore
    FROM PostLinks pl
    JOIN Posts rp ON pl.RelatedPostId = rp.Id
    GROUP BY pl.PostId
),
ClosingReasonAnalysis AS (
    SELECT
        ph.PostId,
        ph.CreationDate AS CloseDateHistory,
        ph.Comment AS CloseReasonComment,
        cr.Name AS CloseReasonName,
        ROW_NUMBER() OVER (PARTITION BY ph.PostId ORDER BY ph.CreationDate DESC) AS rn
    FROM PostHistory ph
    LEFT JOIN CloseReasonTypes cr ON ph.PostHistoryTypeId = 10
        AND ph.Comment ~ '^[0-9]+$'
        AND CAST(ph.Comment AS integer) = cr.Id
    WHERE ph.PostHistoryTypeId = 10
)
SELECT
    ue.DisplayName AS User_DisplayName,
    ue.Reputation,
    ue.TotalPosts,
    ue.TotalQuestions,
    ue.TotalAnswers,
    ue.TotalBadges,
    ue.ReputationPerDay,
    q.Title AS Question_Title,
    q.QuestionCreationDate,
    q.QuestionScore,
    q.QuestionViewCount,
    q.AnswerCount AS Question_AnswerCount,
    q.FavoriteCount AS Question_FavoriteCount,
    q.FormattedTags AS Question_Tags,
    q.DistinctCommentersOnQuestion,
    q.AvgCommentScoreOnQuestion,
    q.LastQuestionEditDate,
    aq.AnswerId AS AcceptedAnswer_Id,
    ua.DisplayName AS AcceptedAnswer_OwnerDisplayName,
    aq.AnswerScore AS AcceptedAnswer_Score,
    aq.HoursSincePrevAnswer AS AcceptedAnswer_HoursSincePrevAnswer,
    COALESCE(aq.UpvoteCount, 0) AS AcceptedAnswer_UpvoteCount,
    COALESCE(aq.DownvoteCount, 0) AS AcceptedAnswer_DownvoteCount,
    COALESCE(rpi.LinkedPostsCount, 0) AS Question_LinkedPostsCount,
    COALESCE(rpi.DuplicatePostsCount, 0) AS Question_DuplicatePostsCount,
    rpi.TotalLinkedPostViews AS Question_TotalLinkedPostViews,
    rpi.TotalDuplicatePostScore AS Question_TotalDuplicatePostScore,
    cra.CloseReasonName AS Question_CloseReason,
    CASE
        WHEN q.ClosedDate IS NOT NULL AND cra.CloseReasonName IS NULL THEN 'Unknown/Legacy Close'
        WHEN q.ClosedDate IS NOT NULL THEN 'Closed'
        ELSE 'Open'
    END AS Question_Status,
    RANK() OVER (ORDER BY q.QuestionScore DESC, q.QuestionViewCount DESC) AS GlobalQuestionRank,
    (SELECT COUNT(DISTINCT badge.Name)
     FROM Badges badge
     WHERE badge.UserId = ue.UserId AND badge.Class = 1
    ) AS GoldBadgesCount,
    (SELECT AVG(v.BountyAmount)
     FROM Votes v
     WHERE v.PostId = q.QuestionId AND v.VoteTypeId = 8
    ) AS AvgBountyAmountForQuestion,
    (SELECT
        COALESCE(SUM(LENGTH(c.Text) - LENGTH(REPLACE(LOWER(c.Text), 'thanks', '')))/6, 0) +
        COALESCE(SUM(LENGTH(c.Text) - LENGTH(REPLACE(LOWER(c.Text), 'appreciate', '')))/10, 0)
     FROM Comments c
     WHERE c.PostId = q.QuestionId
    ) AS ThankfulCommentsCountApproximation,
    (SELECT COUNT(DISTINCT ph_inner.UserId)
     FROM PostHistory ph_inner
     WHERE ph_inner.PostId = q.QuestionId
       AND ph_inner.PostHistoryTypeId IN (4, 5, 6)
       AND ph_inner.UserId IS NOT NULL
       AND ph_inner.UserId != q.OwnerUserId
       AND ph_inner.CreationDate > q.QuestionCreationDate
       AND EXISTS (
            SELECT 1
            FROM Posts p_editor
            WHERE p_editor.OwnerUserId = ph_inner.UserId
              AND p_editor.PostTypeId = 1
              AND p_editor.Score > 100
              AND p_editor.CreationDate < ph_inner.CreationDate
       )
    ) AS ExternalEditorCountForQuestion
FROM UserEngagement ue
INNER JOIN QuestionActivity q ON ue.UserId = q.OwnerUserId
LEFT JOIN AnswerQuality aq ON q.AcceptedAnswerId = aq.AnswerId
LEFT JOIN Users ua ON aq.AnswerOwnerUserId = ua.Id
LEFT JOIN RelatedPostInfluence rpi ON q.QuestionId = rpi.PostId
LEFT JOIN ClosingReasonAnalysis cra ON q.QuestionId = cra.PostId AND cra.rn = 1
WHERE
    ue.Reputation >= 10000
    AND ue.TotalQuestions >= 5
    AND ue.TotalAnswers >= 10
    AND q.QuestionScore > 50
    AND q.QuestionViewCount > 5000
    AND q.AnswerCount >= 2
    AND q.QuestionCreationDate >= (CAST('2024-10-01 12:34:56' AS timestamp) - INTERVAL '5 years')
    AND (
        q.ClosedDate IS NULL OR
        (q.ClosedDate IS NOT NULL AND cra.CloseReasonName NOT IN ('Off-topic', 'Not a real question', 'Needs more focus', 'Needs details or clarity'))
    )
    AND (ue.DisplayName IS NOT NULL AND LENGTH(TRIM(ue.DisplayName)) > 0)
    AND (
        q.FormattedTags ILIKE '%sql%' OR
        q.FormattedTags ILIKE '%database%' OR
        q.FormattedTags ILIKE '%performance%' OR
        q.FormattedTags ILIKE '%optimization%'
    )
    AND EXISTS (
        SELECT 1
        FROM Tags t_pop
        WHERE t_pop.TagName IN (SELECT UNNEST(string_to_array(SUBSTRING(q.Tags, 2, LENGTH(q.Tags) - 2), '><')))
          AND t_pop.Count > 100000
    )
    AND NOT EXISTS (
        SELECT 1
        FROM PostHistory ph_del
        WHERE ph_del.PostId = q.QuestionId
          AND ph_del.PostHistoryTypeId = 12
    )
ORDER BY
    ue.Reputation DESC,
    q.QuestionScore DESC,
    q.QuestionViewCount DESC
LIMIT 100;