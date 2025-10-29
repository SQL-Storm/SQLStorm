WITH UserEngagement AS (
    SELECT
        u.Id AS UserId,
        u.DisplayName,
        u.Reputation,
        u.Views AS UserViews,
        u.UpVotes,
        u.DownVotes,
        COUNT(DISTINCT p.Id) AS TotalPostsOwned,
        COUNT(DISTINCT c.Id) AS TotalCommentsMade,
        COUNT(DISTINCT b.Id) AS TotalBadgesEarned,
        GREATEST(
            COALESCE(MAX(u.LastAccessDate), u.CreationDate),
            COALESCE(MAX(p.LastActivityDate), u.CreationDate),
            COALESCE(MAX(c.CreationDate), u.CreationDate)
        ) AS LastUserInteractionDate,
        DATE_PART('day', (TIMESTAMP '2024-10-01 12:34:56' - u.CreationDate)) AS AccountAgeDays,
        (u.Reputation * 0.5 + u.UpVotes * 0.2 - u.DownVotes * 0.1 + COUNT(DISTINCT b.Id) * 10) AS UserActivityScore
    FROM Users u
    LEFT JOIN Posts p ON u.Id = p.OwnerUserId
    LEFT JOIN Comments c ON u.Id = c.UserId
    LEFT JOIN Badges b ON u.Id = b.UserId
    GROUP BY u.Id, u.DisplayName, u.Reputation, u.Views, u.UpVotes, u.DownVotes, u.CreationDate, u.LastAccessDate
),
PostDetails AS (
    SELECT
        q.Id AS QuestionId,
        q.Title AS QuestionTitle,
        q.OwnerUserId AS QuestionOwnerId,
        q.CreationDate AS QuestionCreationDate,
        q.Score AS QuestionScore,
        q.ViewCount,
        q.AnswerCount,
        q.FavoriteCount,
        q.ClosedDate,
        COALESCE(q.CommunityOwnedDate, TIMESTAMP '1900-01-01 00:00:00') AS CommunityOwnedStatusDate,
        COUNT(DISTINCT ph.Id) AS TotalPostHistoryEntries,
        SUM(CASE WHEN ph.PostHistoryTypeId IN (4, 5, 6) THEN 1 ELSE 0 END) AS EditCount,
        SUM(CASE WHEN ph.PostHistoryTypeId = 10 THEN 1 ELSE 0 END) AS CloseHistoryCount,
        COUNT(DISTINCT pl_linked.RelatedPostId) AS LinkedPostsCount,
        COUNT(DISTINCT pl_duplicate.RelatedPostId) AS DuplicatePostsCount,
        q.Tags,
        AVG(CASE WHEN a.PostTypeId = 2 THEN a.Score END) AS AvgAnswerScore,
        MAX(CASE WHEN ph_owner.PostHistoryTypeId IN (5,8) AND ph_owner.UserId = q.OwnerUserId THEN ph_owner.CreationDate END) AS LastOwnerBodyEditDate
    FROM Posts q
    LEFT JOIN PostHistory ph ON q.Id = ph.PostId
    LEFT JOIN PostHistory ph_owner ON q.Id = ph_owner.PostId
    LEFT JOIN PostLinks pl_linked ON q.Id = pl_linked.PostId AND pl_linked.LinkTypeId = 1
    LEFT JOIN PostLinks pl_duplicate ON q.Id = pl_duplicate.PostId AND pl_duplicate.LinkTypeId = 3
    LEFT JOIN Posts a ON q.Id = a.ParentId
    WHERE q.PostTypeId = 1
    GROUP BY q.Id, q.Title, q.OwnerUserId, q.CreationDate, q.Score, q.ViewCount, q.AnswerCount, q.FavoriteCount, q.ClosedDate, q.CommunityOwnedDate, q.Tags
),
TagAnalysis AS (
    SELECT
        pd.QuestionId,
        TRIM(UNNEST(string_to_array(SUBSTRING(pd.Tags, 2, LENGTH(pd.Tags) - 2), '><'))) AS TagName
    FROM PostDetails pd
    WHERE pd.Tags IS NOT NULL AND LENGTH(pd.Tags) > 2
)
SELECT
    ue.DisplayName AS QuestionOwnerDisplayName,
    ue.Reputation,
    ue.UserViews,
    ue.UpVotes,
    ue.TotalBadgesEarned,
    pd.QuestionTitle,
    pd.QuestionScore,
    pd.ViewCount,
    pd.AnswerCount,
    pd.FavoriteCount,
    pd.EditCount,
    pd.CloseHistoryCount,
    pd.LinkedPostsCount,
    pd.DuplicatePostsCount,
    pd.AvgAnswerScore,
    pd.LastOwnerBodyEditDate,
    ta.TagName,
    CASE
        WHEN pd.ClosedDate IS NOT NULL AND DATE_PART('year', (TIMESTAMP '2024-10-01 12:34:56' - pd.ClosedDate)) < 1 THEN 'Recently Closed'
        WHEN pd.CommunityOwnedStatusDate > TIMESTAMP '1900-01-01 00:00:00' THEN 'Community Wiki'
        WHEN pd.AnswerCount > 0 AND COALESCE(pd.AvgAnswerScore, 0) >= 5 AND pd.FavoriteCount >= 3 THEN 'Highly Engaged & Answered'
        WHEN pd.AnswerCount = 0 AND pd.ViewCount > 500 AND pd.QuestionScore < 0 THEN 'Unanswered but Viewed & Downvoted'
        ELSE 'Active Open'
    END AS QuestionStatusCategory,
    COALESCE(
        (SELECT MAX(s.Score) FROM Comments s WHERE s.PostId = pd.QuestionId AND s.UserId = ue.UserId),
        0
    ) AS MaxOwnerCommentScore,
    (
        SELECT COUNT(DISTINCT v.UserId)
        FROM Votes v
        WHERE v.PostId = pd.QuestionId
          AND v.VoteTypeId = 2
    ) AS UpVoteUserCount,
    RANK() OVER (PARTITION BY ue.UserId ORDER BY pd.QuestionScore DESC, pd.ViewCount DESC) AS RankByOwnerQuestionScore,
    AVG(pd.QuestionScore) OVER (PARTITION BY FLOOR(ue.Reputation / 10000)) AS AvgScoreByReputationTier,
    DENSE_RANK() OVER (ORDER BY pd.ViewCount DESC, pd.QuestionScore DESC) AS GlobalQuestionViewRank,
    LAG(pd.QuestionCreationDate, 1, TIMESTAMP '1970-01-01 00:00:00') OVER (PARTITION BY ue.UserId ORDER BY pd.QuestionCreationDate) AS PreviousQuestionDate,
    (ue.UserActivityScore * 0.1 + pd.QuestionScore * 0.5 + pd.ViewCount * 0.01 + pd.AnswerCount * 2 + pd.FavoriteCount * 3 - pd.CloseHistoryCount * 5) AS OverallQuestionInfluenceScore,
    LENGTH(pd.QuestionTitle) AS TitleLength,
    LENGTH(q_body.Body) AS QuestionBodyLength,
    REPLACE(REPLACE(pd.QuestionTitle, 'SQL', 'Database'), 'Query', 'Statement') AS ReplacedTitleKeywords,
    (SELECT COUNT(DISTINCT co.UserId) FROM Comments co WHERE co.PostId = pd.QuestionId) AS DistinctCommenterCount
