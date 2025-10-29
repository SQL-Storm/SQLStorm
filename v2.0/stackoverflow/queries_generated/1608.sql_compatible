WITH UserActivity AS (
    SELECT
        u.Id AS UserId,
        u.DisplayName,
        u.Reputation,
        u.CreationDate AS UserCreationDate,
        COUNT(DISTINCT p.Id) AS TotalPostsOwned,
        COUNT(DISTINCT CASE WHEN p.PostTypeId = 1 THEN p.Id END) AS QuestionsAsked,
        COUNT(DISTINCT c.Id) AS TotalCommentsMade,
        SUM(CASE WHEN v.VoteTypeId = 2 THEN 1 ELSE 0 END) AS TotalUpVotesGiven,
        SUM(CASE WHEN v.VoteTypeId = 3 THEN 1 ELSE 0 END) AS TotalDownVotesGiven,
        SUM(COALESCE(p.Score, 0)) AS TotalPostsScoreReceived,
        SUM(COALESCE(p.ViewCount, 0)) AS TotalPostsViewCount,
        ((CAST(COUNT(DISTINCT p.Id) AS DECIMAL) * 0.4) +
         (CAST(COUNT(DISTINCT c.Id) AS DECIMAL) * 0.3) +
         (CAST(SUM(CASE WHEN v.VoteTypeId = 2 THEN 1 ELSE 0 END) AS DECIMAL) * 0.15) +
         (CAST(SUM(COALESCE(p.FavoriteCount, 0)) AS DECIMAL) * 0.15)) AS EngagementScore,
        MAX(p.LastActivityDate) AS LastPostActivityDate
    FROM Users u
    LEFT JOIN Posts p ON u.Id = p.OwnerUserId
    LEFT JOIN Comments c ON u.Id = c.UserId
    LEFT JOIN Votes v ON u.Id = v.UserId
    WHERE u.CreationDate >= TIMESTAMP '2020-01-01'
    GROUP BY u.Id, u.DisplayName, u.Reputation, u.CreationDate
),
PostDetailsExtended AS (
    SELECT
        p.Id AS PostId,
        p.PostTypeId,
        p.OwnerUserId,
        p.Title,
        p.CreationDate AS PostCreationDate,
        p.Score AS CurrentScore,
        p.ViewCount,
        p.AnswerCount,
        p.CommentCount,
        p.FavoriteCount,
        p.ClosedDate,
        p.LastEditDate,
        p.LastActivityDate,
        ph_initial_body.CreationDate AS InitialBodyCreationDate,
        ph_initial_body.Text AS InitialBodyText,
        ph_initial_title.Text AS InitialTitleText,
        -- Standard SQL aggregation of tag names into a single string (no DISTINCT within ORDER BY in many dialects).
        STRING_AGG(t.TagName, '><' ORDER BY t.TagName) AS AggregatedTags,
        COUNT(DISTINCT ph.Id) AS TotalHistoryEvents,
        SUM(CASE WHEN ph.PostHistoryTypeId IN (4, 5, 6) THEN 1 ELSE 0 END) AS TotalEditCount,
        SUM(CASE WHEN ph.PostHistoryTypeId = 10 THEN 1 ELSE 0 END) AS TotalCloseVotes,
        SUM(CASE WHEN ph.PostHistoryTypeId = 11 THEN 1 ELSE 0 END) AS TotalReopenVotes,
        MAX(CASE WHEN ph.PostHistoryTypeId = 10 AND ph.Comment IS NOT NULL THEN CAST(ph.Comment AS INT) ELSE NULL END) AS LastCloseReasonTypeId,
        COALESCE(LENGTH(ph_initial_body.Text), 0) AS InitialPostBodyLength,
        (SELECT COUNT(DISTINCT cmt.Id)
         FROM Comments cmt
         WHERE cmt.PostId = p.Id
           AND (p.LastEditDate IS NULL OR cmt.CreationDate > p.LastEditDate)
           AND (cmt.UserId IS DISTINCT FROM p.OwnerUserId)
        ) AS CommentsAfterOwnerEdit,
        -- Use timestampdiff for dialects that support it; fallback to EXTRACT(EPOCH...) where appropriate could be needed per dialect.
        -- Here use generic: (EXTRACT(EPOCH FROM p.LastActivityDate) - EXTRACT(EPOCH FROM p.CreationDate)) / 3600
        ((EXTRACT(EPOCH FROM p.LastActivityDate) - EXTRACT(EPOCH FROM p.CreationDate)) / 3600) AS HoursSinceCreationToLastActivity,
        LAG(p.Score, 1, 0) OVER (PARTITION BY p.OwnerUserId ORDER BY p.CreationDate) AS ScoreOfPreviousPostByOwner,
        AVG(p.Score) OVER (PARTITION BY p.PostTypeId ORDER BY p.CreationDate ROWS BETWEEN 5 PRECEDING AND CURRENT ROW) AS MovingAvgScoreForPostType,
        RANK() OVER (PARTITION BY p.PostTypeId ORDER BY p.Score DESC, p.ViewCount DESC) AS RankWithinPostTypeByPerformance
    FROM Posts p
    LEFT JOIN PostHistory ph_initial_body ON p.Id = ph_initial_body.PostId AND ph_initial_body.PostHistoryTypeId = 2
    LEFT JOIN PostHistory ph_initial_title ON p.Id = ph_initial_title.PostId AND ph_initial_title.PostHistoryTypeId = 1
    LEFT JOIN PostHistory ph ON p.Id = ph.PostId
    LEFT JOIN Tags t ON p.Tags LIKE '%' || '<' || t.TagName || '>' || '%'
    WHERE p.PostTypeId IN (1, 2)
      AND p.CreationDate >= TIMESTAMP '2020-01-01'
    GROUP BY
        p.Id, p.PostTypeId, p.OwnerUserId, p.Title, p.CreationDate, p.Score, p.ViewCount, p.AnswerCount, p.CommentCount,
        p.FavoriteCount, p.ClosedDate, p.LastEditDate, p.LastActivityDate, ph_initial_body.CreationDate,
        ph_initial_body.Text, ph_initial_title.Text
),
ModerationActions AS (
    SELECT
        ph.PostId,
        ph.CreationDate AS ActionDate,
        ph.PostHistoryTypeId,
        cr.Name AS CloseReasonName,
        ph.UserId AS ActionUserId,
        EXTRACT(EPOCH FROM (ph.CreationDate - LAG(ph.CreationDate, 1, ph.CreationDate) OVER (PARTITION BY ph.PostId ORDER BY ph.CreationDate))) / 60 AS MinutesSincePreviousHistoryEvent,
        MAX(CASE WHEN ph.PostHistoryTypeId = 10 THEN 'Closed'
                 WHEN ph.PostHistoryTypeId = 11 THEN 'Reopened'
                 ELSE 'Other' END) OVER (PARTITION BY ph.PostId) AS FinalModerationState
    FROM PostHistory ph
    LEFT JOIN CloseReasonTypes cr ON ph.PostHistoryTypeId = 10 AND ph.Comment = CAST(cr.Id AS VARCHAR)
    WHERE ph.PostHistoryTypeId IN (10, 11)
      AND ph.CreationDate >= TIMESTAMP '2020-01-01'
)
SELECT
    ua.UserId,
    ua.DisplayName,
    ua.Reputation,
    ua.EngagementScore,
    ua.QuestionsAsked,
    COALESCE(pde.PostId, -1) AS AnalyzedPostId,
    pde.PostTypeId,
    pde.Title,
    pde.PostCreationDate,
    pde.CurrentScore,
    pde.ViewCount,
    pde.AggregatedTags,
    pde.TotalEditCount,
    pde.TotalCloseVotes,
    pde.TotalReopenVotes,
    ma.CloseReasonName AS LastClosureReason,
    ma.ActionDate AS LastClosureDate,
    pde.CommentsAfterOwnerEdit,
    pde.ScoreOfPreviousPostByOwner,
    pde.MovingAvgScoreForPostType,
    pde.RankWithinPostTypeByPerformance,
    NTILE(10) OVER (ORDER BY ua.EngagementScore DESC) AS EngagementDecile,
    (SELECT AVG(q.Score)
     FROM Posts q
     WHERE q.OwnerUserId = ua.UserId
       AND q.PostTypeId = 1
       AND q.CreationDate BETWEEN pde.PostCreationDate - INTERVAL '30' DAY AND pde.PostCreationDate + INTERVAL '30' DAY
       AND q.Id != pde.PostId
    ) AS AvgPeerQuestionScoreAroundCreation,
    CASE
        WHEN pde.ClosedDate IS NOT NULL AND pde.TotalReopenVotes = 0 THEN 'Closed_Never_Reopened'
        WHEN pde.ClosedDate IS NOT NULL AND pde.TotalReopenVotes > 0 THEN 'Closed_Then_Reopened'
        WHEN pde.PostTypeId = 1 AND pde.AnswerCount = 0 AND pde.ViewCount > 500 AND pde.PostCreationDate < (TIMESTAMP '2024-10-01 12:34:56' - INTERVAL '90' DAY) THEN 'Unanswered_HighlyViewed_Old'
        WHEN pde.OwnerUserId IS NULL THEN 'Community_Owned_Or_Deleted_User'
        ELSE 'Active_Or_Answered_Post'
    END AS PostLifecycleStatus,
    b.Name AS FirstGoldBadgeName,
    b.Date AS FirstGoldBadgeDate,
    'Main Analysis Branch' AS QueryBranchIdentifier
