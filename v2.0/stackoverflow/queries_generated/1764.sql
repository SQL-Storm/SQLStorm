-- {"query": "1764.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gemini-2.5-flash", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2111, "output_tokens": 3159} 

WITH UserActivitySummary AS (
    SELECT
        u.Id AS UserId,
        u.DisplayName,
        u.Reputation,
        u.CreationDate AS UserCreationDate,
        u.LastAccessDate,
        COUNT(DISTINCT p.Id) AS TotalPosts,
        SUM(CASE WHEN p.PostTypeId = 1 THEN 1 ELSE 0 END) AS TotalQuestions,
        SUM(CASE WHEN p.PostTypeId = 2 THEN 1 ELSE 0 END) AS TotalAnswers,
        COUNT(DISTINCT c.Id) AS TotalCommentsMade,
        SUM(COALESCE(p.FavoriteCount, 0)) AS TotalFavoriteReceived,
        SUM(CASE WHEN v.VoteTypeId = 2 THEN 1 ELSE 0 END) AS TotalUpVotesGiven,
        SUM(CASE WHEN v.VoteTypeId = 3 THEN 1 ELSE 0 END) AS TotalDownVotesGiven,
        COUNT(DISTINCT b.Id) AS TotalBadges,
        MAX(CASE WHEN b.Class = 1 THEN 1 ELSE 0 END) AS HasGoldBadge,
        EXTRACT(EPOCH FROM (u.LastAccessDate - u.CreationDate)) / (60 * 60 * 24) AS UserAccountAgeDays
    FROM Users u
    LEFT JOIN Posts p ON u.Id = p.OwnerUserId
    LEFT JOIN Comments c ON u.Id = c.UserId
    LEFT JOIN Votes v ON u.Id = v.UserId
    LEFT JOIN Badges b ON u.Id = b.UserId
    GROUP BY
        u.Id, u.DisplayName, u.Reputation, u.CreationDate, u.LastAccessDate
),
PostEngagementMetrics AS (
    SELECT
        p.Id AS PostId,
        p.PostTypeId,
        p.CreationDate AS PostCreationDate,
        p.LastActivityDate,
        p.Score,
        p.ViewCount,
        p.AnswerCount,
        p.CommentCount,
        p.FavoriteCount,
        p.OwnerUserId,
        p.AcceptedAnswerId,
        p.ParentId,
        COALESCE(p.Title, LEFT(p.Body, 100)) AS PostTitleOrExcerpt,
        CASE WHEN p.Tags IS NOT NULL AND LENGTH(p.Tags) > 2
             THEN string_to_array(SUBSTRING(p.Tags, 2, LENGTH(p.Tags)-2), '><')
             ELSE ARRAY[]::varchar[]
        END AS TagArray,
        (p.Score * 1.0 / NULLIF(p.ViewCount, 0)) AS ScorePerView,
        SUM(CASE WHEN ph_edit.PostHistoryTypeId IN (4, 5, 6) THEN 1 ELSE 0 END) AS TotalEditEvents,
        SUM(CASE WHEN ph_close.PostHistoryTypeId = 10 THEN 1 ELSE 0 END) AS TotalCloseEvents,
        SUM(CASE WHEN ph_reopen.PostHistoryTypeId = 11 THEN 1 ELSE 0 END) AS TotalReopenEvents,
        MAX(CASE WHEN p.ClosedDate IS NOT NULL THEN 1 ELSE 0 END) AS IsClosed,
        MAX(CASE WHEN p.CommunityOwnedDate IS NOT NULL THEN 1 ELSE 0 END) AS IsCommunityOwned,
        SUM(CASE WHEN vt_fav.VoteTypeId = 5 THEN 1 ELSE 0 END) AS LegacyFavoriteVotes
    FROM Posts p
    LEFT JOIN PostHistory ph_edit ON p.Id = ph_edit.PostId
    LEFT JOIN PostHistory ph_close ON p.Id = ph_close.PostId
    LEFT JOIN PostHistory ph_reopen ON p.Id = ph_reopen.PostId
    LEFT JOIN Votes vt_fav ON p.Id = vt_fav.PostId AND vt_fav.VoteTypeId = 5
    GROUP BY
        p.Id, p.PostTypeId, p.CreationDate, p.LastActivityDate, p.Score, p.ViewCount,
        p.AnswerCount, p.CommentCount, p.FavoriteCount, p.OwnerUserId, p.AcceptedAnswerId,
        p.ParentId, p.Title, p.Body, p.Tags, p.ClosedDate, p.CommunityOwnedDate
),
ModerationAndLinkedPosts AS (
    SELECT
        ph.PostId,
        COUNT(DISTINCT ph.Id) AS TotalHistoryEvents,
        COUNT(DISTINCT ph.UserId) AS UniqueEditorsOrModerators,
        SUM(CASE WHEN ph.PostHistoryTypeId IN (10, 12, 14, 19) THEN 1 ELSE 0 END) AS CriticalModerationActions,
        SUM(CASE WHEN ph.PostHistoryTypeId IN (11, 13, 15, 20) THEN 1 ELSE 0 END) AS ReversalModerationActions,
        SUM(CASE WHEN pl.LinkTypeId = 1 THEN 1 ELSE 0 END) AS LinkedPostsCount,
        SUM(CASE WHEN pl.LinkTypeId = 3 THEN 1 ELSE 0 END) AS DuplicateOfCount,
        MAX(CASE WHEN ph.PostHistoryTypeId = 10 AND ph.Comment IS NOT NULL THEN cr.Name ELSE NULL END) AS LastCloseReason
    FROM PostHistory ph
    LEFT JOIN PostLinks pl ON ph.PostId = pl.PostId
    LEFT JOIN CloseReasonTypes cr ON ph.PostHistoryTypeId = 10 AND ph.Comment::smallint = cr.Id
    GROUP BY ph.PostId
),
UnnestedPostTags AS (
    SELECT
        pem.PostId,
        unnest(pem.TagArray) AS TagName
    FROM PostEngagementMetrics pem
    WHERE array_length(pem.TagArray, 1) > 0
),
TagAnalysis AS (
    SELECT
        t.TagName,
        t.Count AS TagUseCount,
        AVG(pe.Score) AS AvgPostScoreForTag,
        AVG(pe.ViewCount) AS AvgPostViewsForTag,
        SUM(pe.TotalEditEvents) AS TotalEditsForTagPosts,
        NTILE(4) OVER (ORDER BY t.Count DESC) AS TagPopularityQuartile
    FROM Tags t
    JOIN UnnestedPostTags upt ON t.TagName = upt.TagName
    JOIN PostEngagementMetrics pe ON upt.PostId = pe.PostId
    GROUP BY t.TagName, t.Count
)
SELECT
    uas.UserId,
    uas.DisplayName,
    uas.Reputation,
    uas.UserAccountAgeDays,
    uas.TotalPosts,
    uas.TotalQuestions,
    uas.TotalAnswers,
    uas.TotalCommentsMade,
    uas.TotalFavoriteReceived,
    uas.HasGoldBadge,
    pe.PostId,
    pe.PostTitleOrExcerpt,
    pe.PostTypeId,
    pe.Score AS PostScore,
    pe.ViewCount AS PostViews,
    pe.ScorePerView,
    pe.TotalEditEvents,
    pe.TotalCloseEvents,
    pe.TotalReopenEvents,
    pe.IsClosed,
    pe.IsCommunityOwned,
    mpa.TotalHistoryEvents AS PostModerationEvents,
    mpa.UniqueEditorsOrModerators AS PostUniqueEditors,
    mpa.CriticalModerationActions,
    mpa.ReversalModerationActions,
    mpa.LinkedPostsCount,
    mpa.DuplicateOfCount,
    mpa.LastCloseReason,
    ta.TagName AS PrimaryTag,
    ta.TagUseCount,
    ta.AvgPostScoreForTag,
    ta.TagPopularityQuartile,
    RANK() OVER (PARTITION BY pe.PostTypeId ORDER BY pe.Score DESC, pe.ViewCount DESC) AS PostTypeRank,
    AVG(pe.Score) OVER (PARTITION BY uas.UserId ORDER BY pe.PostCreationDate RANGE BETWEEN INTERVAL '30 days' PRECEDING AND CURRENT ROW) AS AvgScoreLast30DaysForUser,
    (SELECT COUNT(DISTINCT q.Id)
     FROM Posts q
     WHERE q.PostTypeId = 1
       AND q.OwnerUserId = uas.UserId
       AND EXISTS (
           SELECT 1
           FROM Posts a
           WHERE a.ParentId = q.Id
             AND a.OwnerUserId = uas.UserId
       )
    ) AS SelfAnsweredQuestionCount,
    (pe.Score * 5 + pe.ViewCount / 10 + pe.AnswerCount * 3 + pe.CommentCount * 2 + COALESCE(pe.FavoriteCount, 0) * 10) AS EngagementScore,
    UPPER(COALESCE(pe.PostTitleOrExcerpt, 'NO TITLE')) AS PostTitleUpper,
    CASE
        WHEN pe.IsClosed = 1 AND COALESCE(mpa.CriticalModerationActions, 0) > COALESCE(mpa.ReversalModerationActions, 0) THEN 'HighModerationClosed'
        WHEN pe.IsClosed = 1 THEN 'SimplyClosed'
        WHEN pe.TotalEditEvents > 5 AND pe.Score > 50 THEN 'HighlyMaintainedPopular'
        WHEN pe.PostTypeId = 1 AND pe.AnswerCount = 0 AND pe.PostCreationDate < CURRENT_DATE - INTERVAL '1 year' THEN 'UnansweredOldQuestion'
        ELSE 'Normal'
    END AS PostStatusCategory
