-- {"query": "1618.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gemini-2.5-flash", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2111, "output_tokens": 2954} 

WITH UserEngagement AS (
    -- CTE 1: Aggregates core user activity metrics including post scores, view counts, and comment counts.
    SELECT
        u.Id AS UserId,
        u.DisplayName,
        u.Reputation,
        COUNT(DISTINCT p.Id) AS TotalPosts,
        COUNT(DISTINCT CASE WHEN p.PostTypeId = 1 THEN p.Id END) AS TotalQuestions,
        COUNT(DISTINCT CASE WHEN p.PostTypeId = 2 THEN p.Id END) AS TotalAnswers,
        SUM(COALESCE(p.Score, 0)) AS TotalPostScore,
        SUM(COALESCE(p.ViewCount, 0)) AS TotalViewsOnQuestions,
        COUNT(DISTINCT c.Id) AS TotalCommentsMade,
        SUM(CASE WHEN vt.Name = 'UpMod' THEN 1 ELSE 0 END) AS TotalUpVotesGiven,
        SUM(CASE WHEN vt.Name = 'DownMod' THEN 1 ELSE 0 END) AS TotalDownVotesGiven,
        SUM(CASE WHEN p.Id IS NOT NULL AND p.CreationDate >= u.CreationDate + INTERVAL '1 year' THEN p.Score ELSE 0 END) AS ScoreAfterFirstYear,
        MAX(u.LastAccessDate) AS LastActivityDate
    FROM
        Users u
    LEFT JOIN
        Posts p ON u.Id = p.OwnerUserId
    LEFT JOIN
        Comments c ON u.Id = c.UserId
    LEFT JOIN
        Votes v ON u.Id = v.UserId
    LEFT JOIN
        VoteTypes vt ON v.VoteTypeId = vt.Id
    GROUP BY
        u.Id, u.DisplayName, u.Reputation
),
BadgeSummary AS (
    -- CTE 2: Summarizes badge achievements for each user, counting gold, silver, and bronze badges.
    SELECT
        b.UserId,
        COUNT(b.Id) AS TotalBadges,
        SUM(CASE WHEN b.Class = 1 THEN 1 ELSE 0 END) AS GoldBadges,
        SUM(CASE WHEN b.Class = 2 THEN 1 ELSE 0 END) AS SilverBadges,
        SUM(CASE WHEN b.Class = 3 THEN 1 ELSE 0 END) AS BronzeBadges,
        MAX(b.Date) AS LatestBadgeDate
    FROM
        Badges b
    GROUP BY
        b.UserId
),
QuestionMetrics AS (
    -- CTE 3: Calculates detailed metrics for individual questions, including edit/close/reopen history and average answer scores.
    SELECT
        q.Id AS QuestionId,
        q.OwnerUserId,
        q.Title,
        q.CreationDate AS QuestionCreationDate,
        q.Score AS QuestionScore,
        q.ViewCount,
        q.AnswerCount,
        q.CommentCount AS QuestionCommentCount,
        q.FavoriteCount,
        q.ClosedDate,
        q.LastEditDate,
        q.LastActivityDate,
        COUNT(DISTINCT ph_edit.Id) FILTER (WHERE ph_edit.PostHistoryTypeId IN (4, 5, 6)) AS EditHistoryCount,
        COUNT(DISTINCT ph_close.Id) FILTER (WHERE ph_close.PostHistoryTypeId = 10) AS CloseHistoryCount,
        COUNT(DISTINCT ph_reopen.Id) FILTER (WHERE ph_reopen.PostHistoryTypeId = 11) AS ReopenHistoryCount,
        (
            SELECT AVG(a.Score)
            FROM Posts a
            WHERE a.ParentId = q.Id AND a.PostTypeId = 2
        ) AS AvgAnswerScore,
        (
            SELECT MAX(a.CreationDate)
            FROM Posts a
            WHERE a.ParentId = q.Id AND a.PostTypeId = 2
        ) AS LatestAnswerDate,
        STRING_AGG(DISTINCT t.TagName, ',') FILTER (WHERE t.TagName IS NOT NULL) AS QuestionTagsList
    FROM
        Posts q
    LEFT JOIN
        PostHistory ph_edit ON q.Id = ph_edit.PostId
    LEFT JOIN
        PostHistory ph_close ON q.Id = ph_close.PostId
    LEFT JOIN
        PostHistory ph_reopen ON q.Id = ph_reopen.PostId
    LEFT JOIN LATERAL
        (SELECT * FROM unnest(string_to_array(SUBSTRING(q.Tags, 2, LENGTH(q.Tags) - 2), '><')) AS TagName) AS t (TagName)
        ON q.Tags IS NOT NULL AND LENGTH(q.Tags) > 2
    WHERE
        q.PostTypeId = 1
    GROUP BY
        q.Id, q.OwnerUserId, q.Title, q.CreationDate, q.Score, q.ViewCount, q.AnswerCount,
        q.CommentCount, q.FavoriteCount, q.ClosedDate, q.LastEditDate, q.LastActivityDate
),
DuplicateLinkAnalysis AS (
    -- CTE 4: Identifies primary duplicate links for questions and related metrics of the duplicate post.
    SELECT
        pl.PostId AS SourceQuestionId,
        pl.RelatedPostId AS DuplicateOfQuestionId,
        p_dup.Score AS DuplicateQuestionScore,
        p_dup.ViewCount AS DuplicateQuestionViewCount,
        p_dup.OwnerUserId AS DuplicateQuestionOwnerUserId,
        pl.CreationDate AS LinkCreationDate,
        lt.Name AS LinkTypeName,
        ROW_NUMBER() OVER (PARTITION BY pl.PostId ORDER BY pl.CreationDate DESC) AS rn
    FROM
        PostLinks pl
    JOIN
        LinkTypes lt ON pl.LinkTypeId = lt.Id
    JOIN
        Posts p_dup ON pl.RelatedPostId = p_dup.Id
    WHERE
        lt.Name = 'Duplicate'
),
CombinedUserQuestionData AS (
    -- CTE 5: Consolidates data from previous CTEs and applies initial filtering, along with complex calculations and window functions.
    SELECT
        ue.UserId,
        ue.DisplayName,
        ue.Reputation,
        bs.TotalBadges,
        bs.GoldBadges,
        ue.TotalQuestions,
        ue.TotalAnswers,
        ue.TotalPostScore,
        ue.TotalViewsOnQuestions,
        ue.TotalCommentsMade,
        ue.ScoreAfterFirstYear,
        ROUND(CAST(ue.TotalPostScore AS NUMERIC) / NULLIF(ue.TotalPosts, 0), 2) AS AvgPostScore,
        ROUND(CAST(bs.GoldBadges AS NUMERIC) / NULLIF(bs.TotalBadges, 0), 4) AS GoldBadgeRatio,
        q.QuestionId,
        q.Title AS QuestionTitle,
        q.QuestionScore,
        q.ViewCount AS QuestionViews,
        q.AnswerCount AS QuestionAnswers,
        q.AvgAnswerScore,
        q.EditHistoryCount,
        q.CloseHistoryCount,
        q.ReopenHistoryCount,
        q.QuestionTagsList,
        CASE
            WHEN q.QuestionScore > 100 AND q.ViewCount > 5000 AND q.AnswerCount > 5 THEN 'HighImpact'
            WHEN q.QuestionScore > 20 OR q.ViewCount > 1000 THEN 'ModerateImpact'
            ELSE 'LowImpact'
        END AS QuestionImpactCategory,
        DENSE_RANK() OVER (ORDER BY ue.Reputation DESC, ue.TotalPostScore DESC) AS GlobalReputationRank,
        NTILE(5) OVER (ORDER BY q.ViewCount DESC) AS QuestionViewQuartile,
        EXISTS ( -- Correlated subquery: checks if the user answered their own question with a significantly higher score
            SELECT 1
            FROM Posts ans
            WHERE ans.ParentId = q.QuestionId
              AND ans.OwnerUserId = ue.UserId
              AND ans.Score > COALESCE(q.QuestionScore, 0) * 1.5
        ) AS HasSelfAnsweredHighScore,
        COALESCE(dla.DuplicateOfQuestionId, -1) AS IsDuplicateOfQuestionId,
        dla.DuplicateQuestionScore,
        dla.LinkTypeName,
        LAG(q.QuestionCreationDate, 1, '1970-01-01'::timestamp) OVER (PARTITION BY ue.UserId ORDER BY q.QuestionCreationDate) AS PreviousQuestionDate,
        EXTRACT(EPOCH FROM (q.QuestionCreationDate - LAG(q.QuestionCreationDate, 1, '1970-01-01'::timestamp) OVER (PARTITION BY ue.UserId ORDER BY q.QuestionCreationDate))) / 86400 AS DaysSinceLastQuestion
    FROM
        UserEngagement ue
    LEFT JOIN
        BadgeSummary bs ON ue.UserId = bs.UserId
    LEFT JOIN
        QuestionMetrics q ON ue.UserId = q.OwnerUserId
    LEFT JOIN
        DuplicateLinkAnalysis dla ON q.QuestionId = dla.SourceQuestionId AND dla.rn = 1
    WHERE
        ue.Reputation > 500
        AND (ue.DisplayName IS NOT NULL AND ue.DisplayName <> '')
)
-- Main Query: Uses UNION ALL to combine two distinct sets of criteria for influential users.
-- Branch 1: Identifies high-reputation users with recently popular and impactful questions.
SELECT
    c.UserId,
    c.DisplayName,
    c.Reputation,
    c.GoldBadges,
    c.TotalQuestions,
    c.QuestionId,
    c.QuestionTitle,
    c.QuestionScore,
    c.QuestionViews,
    c.QuestionImpactCategory,
    c.GlobalReputationRank,
    c.QuestionViewQuartile,
    c.HasSelfAnsweredHighScore,
    c.IsDuplicateOfQuestionId,
    c.DaysSinceLastQuestion,
    'HighRep_PopularRecentQuestion' AS ReasonCategory
