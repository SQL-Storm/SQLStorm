-- {"query": "1292.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gemini-2.5-flash", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2111, "output_tokens": 3170} 

WITH UserEngagement AS (
    -- CTE 1: Aggregates user-specific engagement metrics, including reputation percentiles and badge counts.
    -- Features: Window function (NTILE), complicated predicate/expression, NULL logic, correlated subqueries.
    SELECT
        u.Id AS UserId,
        u.DisplayName,
        u.Reputation,
        u.CreationDate,
        u.LastAccessDate,
        u.UpVotes,
        u.DownVotes,
        u.Views AS UserProfileViews,
        COALESCE(b.GoldBadges, 0) AS GoldBadges,
        COALESCE(b.SilverBadges, 0) AS SilverBadges,
        COALESCE(b.BronzeBadges, 0) AS BronzeBadges,
        NTILE(100) OVER (ORDER BY u.Reputation DESC, u.CreationDate ASC) AS ReputationPercentile,
        CASE
            WHEN (u.UpVotes + u.DownVotes) > 0 THEN CAST(u.UpVotes AS NUMERIC) / (u.UpVotes + u.DownVotes)
            ELSE 0.0
        END AS VoteRatio,
        COALESCE(u.Location, 'Earth') AS UserLocation_Coalesced,
        (SELECT COUNT(p.Id) FROM Posts p WHERE p.OwnerUserId = u.Id AND p.PostTypeId = 1 AND p.CreationDate >= u.CreationDate - INTERVAL '1 year') AS RecentQuestionCount,
        (SELECT COUNT(c.Id) FROM Comments c WHERE c.UserId = u.Id AND c.CreationDate >= CURRENT_TIMESTAMP - INTERVAL '90 days') AS Last90DayCommentCount
    FROM
        Users u
    LEFT JOIN (
        SELECT
            UserId,
            SUM(CASE WHEN Class = 1 THEN 1 ELSE 0 END) AS GoldBadges,
            SUM(CASE WHEN Class = 2 THEN 1 ELSE 0 END) AS SilverBadges,
            SUM(CASE WHEN Class = 3 THEN 1 ELSE 0 END) AS BronzeBadges
        FROM Badges
        GROUP BY UserId
    ) b ON u.Id = b.UserId
    WHERE
        u.CreationDate >= CURRENT_TIMESTAMP - INTERVAL '5 years' -- Focus on more recent users
        AND u.Reputation > 500
),
PostQualityMetrics AS (
    -- CTE 2: Calculates quality metrics for questions, including accepted answers, edit history, and tags.
    -- Features: Correlated subqueries, Outer Join, CTE, String expressions, Complicated predicates/expressions, NULLIF.
    SELECT
        p.Id AS PostId,
        p.Title,
        p.Tags,
        p.CreationDate AS PostCreationDate,
        p.OwnerUserId,
        p.Score,
        p.ViewCount,
        COALESCE(p.AnswerCount, 0) AS AnswerCount, -- NULL logic
        p.CommentCount,
        p.FavoriteCount,
        ph_edits.LastEditCount,
        ph_edits.SelfEditCount,
        p.AcceptedAnswerId,
        (SELECT p_ans.Score FROM Posts p_ans WHERE p_ans.Id = p.AcceptedAnswerId AND p_ans.PostTypeId = 2) AS AcceptedAnswerScore, -- Correlated subquery
        CASE
            WHEN p.ClosedDate IS NOT NULL THEN 'Closed'
            WHEN p.CommunityOwnedDate IS NOT NULL THEN 'CommunityOwned'
            WHEN p.LastActivityDate IS NULL OR p.LastActivityDate < p.CreationDate + INTERVAL '180 days' AND p.AnswerCount = 0 THEN 'StaleNoActivity'
            ELSE 'Active'
        END AS PostStatus,
        NULLIF(p.ViewCount, 0) AS ViewCount_NonNull, -- NULLIF example for division
        string_to_array(substring(p.Tags, 2, length(p.Tags)-2), '><') AS TagArray,
        (SELECT MIN(ph_hist.CreationDate) FROM PostHistory ph_hist WHERE ph_hist.PostId = p.Id AND ph_hist.PostHistoryTypeId IN (4,5,6) AND ph_hist.UserId IS NOT NULL) AS FirstEditDateByAnyUser
    FROM
        Posts p
    LEFT JOIN (
        SELECT
            PostId,
            COUNT(Id) AS LastEditCount,
            SUM(CASE WHEN UserId = p_inner.OwnerUserId THEN 1 ELSE 0 END) AS SelfEditCount
        FROM
            PostHistory ph_inner
        JOIN
            Posts p_inner ON ph_inner.PostId = p_inner.Id
        WHERE
            ph_inner.PostHistoryTypeId IN (4, 5, 6) -- Edit Title, Edit Body, Edit Tags
        GROUP BY
            PostId
    ) ph_edits ON p.Id = ph_edits.PostId
    WHERE
        p.PostTypeId = 1 -- Questions only
        AND p.CreationDate >= CURRENT_TIMESTAMP - INTERVAL '4 years'
        AND p.Score >= 5
),
RankedTagPerformance AS (
    -- CTE 3: Ranks posts by score within specific tags, showing top-performing questions.
    -- Features: Window functions (RANK, AVG), complicated predicates, string expression.
    SELECT
        pqm.PostId,
        pqm.Title,
        pqm.OwnerUserId,
        pqm.Score,
        pqm.ViewCount,
        pqm.TagArray,
        t.TagName,
        RANK() OVER (PARTITION BY t.TagName ORDER BY pqm.Score DESC, pqm.ViewCount DESC) AS RankInTag,
        AVG(pqm.Score) OVER (PARTITION BY t.TagName) AS AvgScoreForTag,
        MAX(COALESCE(pqm.LastEditCount, 0)) OVER (PARTITION BY t.TagName) AS MaxEditsInTag
    FROM
        PostQualityMetrics pqm
    JOIN Tags t ON t.TagName = ANY(pqm.TagArray) -- Join on tags using array operator
    WHERE
        pqm.Score >= 10
        AND ARRAY_LENGTH(pqm.TagArray, 1) IS NOT NULL AND ARRAY_LENGTH(pqm.TagArray, 1) > 0
),
RecentAnswerPerformance AS (
    -- CTE 4: Aggregates performance metrics for recent answers, using a window function for ranking.
    -- Features: CTE, Window function (ROW_NUMBER), complicated calculations.
    SELECT
        a.Id AS AnswerId,
        a.ParentId AS QuestionId,
        a.OwnerUserId AS AnswerOwnerUserId,
        a.Score AS AnswerScore,
        a.CreationDate AS AnswerCreationDate,
        ROW_NUMBER() OVER (PARTITION BY a.ParentId ORDER BY a.Score DESC, a.CreationDate ASC) AS AnswerRankForQuestion
    FROM
        Posts a
    WHERE
        a.PostTypeId = 2 -- Answers only
        AND a.CreationDate >= CURRENT_TIMESTAMP - INTERVAL '2 years'
        AND a.Score > 0
),
PotentialDuplicateCandidates AS (
    -- CTE 5: Identifies potential duplicate questions based on title similarity and creation date proximity.
    -- Features: Self-join, string expressions (SIMILARITY), date arithmetic, complicated predicates.
    -- Note: SIMILARITY is a placeholder for a text similarity function, common in some SQL dialects (e.g., PostgreSQL pg_trgm).
    SELECT
        p1.Id AS Post1Id,
        p1.Title AS Post1Title,
        p1.CreationDate AS Post1CreationDate,
        p2.Id AS Post2Id,
        p2.Title AS Post2Title,
        p2.CreationDate AS Post2CreationDate,
        p1.OwnerUserId AS Post1OwnerUserId,
        p2.OwnerUserId AS Post2OwnerUserId
        -- SIMILARITY(p1.Title, p2.Title) AS TitleSimilarityScore -- Placeholder for specific function
    FROM
        Posts p1
    JOIN
        Posts p2 ON p1.Id < p2.Id -- Avoid self-join and duplicate pairs
    WHERE
        p1.PostTypeId = 1 AND p2.PostTypeId = 1
        AND p1.Title IS NOT NULL AND p2.Title IS NOT NULL
        AND p1.CreationDate BETWEEN p2.CreationDate - INTERVAL '90 days' AND p2.CreationDate + INTERVAL '90 days'
        -- AND SIMILARITY(p1.Title, p2.Title) > 0.6 -- Use if SIMILARITY is available
        AND REPLACE(LOWER(SUBSTRING(p1.Title, 1, 30)), ' ', '') LIKE '%' || REPLACE(LOWER(SUBSTRING(p2.Title, 1, 30)), ' ', '') || '%' -- A simpler, albeit less accurate, similarity check for benchmarking
    LIMIT 2000 -- Limit to avoid excessive computation on large datasets
)
-- Main Query: Combines all CTEs to generate a comprehensive report on high-impact users and their questions.
-- Features: Outer joins, correlated subqueries, CTEs, window functions, complicated predicates/expressions/calculations,
-- string expressions, NULL logic, EXISTS/NOT EXISTS (as a form of set operation).
SELECT
    ue.UserId,
    ue.DisplayName,
    ue.Reputation,
    ue.ReputationPercentile,
    ue.VoteRatio,
    ue.GoldBadges,
    ue.RecentQuestionCount,
    ue.Last90DayCommentCount,
    pqm.PostId,
    pqm.Title,
    pqm.PostCreationDate,
    pqm.Score AS QuestionScore,
    pqm.ViewCount AS QuestionViews,
    pqm.AnswerCount AS QuestionAnswerCount,
    pqm.PostStatus,
    COALESCE(pqm.LastEditCount, 0) AS TotalEditsOnQuestion,
    COALESCE(pqm.SelfEditCount, 0) AS SelfEditsOnQuestion,
    COALESCE(pqm.AcceptedAnswerScore, 0) AS EffectiveAcceptedAnswerScore, -- NULL logic
    COALESCE(rp.RankInTag, 9999) AS QuestionRankInTopTag,
    rp.TagName AS TopContributingTag,
    (
        SELECT SUM(v.BountyAmount)
        FROM Votes v
        WHERE v.PostId = pqm.PostId AND v.VoteTypeId = 8 -- BountyStart
    ) AS TotalBountyAmountOffered, -- Correlated subquery for post bounty
    UPPER(SUBSTRING(pqm.Title, 1, 5)) || '...' || LOWER(SUBSTRING(pqm.Title, LENGTH(pqm.Title) - 4)) AS TitleSnippet, -- String expressions
    (CURRENT_TIMESTAMP - ue.CreationDate) AS UserAgeFromCreation, -- Date arithmetic
    CASE
        WHEN ue.Reputation > 20000 AND pqm.Score > 100 THEN 'Very High Impact'
        WHEN ue.Reputation > 5000 AND pqm.Score > 30 THEN 'High Impact'
        WHEN ue.Reputation > 1000 AND pqm.Score > 10 THEN 'Moderate Impact'
        ELSE 'Regular Contributor'
    END AS ImpactCategory,
    AVG(rap.AnswerScore) OVER (PARTITION BY ue.UserId) AS AvgAnswerScoreByThisUser, -- Window function
    MAX(rap.AnswerRankForQuestion) OVER (PARTITION BY ue.UserId) AS BestAnswerRankForUser, -- Window function
    (SELECT COUNT(DISTINCT l.RelatedPostId) FROM PostLinks l WHERE l.PostId = pqm.PostId AND l.LinkTypeId = 3) AS NumberOfDuplicatesLinked -- Correlated subquery for linked duplicates