FROM UserActivity ua
LEFT JOIN PostDetailsExtended pde ON ua.UserId = pde.OwnerUserId
LEFT JOIN ModerationActions ma ON pde.PostId = ma.PostId AND ma.PostHistoryTypeId = 10 AND ma.ActionDate = (
    SELECT MAX(ma_inner.ActionDate) FROM ModerationActions ma_inner
    WHERE ma_inner.PostId = pde.PostId AND ma_inner.PostHistoryTypeId = 10
)
LEFT JOIN (
    SELECT UserId, Name, Date
    FROM (
        SELECT UserId, Name, Date,
               ROW_NUMBER() OVER (PARTITION BY UserId ORDER BY Date) AS rn
        FROM Badges
        WHERE Class = 1
    ) t
    WHERE rn = 1
) b ON ua.UserId = b.UserId
WHERE
    (ua.EngagementScore > 100 OR ua.Reputation > 5000)
    AND (pde.PostId IS NULL OR (pde.CurrentScore >= 0 AND pde.ViewCount >= 50 AND pde.InitialPostBodyLength > 100))
    AND (pde.AggregatedTags IS NULL OR (pde.AggregatedTags NOT LIKE '%<sql>%') OR (pde.AggregatedTags LIKE '%<postgresql>%'))
    AND (ua.DisplayName NOT LIKE '%test%' OR ua.DisplayName IS NULL)
    AND (pde.LastCloseReasonTypeId NOT IN (103, 104, 105) OR pde.LastCloseReasonTypeId IS NULL)
