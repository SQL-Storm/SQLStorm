-- {"query": "1810.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gemini-2.5-flash", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2111, "output_tokens": 2957}
WITH UserActivitySummary AS (
    SELECT
        u.Id AS UserId,
        u.DisplayName,
        u.Reputation,
        u.CreationDate AS UserCreationDate,
        u.LastAccessDate,
        u.Views AS UserViews,
        u.UpVotes AS UserUpVotes,
        u.DownVotes AS UserDownVotes,
        COUNT(DISTINCT CASE WHEN p.PostTypeId = 1 THEN p.Id END) AS TotalQuestionsAsked,
        COUNT(DISTINCT CASE WHEN p.PostTypeId = 2 THEN p.Id END) AS TotalAnswersProvided,
        SUM(CASE WHEN p.PostTypeId = 1 THEN p.Score ELSE 0 END) AS TotalQuestionScore,
        SUM(CASE WHEN p.PostTypeId = 2 THEN p.Score ELSE 0 END) AS TotalAnswerScore,
        AVG(CASE WHEN p.PostTypeId = 2 THEN p.Score END) AS AverageAnswerScore,
        SUM(CASE WHEN p.PostTypeId = 1 AND p.AcceptedAnswerId IS NOT NULL THEN 1 ELSE 0 END) AS QuestionsWithAcceptedAnswers,
        COUNT(DISTINCT t.TagName) AS TotalUniqueTagsUsedInQuestions,
        MAX(CASE WHEN b.Class = 1 THEN 1 ELSE 0 END) AS HasGoldBadge,
        COUNT(b.Id) FILTER (WHERE b.Date >= u.LastAccessDate - INTERVAL '1 year') AS BadgesLastYearCount,
        SUM(CASE WHEN p.PostTypeId = 1 THEN p.FavoriteCount ELSE 0 END) AS TotalQuestionFavorites
    FROM
        Users u
    LEFT JOIN
        Posts p ON u.Id = p.OwnerUserId
    LEFT JOIN
        Badges b ON u.Id = b.UserId
    LEFT JOIN LATERAL (
        SELECT DISTINCT UNNEST(string_to_array(SUBSTRING(p_tags.Tags FROM 2 FOR LENGTH(p_tags.Tags) - 2), '><')) AS TagName
        FROM Posts p_tags
        WHERE p_tags.OwnerUserId = u.Id AND p_tags.PostTypeId = 1 AND p_tags.Tags IS NOT NULL AND LENGTH(p_tags.Tags) > 2
    ) AS t ON TRUE
    GROUP BY
        u.Id, u.DisplayName, u.Reputation, u.CreationDate, u.LastAccessDate, u.Views, u.UpVotes, u.DownVotes
),
RecentHighImpactQuestions AS (
    SELECT
        p.Id AS PostId,
        p.OwnerUserId,
        p.Title AS QuestionTitle,
        p.CreationDate AS QuestionCreationDate,
        p.Score AS QuestionScore,
        p.ViewCount,
        p.AnswerCount,
        p.FavoriteCount,
        p.Tags,
        p.LastActivityDate,
        COALESCE(p.LastEditorDisplayName, u_editor.DisplayName, 'Community') AS LastEditorInfo,
        (p.Score * 0.6) + (p.ViewCount * 0.2) + (COALESCE(p.AnswerCount, 0) * 0.1) + (COALESCE(p.FavoriteCount, 0) * 0.15) AS EngagementScore,
        ROW_NUMBER() OVER (PARTITION BY p.OwnerUserId ORDER BY p.ViewCount DESC, p.Score DESC, p.CreationDate DESC) AS rn_user_question_rank
    FROM
        Posts p
    INNER JOIN
        Users u_owner ON p.OwnerUserId = u_owner.Id
    LEFT JOIN
        Users u_editor ON p.LastEditorUserId = u_editor.Id
    WHERE
        p.PostTypeId = 1
        AND p.CreationDate >= CAST('2024-10-01 12:34:56' AS TIMESTAMP) - INTERVAL '2 year'
        AND p.AcceptedAnswerId IS NOT NULL
        AND p.ViewCount > 5000
        AND p.Score > 10
        AND p.Tags IS NOT NULL
        AND (p.Tags LIKE '%<sql>%' OR p.Tags LIKE '%<database>%' OR p.Tags LIKE '%<performance>%')
),
PostHistorySnapshots AS (
    SELECT
        ph.PostId,
        ph.Id AS HistoryId,
        ph.PostHistoryTypeId,
        pht.Name AS HistoryTypeName,
        ph.CreationDate AS HistoryDate,
        ph.Comment,
        ph.UserId AS HistoryUserId,
        ROW_NUMBER() OVER (PARTITION BY ph.PostId ORDER BY ph.CreationDate DESC) AS rn_latest_history,
        LAG(ph.CreationDate, 1, ph.CreationDate) OVER (PARTITION BY ph.PostId ORDER BY ph.CreationDate) AS PrevHistoryDate,
        LEAD(ph.CreationDate, 1, ph.CreationDate) OVER (PARTITION BY ph.PostId ORDER BY ph.CreationDate) AS NextHistoryDate
    FROM
        PostHistory ph
    INNER JOIN
        PostHistoryTypes pht ON ph.PostHistoryTypeId = pht.Id
    WHERE
        ph.PostHistoryTypeId IN (4, 5, 6, 10, 11, 12, 13)
),
PostLinkSummary AS (
    SELECT
        pl.PostId,
        COUNT(DISTINCT CASE WHEN pl.LinkTypeId = 1 THEN pl.RelatedPostId END) AS LinkedPostsCount,
        COUNT(DISTINCT CASE WHEN pl.LinkTypeId = 3 THEN pl.RelatedPostId END) AS DuplicatePostsCount,
        MAX(CASE WHEN EXISTS (SELECT 1 FROM Posts p WHERE p.Id = pl.RelatedPostId AND p.Score < 0) THEN 1 ELSE 0 END) AS HasBadRelatedPostLink
    FROM
        PostLinks pl
    GROUP BY
        pl.PostId
)
SELECT
    uas.UserId,
    COALESCE(uas.DisplayName, 'Anonymous User #' || uas.UserId) AS DisplayName,
    uas.Reputation,
    uas.UserCreationDate,
    uas.LastAccessDate,
    uas.TotalQuestionsAsked,
    uas.TotalAnswersProvided,
    uas.AverageAnswerScore,
    uas.QuestionsWithAcceptedAnswers,
    uas.TotalUniqueTagsUsedInQuestions,
    uas.HasGoldBadge,
    uas.BadgesLastYearCount,
    (uas.Reputation * 0.1) + (uas.UserUpVotes * 0.05) + (uas.UserViews * 0.01) + (COALESCE(uas.AverageAnswerScore, 0) * 0.5) + (uas.QuestionsWithAcceptedAnswers * 2) + (uas.TotalUniqueTagsUsedInQuestions * 1.5) + (CASE WHEN uas.HasGoldBadge = 1 THEN 1000 ELSE 0 END) AS CompositeInfluenceScore,
    RANK() OVER (ORDER BY uas.Reputation DESC, COALESCE(uas.AverageAnswerScore, 0) DESC, uas.TotalQuestionsAsked DESC) AS OverallUserRank,
    STRING_AGG(CASE WHEN rhq.rn_user_question_rank <= 3 THEN rhq.QuestionTitle || ' (ID: ' || rhq.PostId || ', Score: ' || rhq.QuestionScore || ')' ELSE NULL END, ' | ' ORDER BY rhq.rn_user_question_rank) AS Top3QuestionTitles,
    STRING_AGG(
        CASE
            WHEN rhq.rn_user_question_rank <= 3 AND phs.rn_latest_history = 1 THEN
                'Post ID ' || phs.PostId || ': Latest event: ' || phs.HistoryTypeName || ' on ' || phs.HistoryDate || ' by ' || COALESCE(uu.DisplayName, 'System/Deleted User') || COALESCE(' (' || phs.Comment || ')', '') ||
                ' (Time since prev: ' || EXTRACT(EPOCH FROM (phs.HistoryDate - phs.PrevHistoryDate)) || 's)'
            ELSE NULL
        END,
        ' || ' ORDER BY phs.HistoryDate DESC
    ) AS LatestPostHistorySummary,
    SUM(CASE WHEN rhq.rn_user_question_rank <= 3 THEN COALESCE(pls.LinkedPostsCount, 0) ELSE 0 END) AS TotalTopQuestionLinkedCount,
    SUM(CASE WHEN rhq.rn_user_question_rank <= 3 THEN COALESCE(pls.DuplicatePostsCount, 0) ELSE 0 END) AS TotalTopQuestionDuplicateCount,
    MAX(CASE WHEN rhq.rn_user_question_rank <= 3 THEN COALESCE(pls.HasBadRelatedPostLink, 0) ELSE 0 END) AS HasBadLinkInTopQuestions,
    (SELECT EXISTS(
        SELECT 1 FROM Posts sa WHERE sa.OwnerUserId = uas.UserId AND sa.PostTypeId = 2 AND sa.Score > 500 AND sa.CreationDate >= CAST('2024-10-01 12:34:56' AS TIMESTAMP) - INTERVAL '3 years'
    )) AS HasSuperlativeAnswerRecently,
    NULLIF(CAST(uas.UserUpVotes AS NUMERIC) / NULLIF(uas.UserDownVotes, 0), 0) AS UpVoteDownVoteRatio,
    CASE
        WHEN uas.Reputation >= 20000 AND uas.BadgesLastYearCount >= 5 THEN 'Veteran & Active'
        WHEN uas.Reputation >= 5000 AND COALESCE(uas.AverageAnswerScore, 0) > 20 THEN 'Expert Contributor'
        WHEN uas.TotalQuestionsAsked >= 10 AND uas.QuestionsWithAcceptedAnswers >= 5 THEN 'Question Master'
        ELSE 'Engaged User'
    END AS UserCategory,
    MAX(CASE WHEN rhq.rn_user_question_rank <= 3 AND rhq.Tags LIKE '%<javascript>%' THEN 1 ELSE 0 END) AS AskedJavaScriptHotQuestion,
    MAX(CASE WHEN rhq.rn_user_question_rank <= 3 AND rhq.Tags LIKE '%<python>%' THEN 1 ELSE 0 END) AS AskedPythonHotQuestion
