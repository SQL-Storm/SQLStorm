WITH UserEngagement AS (
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
        SUM(CASE WHEN p.Id IS NOT NULL AND p.CreationDate >= u.CreationDate + INTERVAL '1' YEAR THEN p.Score ELSE 0 END) AS ScoreAfterFirstYear,
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
        u.Id, u.DisplayName, u.Reputation, u.CreationDate
),
BadgeSummary AS (
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
        COUNT(DISTINCT CASE WHEN ph_edit.PostHistoryTypeId IN (4,5,6) THEN ph_edit.Id END) AS EditHistoryCount,
        COUNT(DISTINCT CASE WHEN ph_close.PostHistoryTypeId = 10 THEN ph_close.Id END) AS CloseHistoryCount,
        COUNT(DISTINCT CASE WHEN ph_reopen.PostHistoryTypeId = 11 THEN ph_reopen.Id END) AS ReopenHistoryCount,
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
        STRING_AGG(DISTINCT t.TagName, ',') AS QuestionTagsList
    FROM
        Posts q
    LEFT JOIN
        PostHistory ph_edit ON q.Id = ph_edit.PostId
    LEFT JOIN
        PostHistory ph_close ON q.Id = ph_close.PostId
    LEFT JOIN
        PostHistory ph_reopen ON q.Id = ph_reopen.PostId
    LEFT JOIN
        (
            SELECT
                q_inner.Id AS qid,
                TRIM(tag) AS TagName
            FROM
                Posts q_inner,
                LATERAL (
                    SELECT UNNEST(string_to_array(SUBSTRING(q_inner.Tags FROM 2 FOR CHAR_LENGTH(q_inner.Tags) - 2), '><')) AS tag
                ) AS tags
            WHERE q_inner.Tags IS NOT NULL AND CHAR_LENGTH(q_inner.Tags) > 2
        ) t ON t.qid = q.Id
    WHERE
        q.PostTypeId = 1
    GROUP BY
        q.Id, q.OwnerUserId, q.Title, q.CreationDate, q.Score, q.ViewCount, q.AnswerCount,
        q.CommentCount, q.FavoriteCount, q.ClosedDate, q.LastEditDate, q.LastActivityDate
),
DuplicateLinkAnalysis AS (
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
    SELECT
        ue.UserId,
        ue.DisplayName,
        ue.Reputation,
        COALESCE(bs.TotalBadges, 0) AS TotalBadges,
        COALESCE(bs.GoldBadges, 0) AS GoldBadges,
        ue.TotalQuestions,
        ue.TotalAnswers,
        ue.TotalPostScore,
        ue.TotalViewsOnQuestions,
        ue.TotalCommentsMade,
        ue.ScoreAfterFirstYear,
        ROUND(CAST(ue.TotalPostScore AS NUMERIC) / NULLIF(ue.TotalPosts, 0), 2) AS AvgPostScore,
        ROUND(CAST(COALESCE(bs.GoldBadges,0) AS NUMERIC) / NULLIF(COALESCE(bs.TotalBadges,0), 0), 4) AS GoldBadgeRatio,
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
        EXISTS (
            SELECT 1
            FROM Posts ans
            WHERE ans.ParentId = q.QuestionId
              AND ans.OwnerUserId = ue.UserId
              AND ans.Score > COALESCE(q.QuestionScore, 0) * 1.5
        ) AS HasSelfAnsweredHighScore,
        COALESCE(dla.DuplicateOfQuestionId, -1) AS IsDuplicateOfQuestionId,
        dla.DuplicateQuestionScore,
        dla.LinkTypeName,
        LAG(q.QuestionCreationDate, 1, TIMESTAMP '1970-01-01 00:00:00') OVER (PARTITION BY ue.UserId ORDER BY q.QuestionCreationDate) AS PreviousQuestionDate,
        EXTRACT(EPOCH FROM (q.QuestionCreationDate - LAG(q.QuestionCreationDate, 1, TIMESTAMP '1970-01-01 00:00:00') OVER (PARTITION BY ue.UserId ORDER BY q.QuestionCreationDate))) / 86400 AS DaysSinceLastQuestion,
        q.QuestionCreationDate,
        ue.LastActivityDate
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
    AND c.QuestionCreationDate >= (TIMESTAMP '2024-10-01 12:34:56' - INTERVAL '1' YEAR)
    AND c.QuestionViews > 1000
    AND c.QuestionScore > 50
    AND c.QuestionImpactCategory = 'HighImpact'
    AND c.QuestionViewQuartile <= 2
    AND NOT EXISTS (
        SELECT 1
        FROM Comments comm
        WHERE comm.UserId = c.UserId
          AND comm.CreationDate > (TIMESTAMP '2024-10-01 12:34:56' - INTERVAL '6' MONTH)
          AND LOWER(comm.Text) LIKE '%advertis%'
    )
UNION ALL
SELECT
    c.UserId,
    c.DisplayName,
    c.Reputation,
    c.GoldBadges,
    c.TotalQuestions,
    NULL AS QuestionId,
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
    AND c.AvgPostScore >= 10
    AND c.TotalCommentsMade > 50
    AND (
        SELECT COUNT(DISTINCT p_ans.Id)
        FROM Posts p_ans
        WHERE p_ans.OwnerUserId = c.UserId AND p_ans.PostTypeId = 2 AND p_ans.Score > 50
    ) >= 5
    AND c.LastActivityDate >= (TIMESTAMP '2024-10-01 12:34:56' - INTERVAL '3' MONTH)
    AND NOT EXISTS (
        SELECT 1
        FROM PostHistory ph
        WHERE ph.UserId = c.UserId AND ph.PostHistoryTypeId = 12
          AND ph.CreationDate > (TIMESTAMP '2024-10-01 12:34:56' - INTERVAL '1' YEAR)
    )
GROUP BY
    c.UserId, c.DisplayName, c.Reputation, c.GoldBadges, c.TotalQuestions,
    c.GlobalReputationRank, c.TotalAnswers, c.AvgPostScore, c.TotalCommentsMade, c.LastActivityDate
ORDER BY
    Reputation DESC, GoldBadges DESC
LIMIT 200;