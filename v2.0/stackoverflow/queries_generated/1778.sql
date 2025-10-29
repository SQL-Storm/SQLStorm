-- {"query": "1778.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gemini-2.5-flash", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2111, "output_tokens": 4044} 

WITH UserStats AS (
    SELECT
        u.Id AS UserId,
        u.DisplayName,
        u.Reputation,
        u.CreationDate AS UserCreationDate,
        u.LastAccessDate,
        u.UpVotes AS UserUpVotesGiven,
        u.DownVotes AS UserDownVotesGiven,
        u.Views AS UserProfileViews,
        COUNT(DISTINCT p.Id) AS TotalPostsOwned,
        COUNT(DISTINCT c.Id) AS TotalCommentsMade,
        SUM(CASE WHEN b.Class = 1 THEN 1 ELSE 0 END) AS GoldBadges,
        SUM(CASE WHEN b.Class = 2 THEN 1 ELSE 0 END) AS SilverBadges,
        SUM(CASE WHEN b.Class = 3 THEN 1 ELSE 0 END) AS BronzeBadges,
        -- Calculate a heuristic 'activity score'
        (u.UpVotes * 5 + u.DownVotes * 2 + u.Views * 0.1 + COUNT(DISTINCT p.Id) * 10 + COUNT(DISTINCT c.Id) * 3) AS ActivityScore
    FROM Users u
    LEFT JOIN Posts p ON u.Id = p.OwnerUserId
    LEFT JOIN Comments c ON u.Id = c.UserId
    LEFT JOIN Badges b ON u.Id = b.UserId
    GROUP BY u.Id, u.DisplayName, u.Reputation, u.CreationDate, u.LastAccessDate, u.UpVotes, u.DownVotes, u.Views
),
PostStats AS (
    SELECT
        p.Id AS PostId,
        p.PostTypeId,
        pt.Name AS PostTypeName,
        p.OwnerUserId,
        p.CreationDate AS PostCreationDate,
        p.Score AS PostNetScore,
        p.ViewCount,
        p.AnswerCount,
        p.CommentCount AS PostCommentCount,
        p.Title,
        p.Tags,
        p.LastEditDate,
        p.LastActivityDate,
        p.ClosedDate,
        p.ParentId,
        SUM(CASE WHEN v.VoteTypeId = 2 THEN 1 ELSE 0 END) AS UpVotesReceived,
        SUM(CASE WHEN v.VoteTypeId = 3 THEN 1 ELSE 0 END) AS DownVotesReceived,
        COUNT(DISTINCT ph.Id) AS TotalHistoryEntries,
        -- Calculate post age in days at last activity date, coalesce to 0 if null
        COALESCE(EXTRACT(EPOCH FROM (p.LastActivityDate - p.CreationDate)) / 86400.0, 0.0) AS PostAgeAtLastActivityDays,
        -- Identify if post title contains certain performance-related keywords (case-insensitive)
        CASE
            WHEN p.Title IS NOT NULL AND (LOWER(p.Title) LIKE '%performance%' OR LOWER(p.Title) LIKE '%optimize%' OR LOWER(p.Title) LIKE '%slow%') THEN TRUE
            ELSE FALSE
        END AS IsPerformanceRelated
    FROM Posts p
    JOIN PostTypes pt ON p.PostTypeId = pt.Id
    LEFT JOIN Votes v ON p.Id = v.PostId
    LEFT JOIN PostHistory ph ON p.Id = ph.PostId
    GROUP BY p.Id, p.PostTypeId, pt.Name, p.OwnerUserId, p.CreationDate, p.Score, p.ViewCount, p.AnswerCount, p.CommentCount, p.Title, p.Tags, p.LastEditDate, p.LastActivityDate, p.ClosedDate, p.ParentId
),
PostHistoryDetails AS (
    SELECT
        ph.PostId,
        ph.Id AS HistoryId,
        ph.UserId AS HistoryEditorUserId,
        ph.CreationDate AS HistoryEntryDate,
        ph.PostHistoryTypeId,
        pht.Name AS HistoryTypeName,
        ph.Comment AS HistoryComment,
        ph.Text AS HistoryText,
        -- Rank history entries by creation date (descending) for each post
        ROW_NUMBER() OVER (PARTITION BY ph.PostId ORDER BY ph.CreationDate DESC, ph.Id DESC) AS PostHistoryRankDesc,
        -- Calculate time difference in hours to the previous history entry for the same post, NULL if first
        EXTRACT(EPOCH FROM (ph.CreationDate - LAG(ph.CreationDate) OVER (PARTITION BY ph.PostId ORDER BY ph.CreationDate))) / 3600.0 AS HoursSincePrevHistory,
        -- Determine if this is the very first edit to the post body (PostHistoryTypeId = 5)
        CASE
            WHEN ph.PostHistoryTypeId = 5 AND NOT EXISTS (
                SELECT 1 FROM PostHistory ph2
                WHERE ph2.PostId = ph.PostId
                AND ph2.PostHistoryTypeId = 5
                AND ph2.CreationDate < ph.CreationDate
            ) THEN TRUE
            ELSE FALSE
        END AS IsFirstBodyEdit
    FROM PostHistory ph
    JOIN PostHistoryTypes pht ON ph.PostHistoryTypeId = pht.Id
    WHERE ph.PostHistoryTypeId IN (1, 2, 4, 5, 6, 10, 11, 12, 13, 16) -- Initial, Edit, Closed, Reopened, Deleted, Undeleted, Community Owned
),
ComplexUserReputationDetails AS (
    SELECT
        us.UserId,
        us.DisplayName,
        us.Reputation,
        us.UserCreationDate,
        -- Cumulative reputation across all users ordered by creation date
        SUM(us.Reputation) OVER (ORDER BY us.UserCreationDate, us.UserId) AS CumulativeReputationAcrossUsers,
        -- Calculate reputation change rate per day since user creation
        CASE
            WHEN EXTRACT(EPOCH FROM (CURRENT_TIMESTAMP - us.UserCreationDate)) / 86400.0 > 0
            THEN us.Reputation * 1.0 / (EXTRACT(EPOCH FROM (CURRENT_TIMESTAMP - us.UserCreationDate)) / 86400.0)
            ELSE 0.0
        END AS ReputationPerDay,
        -- Ratio of Upvotes given to Downvotes given, handling division by zero and NULLs
        COALESCE(us.UserUpVotesGiven * 1.0 / NULLIF(us.UserDownVotesGiven, 0), us.UserUpVotesGiven * 1.0, 0.0) AS UpDownVoteRatioGiven,
        -- Correlated subquery to find the latest gold badge date for the user, if any
        (SELECT MAX(b.Date) FROM Badges b WHERE b.UserId = us.UserId AND b.Class = 1) AS LatestGoldBadgeDate
    FROM UserStats us
)
-- Main query: Combining high-impact questions with highly edited accepted answers
SELECT
    curd.UserId,
    curd.DisplayName,
    curd.Reputation,
    curd.UserCreationDate,
    curd.ReputationPerDay,
    curd.UpDownVoteRatioGiven,
    curd.LatestGoldBadgeDate,
    us.ActivityScore,
    ps_q.PostId AS EntityId,
    ps_q.PostTypeName AS EntityType,
    ps_q.Title AS EntityTitle,
    ps_q.PostCreationDate AS EntityCreationDate,
    ps_q.PostNetScore AS EntityNetScore,
    ps_q.ViewCount AS EntityViewCount,
    ps_q.AnswerCount AS EntityAnswerCount,
    ps_q.IsPerformanceRelated AS IsEntityPerformanceRelated,
    -- Extract the first tag from the Tags string, handling potential NULLs or empty strings
    TRIM(SPLIT_PART(SUBSTRING(ps_q.Tags, 2, LENGTH(ps_q.Tags) - 2), '><', 1)) AS FirstTagForEntity,
    LENGTH(p_full_q.Body) AS EntityBodyLength, -- Body length from the full Posts table
    NULL AS AcceptedAnswerScore, -- Not applicable for questions in this union branch
    phd_q_latest.HistoryEntryDate AS LatestEntityHistoryDate,
    phd_q_latest.HistoryTypeName AS LatestEntityHistoryType,
    phd_q_first_body_edit.HistoryEditorUserId AS FirstBodyEditorId,
    phd_q_first_body_edit.HistoryEntryDate AS FirstBodyEditDate,
    phd_q_first_body_edit.HoursSincePrevHistory AS FirstBodyEditHoursSincePrev,
    -- Window function: Average question score for a user
    AVG(ps_q.PostNetScore) OVER (PARTITION BY curd.UserId) AS AvgEntityScoreByUser,
    -- Window function: Count of closed questions for a user
    COUNT(CASE WHEN ps_q.ClosedDate IS NOT NULL THEN 1 END) OVER (PARTITION BY curd.UserId) AS SpecificEntityCountByUser,
    -- Correlated subquery: Count of related posts (linked) for the entity
    (SELECT COUNT(DISTINCT pl.RelatedPostId) FROM PostLinks pl WHERE pl.PostId = ps_q.PostId AND pl.LinkTypeId = 1) AS EntityLinkedCount,
    -- String expression: Formatted display name (Capitalize first letter, lowercase rest)
    CONCAT(
        UPPER(SUBSTRING(curd.DisplayName, 1, 1)),
        LOWER(SUBSTRING(curd.DisplayName, 2))
    ) AS FormattedDisplayName,
    -- Correlated subquery: Count of comments made by the owner on their own post within activity period
    (SELECT COUNT(DISTINCT c.Id)
     FROM Comments c
     WHERE c.PostId = ps_q.Id
       AND c.UserId = curd.UserId
       AND c.CreationDate BETWEEN ps_q.CreationDate AND ps_q.LastActivityDate
    ) AS UserCommentsOnOwnEntityCount,
    -- NULL logic: Coalesce entity net score to 0 if NULL
    COALESCE(ps_q.PostNetScore, 0) AS CoalescedEntityNetScore,
    -- Complex predicate/calculation: Categorize question status
    CASE
        WHEN ps_q.Title LIKE '%error%' AND ps_q.ClosedDate IS NOT NULL THEN 'Error_Closed_Question'
        WHEN ps_q.PostNetScore > 100 AND ps_q.AnswerCount > 5 THEN 'High_Engagement_Question'
        ELSE 'Other_Question'
    END AS EntityStatusCategory
