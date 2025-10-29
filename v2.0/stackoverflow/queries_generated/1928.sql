-- {"query": "1928.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gemini-2.5-flash", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2111, "output_tokens": 3267} 

WITH UserActivityMetrics AS (
    -- CTE 1: Summarizes user activity, reputation, and vote engagement.
    -- Includes a window function for ranking users by reputation and last access.
    -- Uses COALESCE for null-safe aggregation and a complex ratio calculation.
    SELECT
        u.Id AS UserId,
        u.DisplayName,
        u.Reputation,
        u.Views,
        u.UpVotes,
        u.DownVotes,
        u.CreationDate AS UserCreationDate,
        u.LastAccessDate,
        COUNT(DISTINCT p.Id) AS TotalPosts,
        COUNT(DISTINCT c.Id) AS TotalComments,
        SUM(CASE WHEN p.PostTypeId = 1 THEN 1 ELSE 0 END) AS TotalQuestions,
        SUM(CASE WHEN p.PostTypeId = 2 THEN 1 ELSE 0 END) AS TotalAnswers,
        COALESCE(SUM(p.Score), 0) AS TotalPostScore,
        COALESCE(AVG(c.Score), 0.0) AS AvgCommentScore,
        MAX(CASE WHEN p.PostTypeId = 1 THEN p.CreationDate END) AS LastQuestionDate,
        MAX(CASE WHEN p.PostTypeId = 2 THEN p.CreationDate END) AS LastAnswerDate,
        DENSE_RANK() OVER (ORDER BY u.Reputation DESC, u.LastAccessDate DESC) AS ReputationRank,
        (u.UpVotes * 1.0 / NULLIF(u.DownVotes + u.UpVotes, 0)) AS UpVoteRatio
    FROM Users AS u
    LEFT JOIN Posts AS p ON u.Id = p.OwnerUserId
    LEFT JOIN Comments AS c ON u.Id = c.UserId
    GROUP BY
        u.Id, u.DisplayName, u.Reputation, u.Views, u.UpVotes, u.DownVotes,
        u.CreationDate, u.LastAccessDate
),
PostDetailsAndHistory AS (
    -- CTE 2: Gathers detailed post information, including edit history and tag analysis.
    -- Features a correlated subquery for comparison, string manipulation for tags,
    -- and conditional logic for post status, along with a window function for owner's post ranking.
    SELECT
        p.Id AS PostId,
        p.PostTypeId,
        pt.Name AS PostTypeName,
        p.AcceptedAnswerId,
        p.ParentId,
        p.CreationDate AS PostCreationDate,
        p.Score AS PostScore,
        p.ViewCount,
        p.OwnerUserId,
        p.LastEditDate,
        p.LastActivityDate,
        p.Title,
        p.Tags,
        p.AnswerCount,
        p.CommentCount,
        p.FavoriteCount,
        p.ClosedDate,
        COUNT(ph.Id) AS TotalHistoryEvents,
        SUM(CASE WHEN ph.PostHistoryTypeId IN (4,5,6) THEN 1 ELSE 0 END) AS EditCount, -- Edit Title, Body, Tags
        -- Correlated subquery: average score of other posts by the same owner in the same year
        (SELECT AVG(p2.Score)
         FROM Posts AS p2
         WHERE p2.OwnerUserId = p.OwnerUserId
           AND p2.Id <> p.Id
           AND EXTRACT(YEAR FROM p2.CreationDate) = EXTRACT(YEAR FROM p.CreationDate)
        ) AS AvgOwnerOtherPostScoreSameYear,
        -- String expression to count tags, handling NULL/empty tags
        COALESCE(LENGTH(REPLACE(TRIM(BOTH '<>' FROM p.Tags), '><', '|')) - LENGTH(REPLACE(REPLACE(TRIM(BOTH '<>' FROM p.Tags), '><', '|'), '|', '')) + 1, 0) AS TagCount,
        CASE
            WHEN p.ClosedDate IS NOT NULL THEN 'Closed'
            WHEN p.AcceptedAnswerId IS NOT NULL THEN 'Answered'
            WHEN p.AnswerCount > 0 THEN 'HasAnswers'
            ELSE 'Open'
        END AS PostStatus,
        DENSE_RANK() OVER (PARTITION BY p.OwnerUserId ORDER BY p.Score DESC, p.ViewCount DESC) AS OwnerPostScoreRank
    FROM Posts AS p
    LEFT JOIN PostHistory AS ph ON p.Id = ph.PostId
    LEFT JOIN PostTypes AS pt ON p.PostTypeId = pt.Id
    GROUP BY
        p.Id, p.PostTypeId, pt.Name, p.AcceptedAnswerId, p.ParentId, p.CreationDate, p.Score,
        p.ViewCount, p.OwnerUserId, p.LastEditDate, p.LastActivityDate, p.Title,
        p.Tags, p.AnswerCount, p.CommentCount, p.FavoriteCount, p.ClosedDate
),
BadgeSummary AS (
    -- CTE 3: Aggregates badge counts per user, distinguishing by class (Gold, Silver, Bronze).
    -- Includes a window function to rank users by their Gold badge count.
    SELECT
        b.UserId,
        SUM(CASE WHEN b.Class = 1 THEN 1 ELSE 0 END) AS GoldBadges,
        SUM(CASE WHEN b.Class = 2 THEN 1 ELSE 0 END) AS SilverBadges,
        SUM(CASE WHEN b.Class = 3 THEN 1 ELSE 0 END) AS BronzeBadges,
        COUNT(b.Id) AS TotalBadges,
        SUM(CASE WHEN b.TagBased = TRUE THEN 1 ELSE 0 END) AS TagBasedBadges,
        DENSE_RANK() OVER (ORDER BY SUM(CASE WHEN b.Class = 1 THEN 1 ELSE 0 END) DESC, COUNT(b.Id) DESC) AS GoldBadgeRank
    FROM Badges AS b
    GROUP BY b.UserId
),
ComplexPostInteractions AS (
    -- CTE 4: Focuses on questions and their interaction metrics, like accepted answers, associated tags, and age.
    -- Uses STRING_AGG with FILTER for tag aggregation and extracts time differences.
    SELECT
        q.Id AS QuestionId,
        q.OwnerUserId AS QuestionOwnerId,
        q.CreationDate AS QuestionCreationDate,
        q.Title AS QuestionTitle,
        q.ViewCount AS QuestionViewCount,
        q.Score AS QuestionScore,
        COALESCE(q.AnswerCount, 0) AS ActualAnswerCount,
        CASE WHEN q.AcceptedAnswerId IS NOT NULL THEN 1 ELSE 0 END AS HasAcceptedAnswer,
        (SELECT MAX(ph.CreationDate) FROM PostHistory AS ph WHERE ph.PostId = q.Id AND ph.PostHistoryTypeId = 10) AS LatestClosedDateHistory, -- 10 = Post Closed
        STRING_AGG(DISTINCT t.TagName, ', ') FILTER (WHERE t.TagName IS NOT NULL) AS AssociatedTags,
        EXTRACT(HOUR FROM (CURRENT_TIMESTAMP - q.CreationDate)) AS HoursSinceCreation
    FROM Posts AS q
    LEFT JOIN Tags AS t ON q.Tags LIKE '%<' || t.TagName || '>%' -- Join with Tags table for tagName extraction
    WHERE q.PostTypeId = 1 -- Only questions
    GROUP BY
        q.Id, q.OwnerUserId, q.CreationDate, q.Title, q.ViewCount, q.Score, q.AnswerCount, q.AcceptedAnswerId
)
-- Main Query: Combines data from all CTEs to generate a comprehensive report on high-engagement posts and their owners.
-- Features extensive outer joins, complicated WHERE clause predicates, CASE statements for categorization,
-- various expressions/calculations, and a UNION ALL set operator to include another distinct segment of posts.
SELECT
    uam.UserId,
    uam.DisplayName,
    uam.Reputation,
    uam.ReputationRank,
    uam.TotalQuestions,
    uam.TotalAnswers,
    uam.UpVoteRatio,
    bs.GoldBadges,
    bs.SilverBadges,
    bs.BronzeBadges,
    bs.TotalBadges,
    pdh.PostId,
    pdh.PostTypeName,
    pdh.PostCreationDate,
    pdh.PostScore,
    pdh.ViewCount AS PostViewCount,
    pdh.TagCount,
    pdh.PostStatus,
    pdh.EditCount,
    pdh.AvgOwnerOtherPostScoreSameYear,
    cpi.QuestionTitle,
    cpi.QuestionViewCount,
    cpi.ActualAnswerCount,
    cpi.HasAcceptedAnswer AS HasAcceptedAnswerFlag,
    cpi.AssociatedTags,
    cpi.HoursSinceCreation,
    -- Complicated predicate/calculation in SELECT
    CASE
        WHEN pdh.PostTypeId = 1 AND pdh.AcceptedAnswerId IS NOT NULL AND cpi.HoursSinceCreation <= 24 THEN 'Quickly_Answered_Question'
        WHEN uam.ReputationRank <= 100 AND bs.GoldBadges >= 5 THEN 'High_Rep_Gold_User_Post'
        WHEN pdh.PostScore > 1000 OR pdh.ViewCount > 50000 THEN 'Viral_Post'
        ELSE 'Regular_Activity'
    END AS ActivityCategory,
    -- Another complicated calculation
    (pdh.PostScore * 1.0 / NULLIF(pdh.ViewCount, 0)) AS ScorePerView,
    -- Null logic in expression
    COALESCE(pdh.LastEditDate, pdh.PostCreationDate) AS EffectiveLastActivityDate