FROM UserActivitySummary uas
INNER JOIN PostEngagementMetrics pe ON uas.UserId = pe.OwnerUserId
LEFT JOIN ModerationAndLinkedPosts mpa ON pe.PostId = mpa.PostId
LEFT JOIN UnnestedPostTags upt_main ON pe.PostId = upt_main.PostId
LEFT JOIN TagAnalysis ta ON upt_main.TagName = ta.TagName
WHERE
    uas.Reputation > 1000
    AND uas.LastAccessDate > CURRENT_DATE - INTERVAL '6 months'
    AND pe.PostCreationDate > CURRENT_DATE - INTERVAL '2 years'
    AND pe.Score > 5
    AND pe.ViewCount > 100
    AND (LOWER(pe.PostTitleOrExcerpt) LIKE '%sql%' OR LOWER(pe.PostTitleOrExcerpt) LIKE '%database%')
    AND uas.HasGoldBadge = 1
    AND mpa.CriticalModerationActions IS NOT NULL
    AND COALESCE(mpa.CriticalModerationActions, 0) > COALESCE(mpa.ReversalModerationActions, 0)
    AND (upt_main.TagName IS NULL OR upt_main.TagName = (SELECT MIN(upt_sub.TagName) FROM UnnestedPostTags upt_sub WHERE upt_sub.PostId = pe.PostId))