FROM
    ComplexUserReputationDetails curd
JOIN
    UserStats us ON curd.UserId = us.UserId
LEFT JOIN
    PostStats ps_q ON curd.UserId = ps_q.OwnerUserId AND ps_q.PostTypeId = 1 -- Join for Questions
LEFT JOIN
    Posts p_full_q ON ps_q.PostId = p_full_q.Id -- To get the actual body text for length calculation
LEFT JOIN
    PostHistoryDetails phd_q_latest ON ps_q.PostId = phd_q_latest.PostId AND phd_q_latest.PostHistoryRankDesc = 1 -- Latest history entry
LEFT JOIN
    PostHistoryDetails phd_q_first_body_edit ON ps_q.PostId = phd_q_first_body_edit.PostId AND phd_q_first_body_edit.IsFirstBodyEdit = TRUE -- First body edit
WHERE
    curd.Reputation > 1000 -- Filter for users with significant reputation
    AND ps_q.PostId IS NOT NULL -- Ensure only users with questions are included
    AND ps_q.ViewCount > 500 -- Filter for popular questions
    AND ps_q.PostCreationDate >= '2022-01-01' -- Recent questions
    AND (ps_q.Tags LIKE '%<sql>%' OR ps_q.Tags LIKE '%<database>%') -- Questions related to specific tags
    AND (phd_q_latest.HistoryTypeName IS NOT NULL OR curd.LatestGoldBadgeDate IS NOT NULL) -- NULL logic: ensure some history or a gold badge
    AND (ps_q.ClosedDate IS NULL OR ps_q.PostAgeAtLastActivityDays < 365) -- Complex date predicate

