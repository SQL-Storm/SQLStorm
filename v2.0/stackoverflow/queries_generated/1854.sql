-- {"query": "1854.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gemini-2.5-flash", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2111, "output_tokens": 3170} 

WITH UserActivitySummary AS (
    SELECT
        u.Id AS UserId,
        u.DisplayName,
        u.Reputation,
        u.CreationDate AS UserCreationDate,
        u.Views AS UserProfileViews,
        u.UpVotes,
        u.DownVotes,
        COUNT(DISTINCT p.Id) AS TotalPosts,
        COUNT(DISTINCT c.Id) AS TotalComments,
        COUNT(DISTINCT b.Id) AS TotalBadges,
        SUM(p.Score) FILTER (WHERE p.PostTypeId = 1) AS TotalQuestionScore,
        SUM(p.Score) FILTER (WHERE p.PostTypeId = 2) AS TotalAnswerScore,
        AVG(p.Score) AS AvgPostScore,
        MAX(p.CreationDate) AS LatestPostDate,
        NTILE(5) OVER (ORDER BY u.Reputation DESC, u.UpVotes DESC) AS ReputationTier
    FROM Users u
    LEFT JOIN Posts p ON u.Id = p.OwnerUserId
    LEFT JOIN Comments c ON u.Id = c.UserId
    LEFT JOIN Badges b ON u.Id = b.UserId
    GROUP BY u.Id, u.DisplayName, u.Reputation, u.CreationDate, u.Views, u.UpVotes, u.DownVotes
),
PostDetails AS (
    SELECT
        p.Id AS PostId,
        p.PostTypeId,
        p.OwnerUserId,
        p.AcceptedAnswerId,
        p.ParentId,
        p.Title,
        p.Body,
        p.CreationDate AS PostCreationDate,
        p.Score,
        p.ViewCount,
        p.AnswerCount,
        p.CommentCount,
        p.FavoriteCount,
        p.LastActivityDate,
        p.ClosedDate,
        -- Count of significant edits (title, body, tags) using correlated subquery
        (SELECT COUNT(ph.Id) FROM PostHistory ph WHERE ph.PostId = p.Id AND ph.PostHistoryTypeId IN (4, 5, 6)) AS EditCount,
        -- Last edit date using correlated subquery
        (SELECT MAX(ph.CreationDate) FROM PostHistory ph WHERE ph.PostId = p.Id AND ph.PostHistoryTypeId IN (4, 5, 6)) AS LastEditDate_Calculated,
        COALESCE(p.LastEditorDisplayName, 'Community') AS LastEditorDisplayName_Coalesced,
        CASE
            WHEN p.ClosedDate IS NOT NULL THEN 'Closed'
            WHEN p.AnswerCount > 0 AND p.AcceptedAnswerId IS NOT NULL THEN 'Answered & Accepted'
            WHEN p.AnswerCount > 0 THEN 'Answered'
            ELSE 'Open'
        END AS PostStatus,
        -- String processing for tags: remove enclosing <> and get the first tag
        CASE
            WHEN p.Tags IS NOT NULL AND LENGTH(p.Tags) > 2 THEN SPLIT_PART(SUBSTRING(p.Tags FROM 2 FOR LENGTH(p.Tags) - 2), '><', 1)
            ELSE NULL
        END AS PrimaryTag,
        -- Correlated subquery to fetch the text of the highest-scored comment
        (
            SELECT cm.Text
            FROM Comments cm
            WHERE cm.PostId = p.Id AND cm.Score = (SELECT MAX(c2.Score) FROM Comments c2 WHERE c2.PostId = p.Id)
            ORDER BY cm.CreationDate DESC
            LIMIT 1
        ) AS TopCommentText,
        -- Another correlated subquery to get the latest close reason if the post is closed
        (
            SELECT crt.Name
            FROM PostHistory ph
            JOIN CloseReasonTypes crt ON ph.Comment::smallint = crt.Id -- Cast PostHistory.Comment to smallint
            WHERE ph.PostId = p.Id AND ph.PostHistoryTypeId = 10 AND ph.Comment IS NOT NULL
            ORDER BY ph.CreationDate DESC
            LIMIT 1
        ) AS LatestCloseReasonName
    FROM Posts p
    WHERE p.PostTypeId IN (1, 2) -- Focus on Questions and Answers
),
RankedPostHistoryEvents AS (
    SELECT
        ph.PostId,
        ph.CreationDate AS HistoryEventDate,
        ph.PostHistoryTypeId,
        ph.UserId AS HistoryInitiatorUserId,
        ROW_NUMBER() OVER (PARTITION BY ph.PostId, ph.PostHistoryTypeId ORDER BY ph.CreationDate DESC) AS rn
    FROM PostHistory ph
    WHERE ph.PostHistoryTypeId IN (10, 11, 12, 13, 19, 20) -- Closed, Reopened, Deleted, Undeleted, Protected, Unprotected
),
LinkAnalysis AS (
    SELECT
        pl.PostId,
        COUNT(CASE WHEN lt.Name = 'Linked' THEN 1 END) AS LinkedPostsCount,
        COUNT(CASE WHEN lt.Name = 'Duplicate' THEN 1 END) AS DuplicateOfCount,
        MAX(CASE WHEN lt.Name = 'Duplicate' THEN pl.RelatedPostId END) AS MostRecentDuplicatePostId -- Assumes higher Id is more recent
    FROM PostLinks pl
    JOIN LinkTypes lt ON pl.LinkTypeId = lt.Id
    GROUP BY pl.PostId
),
UserBadgeStats AS (
    SELECT
        b.UserId,
        COUNT(b.Id) AS UserBadgeCount,
        COUNT(CASE WHEN b.Class = 1 THEN 1 END) AS GoldBadgeCount,
        COUNT(CASE WHEN b.Name = 'Inquisitive' OR b.Name = 'Curious' THEN 1 END) AS QuestionRelatedBadges
    FROM Badges b
    GROUP BY b.UserId
)
-- Main query for analyzing Questions
SELECT
    pd.PostId,
    pd.PostTypeId,
    ua.DisplayName AS OwnerDisplayName,
    ua.Reputation AS OwnerReputation,
    ua.UserProfileViews,
    ubs.UserBadgeCount,
    ubs.GoldBadgeCount,
    pd.Title,
    pd.PostCreationDate,
    pd.Score AS PostScore,
    pd.ViewCount AS PostViewCount,
    pd.AnswerCount,
    pd.CommentCount AS PostCommentCount,
    pd.FavoriteCount,
    pd.PostStatus,
    pd.PrimaryTag,
    pd.EditCount,
    pd.LastEditDate_Calculated,
    pd.LastEditorDisplayName_Coalesced,
    pd.TopCommentText,
    pd.LatestCloseReasonName,
    la.LinkedPostsCount,
    la.DuplicateOfCount,
    p_acc.Score AS AcceptedAnswerScore,
    p_acc_owner.DisplayName AS AcceptedAnswerOwnerDisplayName,
    CASE
        WHEN pd.Score > (SELECT AVG(Score) FROM Posts WHERE PostTypeId = 1 AND CreationDate >= '2023-01-01') THEN 'AboveAvgScore2023'
        WHEN pd.Score > 0 THEN 'HasPositiveScore'
        ELSE 'NonPositiveScore'
    END AS QuestionScoreCategory,
    -- Window functions for ranking and aggregation
    RANK() OVER (PARTITION BY pd.PrimaryTag ORDER BY pd.Score DESC, pd.ViewCount DESC) AS RankInPrimaryTag,
    AVG(pd.Score) OVER (PARTITION BY ua.ReputationTier) AS AvgScoreInOwnerReputationTier,
    SUM(pd.CommentCount) OVER (ORDER BY pd.PostCreationDate ROWS BETWEEN 90 PRECEDING AND CURRENT ROW) AS Rolling90DayCommentSum,
    -- NULL logic and complex calculations
    pd.PostCreationDate - ua.UserCreationDate AS PostAgeRelativeToUserCreation,
    COALESCE(pd.FavoriteCount, 0) + COALESCE(pd.AnswerCount, 0) * 5 + COALESCE(la.LinkedPostsCount, 0) * 2 AS EngagementIndex,
    EXISTS (SELECT 1 FROM Badges b WHERE b.UserId = pd.OwnerUserId AND b.Name IN ('Enthusiast', 'Fanatic')) AS OwnerIsHighlyEngaged,
    (SELECT rph.HistoryEventDate FROM RankedPostHistoryEvents rph WHERE rph.PostId = pd.PostId AND rph.PostHistoryTypeId = 10 AND rph.rn = 1) AS LastClosedDate,
    (SELECT rph.HistoryEventDate FROM RankedPostHistoryEvents rph WHERE rph.PostId = pd.PostId AND rph.PostHistoryTypeId = 11 AND rph.rn = 1) AS LastReopenedDate