UNION ALL
SELECT
    u.Id AS UserId,
    u.DisplayName,
    u.Reputation,
    NULL AS EngagementScore,
    NULL AS QuestionsAsked,
    p.Id AS AnalyzedPostId,
    p.PostTypeId,
    p.Title,
    p.CreationDate AS PostCreationDate,
    p.Score AS CurrentScore,
    p.ViewCount,
    STRING_AGG(t.TagName, '><' ORDER BY t.TagName) AS AggregatedTags,
    NULL AS TotalEditCount,
    NULL AS TotalCloseVotes,
    NULL AS TotalReopenVotes,
    NULL AS LastClosureReason,
    NULL AS LastClosureDate,
    NULL AS CommentsAfterOwnerEdit,
    NULL AS ScoreOfPreviousPostByOwner,
    NULL AS MovingAvgScoreForPostType,
    NULL AS RankWithinPostTypeByPerformance,
    NULL AS EngagementDecile,
    (SELECT AVG(sub_p.Score) FROM Posts sub_p WHERE sub_p.ParentId = p.Id) AS AvgAnswerScoreForQuestion,
    CASE
        WHEN COUNT(DISTINCT pl.RelatedPostId) > 0 THEN 'Has_Linked_Posts'
        WHEN p.Score > 1000 THEN 'Very_High_Score_Post'
        ELSE 'Other_Linked_Post_Type'
    END AS PostLifecycleStatus,
    NULL AS FirstGoldBadgeName,
    NULL AS FirstGoldBadgeDate,
    'Linked Post Analysis Branch' AS QueryBranchIdentifier
FROM Posts p
LEFT JOIN PostLinks pl ON p.Id = pl.PostId AND pl.LinkTypeId = 1
LEFT JOIN Users u ON p.OwnerUserId = u.Id
LEFT JOIN Tags t ON p.Tags LIKE '%' || '<' || t.TagName || '>' || '%'
WHERE
    p.PostTypeId = 1
    AND p.Score > 500
    AND p.CreationDate BETWEEN TIMESTAMP '2018-01-01' AND TIMESTAMP '2021-12-31'
    AND p.AcceptedAnswerId IS NOT NULL
    AND (pl.Id IS NOT NULL OR p.FavoriteCount > 50)
GROUP BY
    u.Id, u.DisplayName, u.Reputation, p.Id, p.PostTypeId, p.Title, p.CreationDate, p.Score, p.ViewCount, p.AcceptedAnswerId, p.FavoriteCount
HAVING COUNT(DISTINCT pl.RelatedPostId) > 1 OR p.FavoriteCount > 100
ORDER BY Reputation DESC, EngagementScore DESC NULLS LAST, CurrentScore DESC, PostCreationDate ASC;