FROM
    CombinedUserQuestionData c
WHERE
    c.Reputation > 5000
    AND c.QuestionId IS NOT NULL
    AND c.QuestionCreationDate >= NOW() - INTERVAL '1 year'
    AND c.QuestionViews > 1000
    AND c.QuestionScore > 50
    AND c.QuestionImpactCategory = 'HighImpact'
    AND c.QuestionViewQuartile <= 2 -- Top 40% of questions by views for this user
    AND NOT EXISTS ( -- Correlated subquery: Excludes users with recent "advertising" comments
        SELECT 1
        FROM Comments comm
        WHERE comm.UserId = c.UserId
          AND comm.CreationDate > NOW() - INTERVAL '6 months'
          AND LOWER(comm.Text) LIKE '%advertis%'
    )
UNION ALL
-- Branch 2: Identifies users with significant badge achievements who are also active answerers.
SELECT
    c.UserId,
    c.DisplayName,
    c.Reputation,
    c.GoldBadges,
    c.TotalQuestions,
    NULL AS QuestionId, -- This branch focuses on overall user contributions, not specific questions
    NULL AS QuestionTitle,
    NULL AS QuestionScore,
    NULL AS QuestionViews,
    NULL AS QuestionImpactCategory,
    c.GlobalReputationRank,
    NULL AS QuestionViewQuartile,
    NULL AS HasSelfAnsweredHighScore,
    NULL AS IsDuplicateOfQuestionId,
    NULL AS DaysSinceLastQuestion,
    'BadgeAchiever_ActiveAnswerer' AS ReasonCategory
