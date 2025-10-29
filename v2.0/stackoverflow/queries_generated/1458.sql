-- {"query": "1458.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gemini-2.5-flash", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2111, "output_tokens": 3593} 

WITH PostEventStats AS (
    -- Aggregate history and comment data for *any* post
    SELECT
        p.Id AS PostId,
        COUNT(ph.Id) AS TotalHistoryEvents,
        SUM(CASE WHEN ph.PostHistoryTypeId IN (4, 5, 6, 8) THEN 1 ELSE 0 END) AS EditCount, -- Include body/tags rollback as edits
        SUM(CASE WHEN ph.PostHistoryTypeId = 10 THEN 1 ELSE 0 END) AS CloseCount,
        SUM(CASE WHEN ph.PostHistoryTypeId = 11 THEN 1 ELSE 0 END) AS ReopenCount,
        SUM(CASE WHEN ph.PostHistoryTypeId = 12 THEN 1 ELSE 0 END) AS DeleteCount,
        SUM(CASE WHEN ph.PostHistoryTypeId = 13 THEN 1 ELSE 0 END) AS UndeleteCount,
        COUNT(c.Id) AS TotalCommentsMade,
        COALESCE(AVG(c.Score), 0.0) AS AvgCommentScore,
        MAX(CASE WHEN ph.PostHistoryTypeId IN (14, 15, 19, 20) THEN 1 ELSE 0 END) AS HasModeratorIntervention
    FROM Posts p
    LEFT JOIN PostHistory ph ON p.Id = ph.PostId
    LEFT JOIN Comments c ON p.Id = c.PostId
    GROUP BY p.Id
),
UserOverallStats AS (
    -- Summarize user activity and reputation trends
    SELECT
        u.Id AS UserId,
        u.Reputation,
        u.CreationDate AS UserCreationDate,
        u.LastAccessDate,
        COUNT(DISTINCT p.Id) AS UserTotalPosts,
        SUM(CASE WHEN p.PostTypeId = 1 THEN 1 ELSE 0 END) AS UserQuestionCount,
        SUM(CASE WHEN p.PostTypeId = 2 THEN 1 ELSE 0 END) AS UserAnswerCount,
        SUM(p.Score) AS UserTotalPostScore,
        MAX(p.CreationDate) AS UserLastPostDate,
        COUNT(b.Id) AS UserBadgeCount,
        COALESCE(AVG(CASE WHEN p.PostTypeId = 2 THEN p.Score ELSE NULL END), 0.0) AS UserAvgAnswerScore,
        COUNT(DISTINCT CASE WHEN v.VoteTypeId = 2 THEN v.PostId END) AS UserUpvotedPosts,
        COUNT(DISTINCT CASE WHEN v.VoteTypeId = 3 THEN v.PostId END) AS UserDownvotedPosts,
        SUM(CASE WHEN p.PostTypeId = 2 AND p_q.AcceptedAnswerId = p.Id THEN 1 ELSE 0 END) AS UserAcceptedAnswers
    FROM Users u
    LEFT JOIN Posts p ON u.Id = p.OwnerUserId
    LEFT JOIN Posts p_q ON p.PostTypeId = 2 AND p.ParentId = p_q.Id -- Join to parent question for accepted answer check
    LEFT JOIN Badges b ON u.Id = b.UserId
    LEFT JOIN Votes v ON u.Id = v.UserId
    GROUP BY u.Id, u.Reputation, u.CreationDate, u.LastAccessDate
),
TagPrimaryInfo AS (
    -- Extract and aggregate info for the *first* tag of each question
    SELECT
        p.Id AS PostId,
        (string_to_array(SUBSTRING(p.Tags, 2, LENGTH(p.Tags) - 2), '><'))[1] AS PrimaryTagName,
        t.Id AS PrimaryTagId,
        t.Count AS PrimaryTagQuestionCount,
        t.IsModeratorOnly AS PrimaryTagIsModeratorOnly
    FROM Posts p
    JOIN Tags t ON (string_to_array(SUBSTRING(p.Tags, 2, LENGTH(p.Tags) - 2), '><'))[1] = t.TagName
    WHERE p.PostTypeId = 1 AND p.Tags IS NOT NULL AND LENGTH(p.Tags) > 2
)
-- UNION ALL Part 1: Interesting Questions - potentially controversial, highly engaged, or influential
SELECT
    'Question' AS PostTypeCategory,
    q.Id AS PostId,
    q.Title AS PostTitle,
    q.CreationDate AS PostCreationDate,
    q.Score AS PostScore,
    q.ViewCount AS PostViewCount,
    q.AnswerCount,
    q.CommentCount AS PostCommentCount,
    q.FavoriteCount,
    COALESCE(q.OwnerDisplayName, u_owner.DisplayName, 'Community User') AS OwnerDisplayName,
    u_owner.Id AS OwnerUserId,
    u_owner.Reputation AS OwnerReputation,
    uos_owner.UserQuestionCount AS OwnerTotalQuestions,
    uos_owner.UserAnswerCount AS OwnerTotalAnswers,
    uos_owner.UserBadgeCount AS OwnerTotalBadges,
    EXTRACT(DAY FROM (NOW() - u_owner.LastAccessDate)) AS DaysSinceOwnerLastAccess,
    pes.EditCount,
    pes.CloseCount,
    pes.ReopenCount,
    pes.TotalCommentsMade AS AggregatedCommentCount,
    pes.AvgCommentScore,
    CASE WHEN pes.HasModeratorIntervention = 1 THEN 'Yes' ELSE 'No' END AS HasModeratorActivityFlag,
    CASE
        WHEN q.ClosedDate IS NOT NULL AND pes.ReopenCount > 0 THEN 'Reopened'
        WHEN q.ClosedDate IS NOT NULL AND pes.ReopenCount = 0 THEN 'Closed'
        WHEN q.AcceptedAnswerId IS NOT NULL THEN 'Answered & Accepted'
        WHEN q.AnswerCount > 0 THEN 'Answered'
        ELSE 'Open'
    END AS PostStatus,
    ti.PrimaryTagName AS RelevantTagName,
    ti.PrimaryTagQuestionCount AS RelevantTagCount,
    (
        SELECT COUNT(b.Id)
        FROM Badges b
        WHERE b.UserId = q.OwnerUserId
          AND b.Name IN ('Generalist', 'Enthusiast') -- Example correlated subquery: owner badges since post creation
          AND b.Date >= q.CreationDate
    ) AS OwnerSpecificBadgesSincePost,
    RANK() OVER (PARTITION BY ti.PrimaryTagName ORDER BY q.Score DESC, q.CreationDate ASC) AS RankInRelevantTagByScore,
    NTILE(5) OVER (ORDER BY q.ViewCount DESC, q.Score DESC) AS ViewScoreQuintile,
    LAG(q.Score, 1, 0) OVER (PARTITION BY q.OwnerUserId ORDER BY q.CreationDate) AS PreviousPostScoreByOwner,
    SUM(q.Score) OVER (PARTITION BY u_owner.Id ORDER BY q.CreationDate ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW) AS CumulativeOwnerPostScore,
    COALESCE(q.FavoriteCount, 0) + (COALESCE(q.AnswerCount, 0) * 3) + (COALESCE(q.CommentCount, 0) * 1) + (pes.EditCount * 0.5) AS CalculatedEngagementScore,
    ABS(q.Score - COALESCE(q_acc_ans.Score, 0)) AS ScoreDifferenceWithAcceptedAnswer,
    (q.ViewCount * 1.0 / NULLIF(q.Score, 0)) AS ViewsPerScoreRatio,
    (EXTRACT(EPOCH FROM (NOW() - q.CreationDate)) / 3600.0 / 24.0) AS DaysSinceCreation,
    SUBSTRING(q.Body, 1, 150) AS BodyExcerpt,
    (q.Body LIKE '%<img %' OR q.Body LIKE '%<a href="http%') AS HasImagesOrExternalLinks,
    q.Body LIKE '%bug%' OR q.Title LIKE '%bug%' AS IsBugReportLike,
    'N/A' AS ParentPostTitle,
    NULL AS TimeToAcceptAnswer,
    NULL AS ParentOwnerReputation,
    (uos_owner.UserAcceptedAnswers * 1.0 / NULLIF(uos_owner.UserAnswerCount, 0)) AS OwnerAcceptedAnswerRate, -- Owner's answer acceptance rate
    NULL AS LinkToParentType,
    q.CommunityOwnedDate IS NOT NULL AS IsCommunityOwned
