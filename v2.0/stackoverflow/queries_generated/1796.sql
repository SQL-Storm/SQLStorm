-- {"query": "1796.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gemini-2.5-flash", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2111, "output_tokens": 3007} 

WITH UserEngagementSummary AS (
    -- CTE to summarize user engagement, badge information, and overall user metrics
    SELECT
        u.Id AS UserId,
        u.DisplayName,
        u.Reputation,
        u.CreationDate AS UserCreationDate,
        u.LastAccessDate,
        u.Views AS UserViews,
        u.UpVotes AS UserUpVotes,
        u.DownVotes AS UserDownVotes,
        u.Location,
        u.AboutMe,
        COALESCE(u.WebsiteUrl, 'NO_WEBSITE_PROVIDED') AS CoalescedWebsiteUrl, -- NULL logic (COALESCE)
        COUNT(DISTINCT p_q.Id) AS TotalQuestionsOwned,
        COUNT(DISTINCT p_a.Id) AS TotalAnswersOwned,
        COUNT(DISTINCT c.Id) AS TotalCommentsWritten,
        AVG(CASE WHEN p_all.PostTypeId IN (1, 2) THEN p_all.Score END) AS AverageOverallPostScore,
        SUM(c.Score) AS TotalCommentScoreSum,
        MIN(CASE WHEN b.Class = 1 THEN b.Date END) AS FirstGoldBadgeDate,
        MAX(CASE WHEN b.Class = 1 THEN b.Date END) AS LastGoldBadgeDate,
        COUNT(DISTINCT b.Id) FILTER (WHERE b.Class = 1 AND b.Date >= '2022-01-01') AS RecentGoldBadgesCount,
        EXTRACT(EPOCH FROM (u.LastAccessDate - u.CreationDate)) / 86400 AS DaysSinceUserCreation, -- Date calculation
        (SELECT COUNT(DISTINCT pl.RelatedPostId) -- Correlated subquery for duplicate links
         FROM Posts p_owned
         JOIN PostLinks pl ON p_owned.Id = pl.PostId
         WHERE p_owned.OwnerUserId = u.Id AND pl.LinkTypeId = 3) AS TotalDuplicateLinkedPostsByOwner,
        EXISTS (SELECT 1 FROM Badges b_corr WHERE b_corr.UserId = u.Id AND b_corr.Name = 'Strunk & White' AND b_corr.Date < u.LastAccessDate) AS HasStrunkWhiteBeforeLastAccess, -- Correlated subquery (EXISTS)
        NTILE(10) OVER (ORDER BY u.Reputation DESC, u.UpVotes DESC) AS ReputationDecile, -- Window function (NTILE)
        NULLIF(u.Views, 0) AS NonZeroUserViews -- NULL logic (NULLIF)
    FROM Users u
    LEFT JOIN Posts p_all ON u.Id = p_all.OwnerUserId
    LEFT JOIN Posts p_q ON u.Id = p_q.OwnerUserId AND p_q.PostTypeId = 1
    LEFT JOIN Posts p_a ON u.Id = p_a.OwnerUserId AND p_a.PostTypeId = 2
    LEFT JOIN Comments c ON u.Id = c.UserId
    LEFT JOIN Badges b ON u.Id = b.UserId
    GROUP BY
        u.Id, u.DisplayName, u.Reputation, u.CreationDate, u.LastAccessDate, u.Views, u.UpVotes, u.DownVotes, u.Location, u.AboutMe, u.WebsiteUrl
),
PostContentAndHistoryAnalysis AS (
    -- CTE to analyze post content, history, associated comments, and tag details
    SELECT
        p.Id AS PostId,
        p.PostTypeId,
        p.OwnerUserId,
        p.CreationDate AS PostCreationDate,
        p.LastEditDate,
        p.LastActivityDate,
        p.Score AS PostScore,
        p.ViewCount,
        p.AnswerCount,
        p.CommentCount AS PostDirectCommentCount,
        p.FavoriteCount,
        p.Title,
        p.Tags,
        COALESCE(p.ClosedDate, '9999-12-31') AS CoalescedClosedDate, -- NULL logic (COALESCE)
        COUNT(DISTINCT ph_edit.Id) AS TotalEditHistoryEntries,
        COUNT(DISTINCT ph_reopen.Id) AS ReopenEventsCount,
        MAX(CASE WHEN ph_community.PostHistoryTypeId = 16 THEN 1 ELSE 0 END) AS WasCommunityOwnedEver, -- Conditional aggregation
        SUM(CASE WHEN ph_text_change.Text LIKE '%<pre><code>%' THEN 1 ELSE 0 END) AS BodyCodeBlockEditCount, -- String expression and conditional aggregation
        AVG(sub_comments.AvgCommentScoreForPost) AS PostCommentsAverageScore,
        STRING_AGG(DISTINCT t.TagName, ';') FILTER (WHERE t.TagName IS NOT NULL) AS AssociatedTagNames, -- String aggregation
        (SELECT COUNT(DISTINCT v.UserId) FROM Votes v WHERE v.PostId = p.Id AND v.VoteTypeId = 5) AS TotalFavoriteUsers, -- Correlated subquery (COUNT)
        (string_to_array(SUBSTRING(p.Tags, 2, LENGTH(p.Tags)-2), '><'))[1] AS FirstTag, -- String parsing (string_to_array, SUBSTRING, LENGTH)
        p.Body LIKE '%<a href="http%' AS ContainsExternalLinkInBody, -- String expression (LIKE)
        NULLIF(p.ViewCount, 0) AS NonZeroPostViewCount, -- NULL logic (NULLIF)
        CASE
            WHEN p.Title LIKE '%performance%' OR p.Title LIKE '%optimize%' THEN 'PerformanceRelated'
            WHEN p.Title LIKE '%error%' OR p.Title LIKE '%bug%' THEN 'IssueRelated'
            ELSE 'General'
        END AS TitleCategory, -- Complex conditional expression
        ROW_NUMBER() OVER (PARTITION BY p.OwnerUserId ORDER BY p.CreationDate DESC) AS RowNumByOwnerForRecency, -- Window function (ROW_NUMBER)
        LEAD(p.CreationDate, 1, p.CreationDate) OVER (PARTITION BY p.OwnerUserId ORDER BY p.CreationDate) AS NextPostCreationDate, -- Window function (LEAD)
        LAG(p.CreationDate, 1, p.CreationDate) OVER (PARTITION BY p.OwnerUserId ORDER BY p.CreationDate) AS PrevPostCreationDate -- Window function (LAG)
    FROM Posts p
    LEFT JOIN PostHistory ph_edit ON p.Id = ph_edit.PostId AND ph_edit.PostHistoryTypeId IN (4, 5, 6)
    LEFT JOIN PostHistory ph_reopen ON p.Id = ph_reopen.PostId AND ph_reopen.PostHistoryTypeId = 11
    LEFT JOIN PostHistory ph_community ON p.Id = ph_community.PostId AND ph_community.PostHistoryTypeId = 16
    LEFT JOIN PostHistory ph_text_change ON p.Id = ph_text_change.PostId AND ph_text_change.PostHistoryTypeId IN (2,5,8)
    LEFT JOIN (
        SELECT c_sub.PostId, AVG(c_sub.Score) AS AvgCommentScoreForPost
        FROM Comments c_sub
        GROUP BY c_sub.PostId
    ) AS sub_comments ON p.Id = sub_comments.PostId
    LEFT JOIN Tags t ON t.TagName = ANY(string_to_array(SUBSTRING(p.Tags, 2, LENGTH(p.Tags)-2), '><')) -- JOIN with array comparison
    WHERE p.PostTypeId IN (1, 2)
    GROUP BY
        p.Id, p.PostTypeId, p.OwnerUserId, p.CreationDate, p.LastEditDate, p.LastActivityDate, p.Score, p.ViewCount, p.AnswerCount, p.CommentCount, p.FavoriteCount, p.Title, p.Tags, p.ClosedDate, p.Body
),
TopInfluentialPosters AS (
    -- CTE to identify top influential users based on their question contributions and reputation
    SELECT
        ues.UserId,
        ues.DisplayName,
        ues.Reputation,
        SUM(pda.PostScore) AS TotalQuestionsScore,
        COUNT(pda.PostId) AS TotalQuestionsContributed,
        AVG(EXTRACT(EPOCH FROM (pda.LastActivityDate - pda.CreationDate))) AS AvgPostActivityDurationSeconds,
        RANK() OVER (ORDER BY SUM(pda.PostScore) DESC, COUNT(pda.PostId) DESC) AS ScoreRank, -- Window function (RANK)
        NTH_VALUE(ues.DisplayName, 3) OVER (ORDER BY ues.Reputation DESC) AS ThirdHighestRepDisplayName -- Window function (NTH_VALUE)
    FROM UserEngagementSummary ues
    JOIN PostContentAndHistoryAnalysis pda ON ues.UserId = pda.OwnerUserId
    WHERE pda.PostTypeId = 1 -- Focus on questions for "influential posters"
    GROUP BY ues.UserId, ues.DisplayName, ues.Reputation
    HAVING SUM(pda.PostScore) > 100 -- Filtering with HAVING
)
-- Main query combining all CTEs, applying complex filtering, and final calculations
SELECT
    ues.UserId,
    ues.DisplayName,
    ues.Reputation,
    ues.TotalQuestionsOwned,
    ues.TotalAnswersOwned,
    ues.AverageOverallPostScore,
    pda.PostId,
    pda.Title AS PostTitle,
    pda.FirstTag,
    pda.TotalEditHistoryEntries,
    pda.ReopenEventsCount,
    pda.WasCommunityOwnedEver,
    pda.PostCommentsAverageScore,
    pda.AssociatedTagNames,
    tip.TotalQuestionsScore AS InfluencerTotalQuestionsScore,
    tip.ScoreRank AS InfluencerScoreRank,
    ues.ReputationDecile,
    pda.TitleCategory,
    EXTRACT(DAY FROM (pda.NextPostCreationDate - pda.PrevPostCreationDate)) AS DaysBetweenUserPosts, -- Date arithmetic
    CASE
        WHEN ues.TotalQuestionsOwned > 50 AND ues.TotalAnswersOwned > 100 AND ues.Reputation > 50000 THEN 'PowerUser'
        WHEN ues.TotalQuestionsOwned = 0 AND ues.TotalAnswersOwned > 50 AND ues.Reputation > 10000 THEN 'DedicatedAnswerer'
        WHEN ues.RecentGoldBadgesCount > 0 AND ues.AverageOverallPostScore > 10 AND ues.HasStrunkWhiteBeforeLastAccess THEN 'CuratorPlus'
        ELSE 'Contributor'
    END AS UserRoleCategory, -- Complex CASE expression
    (ues.UserUpVotes - ues.UserDownVotes) * (ues.AverageOverallPostScore + COALESCE(pda.PostCommentsAverageScore, 0)) AS CustomEngagementMetric, -- Complicated calculation with NULL logic (COALESCE)
    COALESCE(ues.Location, 'Unknown') || ' - ' || UPPER(SUBSTRING(ues.CoalescedWebsiteUrl, POSITION('//' IN ues.CoalescedWebsiteUrl) + 2, 5)) AS CombinedLocationInfo, -- String concatenation and manipulation (COALESCE, UPPER, SUBSTRING, POSITION)
    NULLIF(pda.NonZeroPostViewCount, 0) AS PostEffectiveViewCount,
    ues.DaysSinceUserCreation / NULLIF(ues.TotalQuestionsOwned + ues.TotalAnswersOwned, 0) AS AvgDaysPerPost, -- Division by NULLIF to prevent division by zero
    pda.PostScore * (1 + pda.ReopenEventsCount * 0.5) * (CASE WHEN pda.WasCommunityOwnedEver = 1 THEN 0.8 ELSE 1 END) AS AdjustedPostScore -- Complex calculation