FROM PostDetailsAndHistory AS pdh
INNER JOIN UserActivityMetrics AS uam ON pdh.OwnerUserId = uam.UserId
LEFT JOIN BadgeSummary AS bs ON uam.UserId = bs.UserId
LEFT JOIN ComplexPostInteractions AS cpi ON pdh.PostId = cpi.QuestionId
WHERE
    pdh.OwnerUserId IS NOT NULL -- Exclude community user posts etc.
    AND pdh.PostCreationDate >= '2020-01-01' -- Filter recent data
    AND (
        pdh.PostTypeId = 1 -- Only questions
        OR (pdh.PostTypeId = 2 AND pdh.PostScore >= 10 AND pdh.LastEditDate IS NOT NULL) -- High-scoring edited answers
    )
    AND (
        -- Complicated predicate with NULL logic and string expression
        (pdh.Tags IS NOT NULL AND pdh.Tags LIKE '%<sql>%' AND pdh.TagCount > 2)
        OR (pdh.ViewCount > 1000 AND uam.Reputation >= 5000 AND uam.TotalPosts > 50)
        OR (cpi.QuestionId IS NOT NULL AND cpi.ActualAnswerCount > 0 AND cpi.HasAcceptedAnswer = 1)
    )
    AND (pdh.ClosedDate IS NULL OR pdh.TotalHistoryEvents > 0 AND EXISTS (SELECT 1 FROM PostHistory ph_reopen WHERE ph_reopen.PostId = pdh.PostId AND ph_reopen.PostHistoryTypeId = 11)) -- Not closed or explicitly reopened
    AND uam.UpVoteRatio IS NOT NULL AND uam.UpVoteRatio > 0.7
    AND bs.GoldBadges IS NOT NULL -- Only users with badges