FROM Posts q
LEFT JOIN Users u_owner ON q.OwnerUserId = u_owner.Id
LEFT JOIN PostEventStats pes ON q.Id = pes.PostId
LEFT JOIN UserOverallStats uos_owner ON u_owner.Id = uos_owner.UserId
LEFT JOIN Posts q_acc_ans ON q.AcceptedAnswerId = q_acc_ans.Id
LEFT JOIN TagPrimaryInfo ti ON q.Id = ti.PostId
WHERE
    q.PostTypeId = 1
    AND q.CreationDate >= '2023-01-01'
    AND q.Score > 5
    AND q.ViewCount > 500
    AND (pes.EditCount > 2 OR pes.CloseCount > 0 OR q.FavoriteCount > 10)
    AND u_owner.Reputation > 5000
    AND (
        (q.ClosedDate IS NULL AND q.AnswerCount >= 1)
        OR (q.ClosedDate IS NOT NULL AND pes.ReopenCount > 0 AND pes.ReopenCount > pes.CloseCount / 2.0)
        OR (q.Score > 50 AND q.FavoriteCount > 5 AND (SELECT COUNT(DISTINCT c_sub.Id) FROM Comments c_sub WHERE c_sub.PostId = q.Id) > 5)
    )
    AND NOT EXISTS (
        SELECT 1 FROM Comments c_sub WHERE c_sub.PostId = q.Id AND c_sub.Text ILIKE '%please delete%'
    )