FROM PostDetails pd
INNER JOIN UserEngagement ue ON pd.QuestionOwnerId = ue.UserId
LEFT JOIN Posts q_body ON pd.QuestionId = q_body.Id
INNER JOIN TagAnalysis ta ON pd.QuestionId = ta.QuestionId
WHERE
    ue.AccountAgeDays > 365
    AND pd.QuestionScore > 10
    AND pd.ViewCount > 100
    AND pd.AnswerCount > 0
    AND (
        ta.TagName ILIKE '%sql%'
        OR ta.TagName ILIKE '%database%'
        OR ta.TagName ILIKE '%performance%'
    )
    AND pd.QuestionTitle NOT LIKE '%(deleted)%'
    AND pd.LastOwnerBodyEditDate IS NOT NULL
    AND NOT EXISTS (
        SELECT 1
        FROM Comments c_bad
        WHERE c_bad.PostId = pd.QuestionId
          AND c_bad.Text ILIKE '%offensive%'
          AND c_bad.Score < 0
    )
GROUP BY
    ue.UserId, ue.DisplayName, ue.Reputation, ue.UserViews, ue.UpVotes, ue.TotalBadgesEarned, ue.AccountAgeDays, ue.UserActivityScore,
    pd.QuestionId, pd.QuestionTitle, pd.QuestionScore, pd.ViewCount, pd.AnswerCount, pd.FavoriteCount, pd.EditCount,
    pd.CloseHistoryCount, pd.LinkedPostsCount, pd.DuplicatePostsCount, pd.AvgAnswerScore, pd.LastOwnerBodyEditDate,
    pd.QuestionCreationDate, pd.ClosedDate, pd.CommunityOwnedStatusDate, ta.TagName, q_body.Body

UNION ALL