FROM PostDetails pd
INNER JOIN UserActivitySummary ua ON pd.OwnerUserId = ua.UserId
LEFT JOIN UserBadgeStats ubs ON pd.OwnerUserId = ubs.UserId
LEFT JOIN Posts p_acc ON pd.AcceptedAnswerId = p_acc.Id -- Join for accepted answer details
LEFT JOIN Users p_acc_owner ON p_acc.OwnerUserId = p_acc_owner.Id -- Join for accepted answer owner
LEFT JOIN LinkAnalysis la ON pd.PostId = la.PostId
WHERE
    pd.PostTypeId = 1 -- Only questions for this part
    AND pd.PostCreationDate BETWEEN '2023-01-01' AND '2023-12-31' -- Filter by specific year
    AND pd.Score >= 0
    AND (pd.ViewCount > 1000 OR pd.FavoriteCount > 20 OR pd.AnswerCount > 5) -- High visibility/interest
    AND (
        pd.PrimaryTag LIKE '%sql%'
        OR pd.PrimaryTag LIKE '%performance%'
        OR pd.PrimaryTag IS NULL
    )
    AND pd.OwnerUserId IS NOT NULL
    AND NOT EXISTS (
        SELECT 1
        FROM Comments c
        WHERE c.PostId = pd.PostId
        AND c.Text ILIKE '%bug report%'
        AND c.CreationDate > pd.PostCreationDate + INTERVAL '1 month'
    )
    AND EXISTS (
        SELECT 1
        FROM Votes v
        WHERE v.PostId = pd.PostId
        AND v.VoteTypeId = 2 -- UpMod
        AND v.UserId IS NOT NULL
        AND v.CreationDate < pd.LastActivityDate
    )
    AND (
        (pd.ClosedDate IS NOT NULL AND pd.LatestCloseReasonName = 'Duplicate') OR pd.ClosedDate IS NULL
    )