FROM
    CombinedUserQuestionData c
WHERE
    c.GoldBadges >= 3
    AND c.TotalAnswers >= 100
    AND c.AvgPostScore >= 10 -- Average score across all their posts (questions and answers)
    AND c.TotalCommentsMade > 50
    AND ( -- Correlated subquery: At least 5 highly scored answers
        SELECT COUNT(DISTINCT p_ans.Id)
        FROM Posts p_ans
        WHERE p_ans.OwnerUserId = c.UserId AND p_ans.PostTypeId = 2 AND p_ans.Score > 50
    ) >= 5
    AND c.LastActivityDate >= NOW() - INTERVAL '3 months' -- Recently active
    AND NOT EXISTS ( -- Correlated subquery: Excludes users who have had posts deleted recently
        SELECT 1
        FROM PostHistory ph
        WHERE ph.UserId = c.UserId AND ph.PostHistoryTypeId = 12 -- Post Deleted
          AND ph.CreationDate > NOW() - INTERVAL '1 year'
    )
GROUP BY -- Grouping for Branch 2, since it aggregates user-level data without specific question details
    c.UserId, c.DisplayName, c.Reputation, c.GoldBadges, c.TotalQuestions,
    c.GlobalReputationRank, c.TotalAnswers, c.AvgPostScore, c.TotalCommentsMade, c.LastActivityDate
ORDER BY
    Reputation DESC, GoldBadges DESC
LIMIT 200;