UNION ALL

-- UNION ALL Part 2: Interesting Answers - highly rated, controversial, or accepted quickly
SELECT
    'Answer' AS PostTypeCategory,
    a.Id AS PostId,
    p_parent.Title AS PostTitle,
    a.CreationDate AS PostCreationDate,
    a.Score AS PostScore,
    NULL AS PostViewCount,
    NULL AS AnswerCount,
    a.CommentCount AS PostCommentCount,
    a.FavoriteCount,
    COALESCE(a.OwnerDisplayName, u_owner_ans.DisplayName, 'Anonymous') AS OwnerDisplayName,
    u_owner_ans.Id AS OwnerUserId,
    u_owner_ans.Reputation AS OwnerReputation,
    uos_owner_ans.UserQuestionCount AS OwnerTotalQuestions,
    uos_owner_ans.UserAnswerCount AS OwnerTotalAnswers,
    uos_owner_ans.UserBadgeCount AS OwnerTotalBadges,
    EXTRACT(DAY FROM (NOW() - u_owner_ans.LastAccessDate)) AS DaysSinceOwnerLastAccess,
    pes.EditCount,
    NULL AS CloseCount,
    NULL AS ReopenCount,
    pes.TotalCommentsMade AS AggregatedCommentCount,
    pes.AvgCommentScore,
    CASE WHEN pes.HasModeratorIntervention = 1 THEN 'Yes' ELSE 'No' END AS HasModeratorActivityFlag,
    CASE
        WHEN p_parent.AcceptedAnswerId = a.Id THEN 'Accepted'
        WHEN a.Score < 0 THEN 'Highly Downvoted'
        ELSE 'Active'
    END AS PostStatus,
    (string_to_array(SUBSTRING(p_parent.Tags, 2, LENGTH(p_parent.Tags) - 2), '><'))[1] AS RelevantTagName,
    NULL AS RelevantTagCount,
    (
        SELECT COUNT(b.Id)
        FROM Badges b
        WHERE b.UserId = a.OwnerUserId
          AND b.Name IN ('Great Answer', 'Pundit') -- Another correlated subquery: answerer badges
          AND b.Date >= a.CreationDate
    ) AS OwnerSpecificBadgesSincePost,
    RANK() OVER (PARTITION BY p_parent.Id ORDER BY a.Score DESC, a.CreationDate ASC) AS RankInParentQuestionByScore,
    NTILE(5) OVER (ORDER BY a.Score DESC, a.CreationDate ASC) AS ScoreQuintile,
    LAG(a.Score, 1, 0) OVER (PARTITION BY a.OwnerUserId ORDER BY a.CreationDate) AS PreviousPostScoreByOwner,
    SUM(a.Score) OVER (PARTITION BY u_owner_ans.Id ORDER BY a.CreationDate ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW) AS CumulativeOwnerPostScore,
    COALESCE(a.FavoriteCount, 0) + (COALESCE(a.CommentCount, 0) * 2) + (pes.EditCount * 1.5) AS CalculatedEngagementScore,
    ABS(a.Score - p_parent.Score) AS ScoreDifferenceWithQuestion,
    (a.Score * 1.0 / NULLIF(uos_owner_ans.UserAvgAnswerScore, 0)) AS ScoreRatioToOwnerAvgAnswer,
    (EXTRACT(EPOCH FROM (NOW() - a.CreationDate)) / 3600.0 / 24.0) AS DaysSinceCreation,
    SUBSTRING(a.Body, 1, 150) AS BodyExcerpt,
    (a.Body LIKE '%<a href="http%') AS HasImagesOrExternalLinks,
    a.Body LIKE '%solution%' OR a.Body LIKE '%fix%' AS IsBugReportLike,
    p_parent.Title AS ParentPostTitle,
    CASE
        WHEN p_parent.AcceptedAnswerId = a.Id THEN EXTRACT(HOUR FROM (a.CreationDate - p_parent.CreationDate))
        ELSE NULL
    END AS TimeToAcceptAnswer,
    u_parent_owner.Reputation AS ParentOwnerReputation,
    (uos_owner_ans.UserAcceptedAnswers * 1.0 / NULLIF(uos_owner_ans.UserAnswerCount, 0)) AS OwnerAcceptedAnswerRate,
    lt.Name AS LinkToParentType,
    a.CommunityOwnedDate IS NOT NULL AS IsCommunityOwned