UNION ALL
-- Secondary query for highly-rated Answers from influential users
SELECT
    pd.PostId,
    pd.PostTypeId,
    ua.DisplayName AS OwnerDisplayName,
    ua.Reputation AS OwnerReputation,
    ua.UserProfileViews,
    ubs.UserBadgeCount,
    ubs.GoldBadgeCount,
    SUBSTRING(pd.Body FROM 1 FOR 150) AS TitleSnippet, -- For answers, take a snippet of the body
    pd.PostCreationDate,
    pd.Score AS PostScore,
    NULL AS PostViewCount, -- Not applicable for answers
    NULL AS AnswerCount, -- Not applicable for answers
    pd.CommentCount AS PostCommentCount,
    NULL AS FavoriteCount, -- Not applicable for answers
    pd.PostStatus,
    pd.PrimaryTag, -- Derived from parent if needed, but NULL for this query simplification
    pd.EditCount,
    pd.LastEditDate_Calculated,
    pd.LastEditorDisplayName_Coalesced,
    pd.TopCommentText,
    NULL AS LatestCloseReasonName, -- Not applicable for answers
    la.LinkedPostsCount,
    la.DuplicateOfCount,
    NULL AS AcceptedAnswerScore, -- Not applicable for answers
    NULL AS AcceptedAnswerOwnerDisplayName, -- Not applicable for answers
    CASE
        WHEN pd.Score > (SELECT AVG(Score) FROM Posts WHERE PostTypeId = 2 AND CreationDate >= '2023-01-01') THEN 'AboveAvgScore2023'
        WHEN pd.Score >= 10 THEN 'HighlyRatedAnswer'
        ELSE 'ModeratelyRatedAnswer'
    END AS AnswerScoreCategory,
    RANK() OVER (PARTITION BY pd.ParentId ORDER BY pd.Score DESC, pd.CreationDate ASC) AS RankInParentQuestionAnswers,
    AVG(pd.Score) OVER (PARTITION BY ua.ReputationTier) AS AvgScoreInOwnerReputationTier,
    SUM(pd.CommentCount) OVER (ORDER BY pd.PostCreationDate ROWS BETWEEN 90 PRECEDING AND CURRENT ROW) AS Rolling90DayCommentSum,
    pd.PostCreationDate - ua.UserCreationDate AS PostAgeRelativeToUserCreation,
    COALESCE(pd.Score, 0) * 3 + COALESCE(pd.CommentCount, 0) * 2 AS EngagementIndex, -- Different metric for answers
    EXISTS (SELECT 1 FROM Badges b WHERE b.UserId = pd.OwnerUserId AND b.Name = 'Great Answer') AS OwnerHasGreatAnswerBadge,
    NULL AS LastClosedDate, -- Not applicable for answers
    NULL AS LastReopenedDate -- Not applicable for answers
FROM PostDetails pd
INNER JOIN UserActivitySummary ua ON pd.OwnerUserId = ua.UserId
LEFT JOIN UserBadgeStats ubs ON pd.OwnerUserId = ubs.UserId
LEFT JOIN LinkAnalysis la ON pd.PostId = la.PostId
WHERE
    pd.PostTypeId = 2 -- Only answers for this part
    AND pd.Score >= 5 -- Highly rated answers
    AND pd.CreationDate BETWEEN '2023-01-01' AND '2023-12-31'
    AND pd.OwnerUserId IS NOT NULL
    AND ua.Reputation >= 1000 -- Only answers from influential users
    AND (pd.Body ILIKE '%index%' OR pd.Body ILIKE '%optimization%')
ORDER BY
    OwnerReputation DESC, PostScore DESC, PostCreationDate DESC
LIMIT 25000;