FROM
    UserEngagement ue
INNER JOIN
    PostQualityMetrics pqm ON ue.UserId = pqm.OwnerUserId
LEFT JOIN
    RankedTagPerformance rp ON pqm.PostId = rp.PostId AND rp.RankInTag <= 3 -- Only top 3 questions per tag
LEFT JOIN
    RecentAnswerPerformance rap ON ue.UserId = rap.AnswerOwnerUserId AND rap.QuestionId = pqm.PostId
WHERE
    ue.ReputationPercentile <= 15 -- Top 15% users by reputation
    AND pqm.PostStatus IN ('Active', 'CommunityOwned')
    AND EXISTS (
        SELECT 1 FROM Badges b_sub WHERE b_sub.UserId = ue.UserId AND b_sub.Name ILIKE '%gold%' AND b_sub.TagBased = FALSE
    ) -- Correlated subquery in WHERE: users with at least one non-tag-based 'gold' badge
    AND NOT EXISTS (
        SELECT 1 FROM PotentialDuplicateCandidates pdc WHERE pdc.Post1Id = pqm.PostId OR pdc.Post2Id = pqm.PostId
    ) -- Filter out questions flagged as potential duplicates (simulated set operator)
    AND pqm.Title IS NOT NULL
GROUP BY
    ue.UserId, ue.DisplayName, ue.Reputation, ue.ReputationPercentile, ue.VoteRatio, ue.GoldBadges, ue.RecentQuestionCount,
    ue.Last90DayCommentCount, pqm.PostId, pqm.Title, pqm.PostCreationDate, pqm.Score, pqm.ViewCount, pqm.AnswerCount,
    pqm.PostStatus, pqm.LastEditCount, pqm.SelfEditCount, pqm.AcceptedAnswerScore, rp.RankInTag, rp.TagName, ue.CreationDate
HAVING
    COUNT(rap.AnswerId) > 0 OR pqm.AnswerCount > 0 -- Ensure results have either recent answers or existing answers for the question
ORDER BY
    ue.Reputation DESC, pqm.Score DESC, ue.UserId, pqm.PostId
LIMIT 5000;