SELECT
    u.DisplayName AS QuestionOwnerDisplayName,
    u.Reputation,
    u.Views AS UserViews,
    COUNT(DISTINCT v_up.UserId) AS UpVotes,
    COUNT(DISTINCT b.Id) AS TotalBadgesEarned,
    p.Title AS QuestionTitle,
    p.Score AS QuestionScore,
    p.ViewCount,
    p.AnswerCount,
    p.FavoriteCount,
    SUM(CASE WHEN ph.PostHistoryTypeId IN (4, 5, 6) THEN 1 ELSE 0 END) AS EditCount,
    SUM(CASE WHEN ph.PostHistoryTypeId = 10 THEN 1 ELSE 0 END) AS CloseHistoryCount,
    COUNT(DISTINCT pl_linked.RelatedPostId) AS LinkedPostsCount,
    COUNT(DISTINCT pl_duplicate.RelatedPostId) AS DuplicatePostsCount,
    AVG(a.Score) AS AvgAnswerScore,
    MAX(CASE WHEN ph_latest.PostHistoryTypeId IN (5,8) AND ph_latest.UserId = p.OwnerUserId THEN ph_latest.CreationDate END) AS LastOwnerBodyEditDate,
    TRIM(UNNEST(string_to_array(SUBSTRING(p.Tags, 2, LENGTH(p.Tags) - 2), '><'))) AS TagName,
    'HighCommentLowScore_Recent' AS QuestionStatusCategory,
    COALESCE(
        (SELECT MAX(s.Score) FROM Comments s WHERE s.PostId = p.Id AND s.UserId = u.Id),
        0
    ) AS MaxOwnerCommentScore,
    (
        SELECT COUNT(DISTINCT v_distinct.UserId)
        FROM Votes v_distinct
        WHERE v_distinct.PostId = p.Id
          AND v_distinct.VoteTypeId = 2
    ) AS UpVoteUserCount,
    RANK() OVER (PARTITION BY u.Id ORDER BY p.CreationDate DESC) AS RankByOwnerQuestionScore,
    AVG(p.Score) OVER (PARTITION BY FLOOR(u.Reputation / 500)) AS AvgScoreByReputationTier,
    DENSE_RANK() OVER (ORDER BY COALESCE(p.CommentCount,0) DESC, p.CreationDate DESC) AS GlobalQuestionViewRank,
    LAG(p.CreationDate, 1, TIMESTAMP '1970-01-01 00:00:00') OVER (PARTITION BY u.Id ORDER BY p.CreationDate) AS PreviousQuestionDate,
    (u.Reputation * 0.05 + p.Score * 0.2 + COALESCE(p.CommentCount,0) * 5 - p.ViewCount * 0.005) AS OverallQuestionInfluenceScore,
    LENGTH(p.Title) AS TitleLength,
    LENGTH(p.Body) AS QuestionBodyLength,
    REPLACE(REPLACE(p.Title, 'bug', 'issue'), 'error', 'problem') AS ReplacedTitleKeywords,
    (SELECT COUNT(DISTINCT co.UserId) FROM Comments co WHERE co.PostId = p.Id) AS DistinctCommenterCount
FROM Posts p
INNER JOIN Users u ON p.OwnerUserId = u.Id
LEFT JOIN PostHistory ph ON p.Id = ph.PostId
LEFT JOIN PostHistory ph_latest ON p.Id = ph_latest.PostId
LEFT JOIN PostLinks pl_linked ON p.Id = pl_linked.PostId AND pl_linked.LinkTypeId = 1
LEFT JOIN PostLinks pl_duplicate ON p.Id = pl_duplicate.PostId AND pl_duplicate.LinkTypeId = 3
LEFT JOIN Posts a ON p.Id = a.ParentId AND a.PostTypeId = 2
LEFT JOIN Badges b ON u.Id = b.UserId
LEFT JOIN Votes v_up ON p.Id = v_up.PostId AND v_up.VoteTypeId = 2
WHERE
    p.PostTypeId = 1
    AND COALESCE(p.CommentCount,0) >= 5
    AND p.Score BETWEEN -5 AND 5
    AND u.Reputation < 500
    AND DATE_PART('month', (TIMESTAMP '2024-10-01 12:34:56' - p.CreationDate)) <= 6
    AND p.Tags IS NOT NULL AND LENGTH(p.Tags) > 2
    AND NOT EXISTS (
        SELECT 1
        FROM PostHistory ph_closed
        WHERE ph_closed.PostId = p.Id
          AND ph_closed.PostHistoryTypeId = 10
    )
GROUP BY
    u.Id, u.DisplayName, u.Reputation, u.Views, p.Id, p.Title, p.Score, p.ViewCount, p.AnswerCount, p.FavoriteCount,
    p.CreationDate, p.Body, p.Tags, p.CommentCount
ORDER BY
    OverallQuestionInfluenceScore DESC, GlobalQuestionViewRank ASC;