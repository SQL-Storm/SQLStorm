WITH UserActivity AS (
    SELECT
        u.Id AS UserId,
        u.DisplayName,
        u.Reputation,
        u.CreationDate AS UserCreationDate,
        u.LastAccessDate,
        COUNT(DISTINCT b.Id) AS TotalBadges,
        MAX(CASE WHEN b.Class = 1 THEN 1 ELSE 0 END) AS HasGoldBadge,
        SUM(CASE WHEN vt.Name = 'UpMod' THEN 1 ELSE 0 END) AS TotalUpVotesGiven,
        SUM(CASE WHEN vt.Name = 'DownMod' THEN 1 ELSE 0 END) AS TotalDownVotesGiven,
        COUNT(DISTINCT p.Id) AS TotalPostsCreated,
        COUNT(DISTINCT CASE WHEN p.PostTypeId = 1 THEN p.Id END) AS TotalQuestionsCreated,
        COUNT(DISTINCT CASE WHEN p.PostTypeId = 2 THEN p.Id END) AS TotalAnswersCreated,
        SUM(p.ViewCount) AS TotalPostsViewCount,
        SUM(p.Score) AS TotalPostsScore,
        MAX(p.LastActivityDate) AS LastPostActivityDate
    FROM Users u
    LEFT JOIN Badges b ON u.Id = b.UserId
    LEFT JOIN Votes v ON u.Id = v.UserId
    LEFT JOIN VoteTypes vt ON v.VoteTypeId = vt.Id
    LEFT JOIN Posts p ON u.Id = p.OwnerUserId
    GROUP BY u.Id, u.DisplayName, u.Reputation, u.CreationDate, u.LastAccessDate
),
PostDetails AS (
    SELECT
        p.Id AS PostId,
        p.PostTypeId,
        p.OwnerUserId,
        p.CreationDate AS PostCreationDate,
        p.Score AS PostScore,
        p.ViewCount,
        COALESCE(p.AnswerCount, 0) AS AnswerCount,
        p.CommentCount AS PostCommentCount,
        p.LastActivityDate AS PostLastActivityDate,
        p.Title,
        p.Tags,
        COALESCE(array_length(string_to_array(substring(p.Tags FROM 2 FOR length(p.Tags) - 2), '><'), 1), 0) AS TagCount,
        COUNT(DISTINCT ph.Id) AS TotalHistoryRevisions,
        MAX(ph.CreationDate) AS LastHistoryEditDate,
        MAX(CASE WHEN ph.PostHistoryTypeId IN (4, 5, 6) THEN ph.CreationDate END) AS LastContentEditDate,
        SUM(CASE WHEN ph.PostHistoryTypeId = 10 THEN 1 ELSE 0 END) AS CloseHistoryCount,
        SUM(CASE WHEN ph.PostHistoryTypeId = 11 THEN 1 ELSE 0 END) AS ReopenHistoryCount,
        SUM(CASE WHEN ph.PostHistoryTypeId = 12 THEN 1 ELSE 0 END) AS DeleteHistoryCount,
        SUM(CASE WHEN ph.PostHistoryTypeId = 13 THEN 1 ELSE 0 END) AS UndeleteHistoryCount
    FROM Posts p
    LEFT JOIN PostHistory ph ON p.Id = ph.PostId
    GROUP BY p.Id, p.PostTypeId, p.OwnerUserId, p.CreationDate, p.Score, p.ViewCount, p.AnswerCount, p.CommentCount, p.LastActivityDate, p.Title, p.Tags
),
QuestionAnswerAggregates AS (
    SELECT
        q.Id AS QuestionId,
        COUNT(a.Id) AS ActualAnswerCount,
        SUM(COALESCE(a.Score, 0)) AS TotalAnswersScore,
        AVG(COALESCE(a.Score, 0)) AS AvgAnswerScore,
        MAX(a.CreationDate) AS LastAnswerDate,
        (SELECT COUNT(c.Id) FROM Comments c WHERE c.PostId = q.Id AND c.Score > 0) AS QuestionPositiveCommentCount,
        q.AcceptedAnswerId
    FROM Posts q
    LEFT JOIN Posts a ON q.Id = a.ParentId AND a.PostTypeId = 2
    WHERE q.PostTypeId = 1
    GROUP BY q.Id, q.AcceptedAnswerId
),
UserTagDiversity AS (
    SELECT
        p.OwnerUserId AS UserId,
        COUNT(DISTINCT tag) AS DistinctTagsPosted
    FROM Posts p
    CROSS JOIN LATERAL (
        SELECT unnest(string_to_array(substring(p.Tags FROM 2 FOR length(p.Tags) - 2), '><')) AS tag
    ) t
    WHERE p.PostTypeId = 1 AND p.OwnerUserId IS NOT NULL AND p.Tags IS NOT NULL AND length(trim(p.Tags)) > 2
    GROUP BY p.OwnerUserId
),
HighImpactUsersPreScore AS (
    SELECT
        ua.UserId,
        ua.DisplayName,
        ua.Reputation,
        ua.TotalBadges,
        ua.HasGoldBadge,
        ua.TotalPostsCreated,
        ua.TotalQuestionsCreated,
        ua.TotalAnswersCreated,
        COALESCE(SUM(pd.ViewCount) FILTER (WHERE pd.PostTypeId = 1), 0) AS TotalQuestionViewsOwned,
        COALESCE(SUM(pd.AnswerCount) FILTER (WHERE pd.PostTypeId = 1), 0) AS TotalQuestionAnswersOwned,
        COALESCE(SUM(pd.PostScore) FILTER (WHERE pd.PostTypeId = 1), 0) AS TotalQuestionScoreOwned,
        COALESCE(AVG(pd.TotalHistoryRevisions) FILTER (WHERE pd.PostTypeId = 1), 0) AS AvgQuestionRevisionsOwned,
        COALESCE(SUM(pd.PostScore) FILTER (WHERE pd.PostTypeId = 2), 0) AS TotalAnswerScoreOwned,
        COALESCE(utd.DistinctTagsPosted, 0) AS DistinctTagsPosted,
        COALESCE(AVG(EXTRACT(EPOCH FROM (CAST('2024-10-01 12:34:56' AS timestamp) - pd.PostLastActivityDate))), 0) AS AvgTimeSinceLastActivitySec,
        ua.LastAccessDate,
        COALESCE(ua.TotalPostsViewCount, 0) AS TotalPostsViewCount
    FROM UserActivity ua
    LEFT JOIN PostDetails pd ON ua.UserId = pd.OwnerUserId
    LEFT JOIN UserTagDiversity utd ON ua.UserId = utd.UserId
    WHERE ua.TotalPostsCreated > 0
    GROUP BY ua.UserId, ua.DisplayName, ua.Reputation, ua.TotalBadges, ua.HasGoldBadge, ua.TotalPostsCreated, ua.TotalQuestionsCreated, ua.TotalAnswersCreated, utd.DistinctTagsPosted, ua.LastAccessDate, ua.TotalPostsViewCount
)
SELECT
    h.UserId,
    h.DisplayName,
    h.Reputation,
    h.TotalBadges,
    h.DistinctTagsPosted,
    h.TotalQuestionsCreated,
    h.TotalAnswersCreated,
    h.TotalQuestionViewsOwned,
    h.TotalQuestionAnswersOwned,
    h.TotalQuestionScoreOwned,
    h.AvgQuestionRevisionsOwned,
    h.TotalAnswerScoreOwned,
    CAST(
        (h.Reputation * 0.125)
        + (h.TotalBadges * 0.75)
        + (h.DistinctTagsPosted * 2.0)
        + (h.TotalQuestionsCreated * 2.5)
        + (h.TotalAnswersCreated * 1.5)
        + (h.TotalQuestionViewsOwned * 0.0005)
        + (h.TotalQuestionAnswersOwned * 3.5)
        + (h.TotalQuestionScoreOwned * 0.9)
        + (h.TotalAnswerScoreOwned * 0.7)
        - (h.AvgTimeSinceLastActivitySec / (3600.0 * 24 * 30 * 6.0))
        + (CASE WHEN h.HasGoldBadge > 0 THEN 150.0 ELSE 0.0 END)
        + (
            SELECT COALESCE(SUM(qaa.TotalAnswersScore), 0)
            FROM QuestionAnswerAggregates qaa
            WHERE qaa.AcceptedAnswerId IN (
                SELECT pd_ans.PostId
                FROM PostDetails pd_ans
                WHERE pd_ans.OwnerUserId = h.UserId AND pd_ans.PostTypeId = 2
            )
        ) * 0.05
    AS numeric(18,4)) AS ImpactScore,
    RANK() OVER (ORDER BY h.Reputation DESC, h.TotalBadges DESC) AS RankByReputationBadges,
    DENSE_RANK() OVER (ORDER BY h.TotalQuestionsCreated DESC, h.TotalAnswersCreated DESC) AS RankByContributions,
    NTILE(5) OVER (ORDER BY h.TotalQuestionViewsOwned DESC) AS TopViewedQuestionsQuintile,
    LAG(h.DisplayName, 1, 'NO_PREV_USER') OVER (ORDER BY
        CAST(
            (h.Reputation * 0.125)
            + (h.TotalBadges * 0.75)
            + (h.DistinctTagsPosted * 2.0)
            + (h.TotalQuestionsCreated * 2.5)
            + (h.TotalAnswersCreated * 1.5)
            + (h.TotalQuestionViewsOwned * 0.0005)
            + (h.TotalQuestionAnswersOwned * 3.5)
            + (h.TotalQuestionScoreOwned * 0.9)
            + (h.TotalAnswerScoreOwned * 0.7)
            - (h.AvgTimeSinceLastActivitySec / (3600.0 * 24 * 30 * 6.0))
            + (CASE WHEN h.HasGoldBadge > 0 THEN 150.0 ELSE 0.0 END)
        AS numeric(18,4)) DESC
    ) AS PreviousImpactfulUser,
    LEAD(h.DisplayName, 1, 'NO_NEXT_USER') OVER (ORDER BY
        CAST(
            (h.Reputation * 0.125)
            + (h.TotalBadges * 0.75)
            + (h.DistinctTagsPosted * 2.0)
            + (h.TotalQuestionsCreated * 2.5)
            + (h.TotalAnswersCreated * 1.5)
            + (h.TotalQuestionViewsOwned * 0.0005)
            + (h.TotalQuestionAnswersOwned * 3.5)
            + (h.TotalQuestionScoreOwned * 0.9)
            + (h.TotalAnswerScoreOwned * 0.7)
            - (h.AvgTimeSinceLastActivitySec / (3600.0 * 24 * 30 * 6.0))
            + (CASE WHEN h.HasGoldBadge > 0 THEN 150.0 ELSE 0.0 END)
        AS numeric(18,4)) DESC
    ) AS NextImpactfulUser,
    (
        SELECT
            STRING_AGG(pd_closed.Title || ' [Closed: ' || COALESCE(crt.Name, 'Unknown') || ']', ' | ')
        FROM PostDetails pd_closed
        INNER JOIN PostHistory ph_closed ON pd_closed.PostId = ph_closed.PostId
        LEFT JOIN CloseReasonTypes crt ON CAST(ph_closed.Comment AS smallint) = crt.Id
        WHERE pd_closed.OwnerUserId = h.UserId
          AND pd_closed.PostTypeId = 1
          AND ph_closed.PostHistoryTypeId = 10
          AND pd_closed.PostCreationDate > (CAST('2024-10-01 12:34:56' AS timestamp) - INTERVAL '1 year')
        GROUP BY pd_closed.OwnerUserId
        LIMIT 3
    ) AS RecentClosedQuestionsOwnedInfo,
    COALESCE((
        SELECT SUM(c.Score)
        FROM Comments c
        WHERE c.UserId = h.UserId AND c.CreationDate > (CAST('2024-10-01 12:34:56' AS timestamp) - INTERVAL '6 months')
    ), 0) AS TotalRecentCommentsScoreByUser,
    (
        SELECT COUNT(DISTINCT pl.RelatedPostId)
        FROM PostLinks pl
        INNER JOIN Posts p_link_src ON pl.PostId = p_link_src.Id
        WHERE p_link_src.OwnerUserId = h.UserId AND pl.LinkTypeId = 1
          AND p_link_src.CreationDate > (CAST('2024-10-01 12:34:56' AS timestamp) - INTERVAL '2 years')
    ) AS TotalLinkedQuestionsInitiated,
    CASE WHEN h.UserId IN (SELECT Id FROM Users WHERE WebsiteUrl IS NOT NULL AND length(trim(WebsiteUrl)) > 0) THEN TRUE ELSE FALSE END AS HasWebsiteProfile,
    h.LastAccessDate
FROM HighImpactUsersPreScore h
WHERE h.Reputation >= 1000
  AND h.TotalQuestionsCreated > 0
  AND h.TotalPostsViewCount > 500
  AND (h.DisplayName LIKE 'A%' OR h.DisplayName LIKE 'S%')
ORDER BY ImpactScore DESC, h.Reputation DESC, h.LastAccessDate DESC
LIMIT 50;