UNION ALL
SELECT
    uas.UserId,
    uas.DisplayName,
    uas.Reputation,
    uas.UserAccountAgeDays,
    uas.TotalPosts,
    uas.TotalQuestions,
    uas.TotalAnswers,
    uas.TotalCommentsMade,
    uas.TotalFavoriteReceived,
    uas.HasGoldBadge,
    pe.PostId,
    pe.PostTitleOrExcerpt,
    pe.PostTypeId,
    pe.Score AS PostScore,
    pe.ViewCount AS PostViews,
    pe.ScorePerView,
    pe.TotalEditEvents,
    pe.TotalCloseEvents,
    pe.TotalReopenEvents,
    pe.IsClosed,
    pe.IsCommunityOwned,
    mpa.TotalHistoryEvents AS PostModerationEvents,
    mpa.UniqueEditorsOrModerators AS PostUniqueEditors,
    mpa.CriticalModerationActions,
    mpa.ReversalModerationActions,
    mpa.LinkedPostsCount,
    mpa.DuplicateOfCount,
    mpa.LastCloseReason,
    ta.TagName AS PrimaryTag,
    ta.TagUseCount,
    ta.AvgPostScoreForTag,
    ta.TagPopularityQuartile,
    RANK() OVER (PARTITION BY pe.PostTypeId ORDER BY pe.Score DESC, pe.ViewCount DESC) AS PostTypeRank,
    AVG(pe.Score) OVER (PARTITION BY uas.UserId ORDER BY pe.PostCreationDate RANGE BETWEEN INTERVAL '30 days' PRECEDING AND CURRENT ROW) AS AvgScoreLast30DaysForUser,
    (SELECT COUNT(DISTINCT ph_c.UserId)
     FROM PostHistory ph_c
     WHERE ph_c.PostId = pe.PostId
       AND ph_c.PostHistoryTypeId = 10
       AND ph_c.UserId IS NOT NULL
    ) AS UniqueCloseVoters,
    (pe.Score * 2 + pe.ViewCount / 20 + pe.AnswerCount * 1 + pe.CommentCount * 1 + COALESCE(pe.FavoriteCount, 0) * 5) AS EngagementScore,
    UPPER(COALESCE(pe.PostTitleOrExcerpt, 'NO TITLE')) AS PostTitleUpper,
    'DuplicateContributor' AS PostStatusCategory
FROM UserActivitySummary uas
INNER JOIN PostEngagementMetrics pe ON uas.UserId = pe.OwnerUserId
INNER JOIN ModerationAndLinkedPosts mpa ON pe.PostId = mpa.PostId
LEFT JOIN UnnestedPostTags upt_main ON pe.PostId = upt_main.PostId
LEFT JOIN TagAnalysis ta ON upt_main.TagName = ta.TagName
WHERE
    uas.Reputation > 500
    AND uas.LastAccessDate > CURRENT_DATE - INTERVAL '1 year'
    AND pe.PostTypeId = 1
    AND mpa.DuplicateOfCount > 0
    AND pe.Score > 0
    AND uas.TotalPosts > 10
    AND (upt_main.TagName IS NULL OR upt_main.TagName = (SELECT MIN(upt_sub.TagName) FROM UnnestedPostTags upt_sub WHERE upt_sub.PostId = pe.PostId))
ORDER BY EngagementScore DESC, Reputation DESC
LIMIT 500;