FROM
    UserActivitySummary uas
INNER JOIN
    RecentHighImpactQuestions rhq ON uas.UserId = rhq.OwnerUserId
LEFT JOIN
    PostHistorySnapshots phs ON rhq.PostId = phs.PostId
LEFT JOIN
    Users uu ON phs.HistoryUserId = uu.Id
LEFT JOIN
    PostLinkSummary pls ON rhq.PostId = pls.PostId
WHERE
    uas.TotalQuestionsAsked >= 5
    AND uas.TotalAnswersProvided >= 3
    AND uas.AverageAnswerScore IS NOT NULL AND uas.AverageAnswerScore >= 5
    AND uas.LastAccessDate >= CAST('2024-10-01 12:34:56' AS TIMESTAMP) - INTERVAL '1 year'
    AND rhq.rn_user_question_rank <= 3
    AND uas.Reputation >= 1000
    AND (
        (uas.HasGoldBadge = 1 AND uas.BadgesLastYearCount > 0)
        OR
        (uas.TotalUniqueTagsUsedInQuestions > 10 AND uas.UserUpVotes > COALESCE(uas.UserDownVotes, 0) * 5 AND uas.DisplayName IS NOT NULL)
    )
GROUP BY
    uas.UserId, uas.DisplayName, uas.Reputation, uas.UserCreationDate, uas.LastAccessDate, uas.TotalQuestionsAsked,
    uas.TotalAnswersProvided, uas.AverageAnswerScore, uas.QuestionsWithAcceptedAnswers, uas.TotalUniqueTagsUsedInQuestions,
    uas.HasGoldBadge, uas.BadgesLastYearCount, uas.UserUpVotes, uas.UserDownVotes, uas.UserViews
HAVING
    COUNT(DISTINCT CASE WHEN rhq.rn_user_question_rank <= 3 THEN rhq.PostId END) > 0
ORDER BY
    CompositeInfluenceScore DESC, OverallUserRank ASC
LIMIT 100;