UNION ALL

-- Second branch of the UNION ALL: Highly edited and accepted answers by high-reputation users
SELECT
    curd.UserId,
    curd.DisplayName,
    curd.Reputation,
    curd.UserCreationDate,
    curd.ReputationPerDay,
    curd.UpDownVoteRatioGiven,
    curd.LatestGoldBadgeDate,
    us.ActivityScore,
    ps_a.PostId AS EntityId,
    ps_a.PostTypeName AS EntityType,
    p_q_for_a.Title AS EntityTitle, -- Title of the parent question for context
    ps_a.PostCreationDate AS EntityCreationDate,
    ps_a.PostNetScore AS EntityNetScore,
    NULL AS EntityViewCount, -- Answers don't have direct view counts
    NULL AS EntityAnswerCount, -- Not applicable for answers
    ps_a.IsPerformanceRelated AS IsEntityPerformanceRelated,
    NULL AS FirstTagForEntity, -- Tags are typically on questions, not answers
    LENGTH(p_full_a.Body) AS EntityBodyLength,
    ps_a.PostNetScore AS AcceptedAnswerScore, -- The score of the accepted answer itself
    phd_a_latest.HistoryEntryDate AS LatestEntityHistoryDate,
    phd_a_latest.HistoryTypeName AS LatestEntityHistoryType,
    phd_a_first_body_edit.HistoryEditorUserId AS FirstBodyEditorId,
    phd_a_first_body_edit.HistoryEntryDate AS FirstBodyEditDate,
    phd_a_first_body_edit.HoursSincePrevHistory AS FirstBodyEditHoursSincePrev,
    -- Window function: Average answer score for a user
    AVG(ps_a.PostNetScore) OVER (PARTITION BY curd.UserId) AS AvgEntityScoreByUser,
    -- Window function: Count of significantly edited answers for a user
    COUNT(CASE WHEN ps_a.PostTypeId = 2 AND ps_a.TotalHistoryEntries > 3 THEN 1 END) OVER (PARTITION BY curd.UserId) AS SpecificEntityCountByUser,
    -- Correlated subquery: Count of related posts (linked) for the entity
    (SELECT COUNT(DISTINCT pl.RelatedPostId) FROM PostLinks pl WHERE pl.PostId = ps_a.PostId AND pl.LinkTypeId = 1) AS EntityLinkedCount,
    -- String expression: Formatted display name
    CONCAT(
        UPPER(SUBSTRING(curd.DisplayName, 1, 1)),
        LOWER(SUBSTRING(curd.DisplayName, 2))
    ) AS FormattedDisplayName,
    -- Correlated subquery: Count of comments made by the owner on their own answer
    (SELECT COUNT(DISTINCT c.Id)
     FROM Comments c
     WHERE c.PostId = ps_a.Id
       AND c.UserId = curd.UserId
       AND c.CreationDate BETWEEN ps_a.CreationDate AND ps_a.LastActivityDate
    ) AS UserCommentsOnOwnEntityCount,
    -- NULL logic: Coalesce entity net score to 0 if NULL
    COALESCE(ps_a.PostNetScore, 0) AS CoalescedEntityNetScore,
    -- Complex predicate/calculation: Categorize answer status
    CASE
        WHEN ps_a.PostNetScore > 50 AND ps_a.TotalHistoryEntries > 3 THEN 'HighImpact_Edited_Answer'
        WHEN ps_a.PostNetScore < 0 AND ps_a.ClosedDate IS NOT NULL THEN 'Negative_Closed_Answer'
        ELSE 'Other_Answer'
    END AS EntityStatusCategory