FROM UserEngagementSummary ues
INNER JOIN PostContentAndHistoryAnalysis pda ON ues.UserId = pda.OwnerUserId
LEFT JOIN TopInfluentialPosters tip ON ues.UserId = tip.UserId
WHERE
    ues.Reputation > 10000
    AND ues.DaysSinceUserCreation > 365 * 2 -- Active for at least 2 years
    AND ues.TotalQuestionsOwned >= 5
    AND ues.TotalAnswersOwned >= 10
    AND pda.PostTypeId = 1 -- Only consider questions for the main output
    AND pda.PostScore >= 5
    AND pda.ViewCount >= 1000
    AND pda.TotalEditHistoryEntries >= 2
    AND (LOWER(ues.Location) LIKE '%london%' OR ues.Location IS NULL) -- NULL logic (IS NULL) and string expression (LOWER, LIKE)
    AND NOT pda.ContainsExternalLinkInBody -- Boolean condition
    AND ues.HasStrunkWhiteBeforeLastAccess
    AND pda.CoalescedClosedDate > NOW() - INTERVAL '1 year' -- Date comparison with INTERVAL
    AND pda.RowNumByOwnerForRecency <= 5 -- Filtering based on window function result
    AND ues.DisplayName IS NOT NULL -- NULL logic (IS NOT NULL)
ORDER BY
    AdjustedPostScore DESC,
    CustomEngagementMetric DESC,
    ues.Reputation DESC
LIMIT 1000;