FROM Posts a
JOIN Posts p_parent ON a.ParentId = p_parent.Id
LEFT JOIN Users u_owner_ans ON a.OwnerUserId = u_owner_ans.Id
LEFT JOIN PostEventStats pes ON a.Id = pes.PostId
LEFT JOIN UserOverallStats uos_owner_ans ON u_owner_ans.Id = uos_owner_ans.UserId
LEFT JOIN Users u_parent_owner ON p_parent.OwnerUserId = u_parent_owner.Id
LEFT JOIN PostLinks pl ON a.Id = pl.RelatedPostId AND pl.LinkTypeId = 1 -- Linked FROM an answer TO a question
LEFT JOIN LinkTypes lt ON pl.LinkTypeId = lt.Id
WHERE
    a.PostTypeId = 2
    AND a.CreationDate >= '2023-01-01'
    AND a.Score > 10
    AND (pes.EditCount > 1 OR pes.TotalCommentsMade > 3)
    AND u_owner_ans.Reputation > 2000
    AND (
        (p_parent.AcceptedAnswerId = a.Id AND EXTRACT(HOUR FROM (a.CreationDate - p_parent.CreationDate)) <= 24) -- Accepted within 24 hours
        OR (a.Score > 20 AND uos_owner_ans.UserAvgAnswerScore > 15)
        OR (p_parent.Title ILIKE '%performance%' AND a.Body ILIKE '%optimization%' AND a.Score > 5)
    )
ORDER BY PostCreationDate DESC, CalculatedEngagementScore DESC
LIMIT 1000;