FROM
    ComplexUserReputationDetails curd
JOIN
    UserStats us ON curd.UserId = us.UserId
LEFT JOIN
    PostStats ps_a ON curd.UserId = ps_a.OwnerUserId AND ps_a.PostTypeId = 2 -- Join for Answers
LEFT JOIN
    Posts p_full_a ON ps_a.PostId = p_full_a.Id -- To get the actual body text for length calculation
LEFT JOIN
    Posts p_q_for_a ON ps_a.ParentId = p_q_for_a.Id -- To retrieve the parent question's title
LEFT JOIN
    PostHistoryDetails phd_a_latest ON ps_a.PostId = phd_a_latest.PostId AND phd_a_latest.PostHistoryRankDesc = 1
LEFT JOIN
    PostHistoryDetails phd_a_first_body_edit ON ps_a.PostId = phd_a_first_body_edit.PostId AND phd_a_first_body_edit.IsFirstBodyEdit = TRUE
WHERE
    curd.Reputation > 5000 -- Higher reputation threshold for answers
    AND ps_a.PostId IS NOT NULL
    AND ps_a.PostNetScore > 20 -- Only highly upvoted answers
    AND ps_a.LastEditDate IS NOT NULL AND ps_a.LastEditDate > ps_a.CreationDate -- Only edited answers
    AND ps_a.PostCreationDate >= '2022-01-01'
    AND phd_a_latest.HistoryTypeName IS NOT NULL -- Ensure there is some history data
    AND EXISTS (SELECT 1 FROM Posts acc_ans WHERE acc_ans.Id = ps_a.PostId AND acc_ans.AcceptedAnswerId = ps_a.PostId) -- Correlated subquery: Must be an accepted answer
ORDER BY
    Reputation DESC,
    EntityNetScore DESC,
    LatestEntityHistoryDate DESC
LIMIT 1000;