-- Set operator: UNION ALL to add another perspective to the results for highly commented, unanswered questions
UNION ALL
SELECT
    uam.UserId,
    uam.DisplayName,
    uam.Reputation,
    uam.ReputationRank,
    uam.TotalQuestions,
    uam.TotalAnswers,
    uam.UpVoteRatio,
    bs.GoldBadges,
    bs.SilverBadges,
    bs.BronzeBadges,
    bs.TotalBadges,
    p.Id AS PostId,
    pt.Name AS PostTypeName,
    p.CreationDate AS PostCreationDate,
    p.Score AS PostScore,
    p.ViewCount AS PostViewCount,
    -- String expression to count tags, handling NULL/empty tags
    COALESCE(LENGTH(REPLACE(TRIM(BOTH '<>' FROM p.Tags), '><', '|')) - LENGTH(REPLACE(REPLACE(TRIM(BOTH '<>' FROM p.Tags), '><', '|'), '|', '')) + 1, 0) AS TagCount,
    'Highly_Commented_Orphan' AS PostStatus, -- Custom status for this branch
    0 AS EditCount, -- Placeholder for this branch
    NULL AS AvgOwnerOtherPostScoreSameYear, -- Placeholder for this branch
    p.Title AS QuestionTitle,
    p.ViewCount AS QuestionViewCount,
    COALESCE(p.AnswerCount, 0) AS ActualAnswerCount,
    0 AS HasAcceptedAnswerFlag, -- No accepted answer in this branch
    NULL AS AssociatedTags,
    EXTRACT(HOUR FROM (CURRENT_TIMESTAMP - p.CreationDate)) AS HoursSinceCreation,
    'Unanswered_But_Discussed' AS ActivityCategory,
    (p.Score * 1.0 / NULLIF(p.ViewCount, 0)) AS ScorePerView,
    COALESCE(p.LastEditDate, p.CreationDate) AS EffectiveLastActivityDate
FROM Posts AS p
INNER JOIN UserActivityMetrics AS uam ON p.OwnerUserId = uam.UserId
LEFT JOIN BadgeSummary AS bs ON uam.UserId = bs.UserId
LEFT JOIN PostTypes AS pt ON p.PostTypeId = pt.Id
WHERE
    p.OwnerUserId IS NOT NULL
    AND p.CreationDate >= '2021-01-01'
    AND p.PostTypeId = 1 -- Only questions for this part
    AND p.AcceptedAnswerId IS NULL -- Orphaned questions
    AND COALESCE(p.AnswerCount, 0) = 0 -- No answers
    AND p.CommentCount >= 10 -- But lots of comments
    AND p.Score > 50
    AND uam.Reputation > 1000
    AND (p.ClosedDate IS NULL OR p.LastActivityDate > p.ClosedDate) -- Ensure it's not simply dead-closed
ORDER BY
    Reputation DESC,
    PostScore DESC,
    EffectiveLastActivityDate DESC NULLS LAST,
    TagCount DESC
LIMIT 1000;
