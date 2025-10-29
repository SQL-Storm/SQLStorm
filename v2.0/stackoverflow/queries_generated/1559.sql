-- {"query": "1559.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gemini-2.5-flash", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2111, "output_tokens": 3320} 

WITH UserActivitySummary AS (
    -- CTE 1: Summarize user activities and filter a base set of active, reputable users.
    SELECT
        u.Id AS UserId,
        u.DisplayName,
        u.Reputation,
        u.CreationDate AS UserCreationDate,
        u.LastAccessDate,
        u.Location,
        u.Views AS UserProfileViews,
        u.UpVotes AS UserUpVotes,
        u.DownVotes AS UserDownVotes,
        COUNT(DISTINCT p.Id) AS TotalPostsOwned,
        COUNT(DISTINCT CASE WHEN p.PostTypeId = 1 THEN p.Id END) AS TotalQuestionsOwned,
        COUNT(DISTINCT CASE WHEN p.PostTypeId = 2 THEN p.Id END) AS TotalAnswersOwned,
        AVG(CASE WHEN p.Score IS NOT NULL THEN p.Score ELSE 0 END) AS AvgPostScoreOwned,
        MAX(p.LastActivityDate) AS LastPostActivityDate,
        COUNT(DISTINCT b.Id) AS TotalBadges,
        SUM(CASE WHEN b.Class = 1 THEN 1 ELSE 0 END) AS GoldBadges,
        SUM(CASE WHEN b.TagBased = TRUE THEN 1 ELSE 0 END) AS TagBasedBadges,
        (EXTRACT(EPOCH FROM (u.LastAccessDate - u.CreationDate)) / 86400)::INT AS DaysSinceCreation
    FROM Users AS u
    LEFT JOIN Posts AS p ON u.Id = p.OwnerUserId
    LEFT JOIN Badges AS b ON u.Id = b.UserId
    WHERE
        u.Reputation >= 10000 -- Filter for highly reputable users
        AND u.CreationDate BETWEEN '2015-01-01' AND '2020-01-01' -- Users created in a specific period
        AND u.Location IS NOT NULL
        AND u.Location NOT ILIKE '%internet%' -- Exclude generic or empty locations
        AND u.DisplayName IS NOT NULL
    GROUP BY
        u.Id, u.DisplayName, u.Reputation, u.CreationDate, u.LastAccessDate,
        u.Location, u.Views, u.UpVotes, u.DownVotes
),
PostEngagementMetrics AS (
    -- CTE 2: Calculate various engagement metrics for posts owned by the users from CTE 1.
    SELECT
        p.Id AS PostId,
        p.OwnerUserId,
        p.PostTypeId,
        p.CreationDate AS PostCreationDate,
        p.Score AS PostScore,
        p.ViewCount,
        p.AnswerCount,
        p.CommentCount,
        p.FavoriteCount,
        p.LastEditDate,
        p.LastActivityDate,
        p.Title,
        p.Tags,
        p.AcceptedAnswerId,
        COALESCE((SELECT SUM(c.Score) FROM Comments AS c WHERE c.PostId = p.Id), 0) AS TotalCommentScore,
        COALESCE((SELECT COUNT(DISTINCT ph.Id) FROM PostHistory AS ph WHERE ph.PostId = p.Id AND ph.PostHistoryTypeId IN (4, 5, 6, 7, 8, 9)), 0) AS EditCount, -- Title/Body/Tags edits
        COALESCE((SELECT COUNT(DISTINCT ph.Id) FROM PostHistory AS ph WHERE ph.PostId = p.Id AND ph.PostHistoryTypeId IN (10, 11)), 0) AS CloseReopenCount, -- Close/Reopen events
        COALESCE((SELECT COUNT(DISTINCT v.UserId) FROM Votes AS v WHERE v.PostId = p.Id AND v.VoteTypeId IN (2, 3)), 0) AS UniqueVoterCount, -- Up/Down votes
        AGE(p.LastActivityDate, p.CreationDate) AS PostActivityDuration, -- Time difference between activity and creation
        COALESCE(p.FavoriteCount, 0) AS CoalescedFavoriteCount,
        CASE
            WHEN p.ClosedDate IS NOT NULL AND p.CommunityOwnedDate IS NOT NULL THEN 'ClosedAndCommunityWiki'
            WHEN p.ClosedDate IS NOT NULL THEN 'Closed'
            WHEN p.CommunityOwnedDate IS NOT NULL THEN 'CommunityWiki'
            ELSE 'Open'
        END AS PostStatus
    FROM Posts AS p
    WHERE p.PostTypeId IN (1, 2) -- Focus on Questions (1) and Answers (2)
      AND p.CreationDate BETWEEN '2016-01-01' AND '2022-01-01' -- Posts within a specific timeframe
      AND p.Score > 5 -- Filter for posts with some positive score
),
CalculatedPostScores AS (
    -- CTE 3: Combine user and post metrics, calculate a complex Post Impact Score, and rank posts per user.
    SELECT
        pem.*,
        uas.DisplayName AS OwnerDisplayName,
        uas.Reputation AS OwnerReputation,
        -- Complex Post Impact Score Calculation: a weighted sum of various post attributes
        (
            (pem.PostScore * 0.7) +
            (COALESCE(pem.ViewCount, 0) * 0.005) + -- ViewCount is usually very high, scale down
            (COALESCE(pem.AnswerCount, 0) * 0.1) +
            (pem.CoalescedFavoriteCount * 0.2) +
            (pem.EditCount * 5) + -- Edits suggest ongoing engagement/refinement
            (pem.CloseReopenCount * 15) + -- Close/reopen cycles suggest significant attention/controversy
            (pem.TotalCommentScore * 0.05) +
            (CASE WHEN pem.AcceptedAnswerId IS NOT NULL THEN 100 ELSE 0 END) + -- Bonus for accepted answer
            (pem.UniqueVoterCount * 3) +
            (CASE WHEN pem.Tags IS NOT NULL THEN (LENGTH(pem.Tags) - LENGTH(REPLACE(pem.Tags, '><', '')) + 1) * 2 ELSE 0 END) -- Bonus for number of tags, implying relevance
        ) AS PostImpactScore,
        -- Get the score of the previous post by the same user to show trend, default to 0 for the first post
        LAG(pem.PostScore, 1, 0) OVER (PARTITION BY pem.OwnerUserId ORDER BY pem.PostCreationDate) AS PreviousPostScore,
        -- Rank posts by their impact score within each user's contributions
        ROW_NUMBER() OVER (PARTITION BY pem.OwnerUserId ORDER BY pem.PostImpactScore DESC, pem.ViewCount DESC) AS Rnk_PostImpactPerUser,
        -- Categorize posts into 10 deciles based on their overall impact score
        NTILE(10) OVER (ORDER BY (
            (pem.PostScore * 0.7) + (COALESCE(pem.ViewCount, 0) * 0.005) +
            (COALESCE(pem.AnswerCount, 0) * 0.1) + (pem.CoalescedFavoriteCount * 0.2) +
            (pem.EditCount * 5) + (pem.CloseReopenCount * 15) +
            (pem.TotalCommentScore * 0.05) + (CASE WHEN pem.AcceptedAnswerId IS NOT NULL THEN 100 ELSE 0 END) +
            (pem.UniqueVoterCount * 3) + (CASE WHEN pem.Tags IS NOT NULL THEN (LENGTH(pem.Tags) - LENGTH(REPLACE(pem.Tags, '><', '')) + 1) * 2 ELSE 0 END)
        ) DESC) AS PostImpactDecile
    FROM PostEngagementMetrics AS pem
    INNER JOIN UserActivitySummary AS uas ON pem.OwnerUserId = uas.UserId
),
UserContributionSummary AS (
    -- CTE 4: Aggregate post scores back to the user level and calculate an overall user contribution score.
    SELECT
        uas.UserId,
        uas.DisplayName,
        uas.Reputation,
        uas.UserCreationDate,
        uas.Location,
        uas.TotalBadges,
        uas.GoldBadges,
        uas.TagBasedBadges,
        uas.TotalPostsOwned,
        uas.TotalQuestionsOwned,
        uas.TotalAnswersOwned,
        SUM(cps.PostImpactScore) AS AggregateUserPostImpact,
        AVG(cps.PostImpactScore) AS AvgUserPostImpact,
        (
            uas.Reputation * 0.3 +
            uas.UserProfileViews * 0.005 + -- Scale down user profile views
            uas.UserUpVotes * 0.1 +
            uas.TotalBadges * 10 +
            (SUM(cps.PostImpactScore) * 0.02) + -- Incorporate aggregate post impact
            (uas.TotalQuestionsOwned * 25) +
            (uas.TotalAnswersOwned * 20) +
            (uas.DaysSinceCreation * 0.5) -- Users who have been active longer get a slight boost
        ) AS UserOverallContributionScore,
        -- Rank users based on their overall contribution score
        RANK() OVER (ORDER BY (
            uas.Reputation * 0.3 + uas.UserProfileViews * 0.005 + uas.UserUpVotes * 0.1 +
            uas.TotalBadges * 10 + (SUM(cps.PostImpactScore) * 0.02) +
            (uas.TotalQuestionsOwned * 25) + (uas.TotalAnswersOwned * 20) +
            (uas.DaysSinceCreation * 0.5)
        ) DESC) AS Rank_OverallUser,
        -- Categorize users into 5 quintiles based on their overall contribution score
        NTILE(5) OVER (ORDER BY (
            uas.Reputation * 0.3 + uas.UserProfileViews * 0.005 + uas.UserUpVotes * 0.1 +
            uas.TotalBadges * 10 + (SUM(cps.PostImpactScore) * 0.02) +
            (uas.TotalQuestionsOwned * 25) + (uas.TotalAnswersOwned * 20) +
            (uas.DaysSinceCreation * 0.5)
        ) DESC) AS UserContributionQuintile
    FROM UserActivitySummary AS uas
    INNER JOIN CalculatedPostScores AS cps ON uas.UserId = cps.OwnerUserId
    WHERE cps.Rnk_PostImpactPerUser <= 5 -- Only consider a user's top 5 posts for their aggregate impact
    GROUP BY
        uas.UserId, uas.DisplayName, uas.Reputation, uas.UserCreationDate, uas.Location,
        uas.TotalBadges, uas.GoldBadges, uas.TagBasedBadges, uas.TotalPostsOwned,
        uas.TotalQuestionsOwned, uas.TotalAnswersOwned, uas.UserProfileViews, uas.UserUpVotes, uas.DaysSinceCreation
)
-- Final SELECT: Retrieve user and their top posts information, applying further filters.
SELECT
    ucs.DisplayName AS User_DisplayName,
    ucs.Reputation AS User_Reputation,
    ucs.Location AS User_Location,
    ucs.UserCreationDate,
    ucs.TotalBadges,
    ucs.GoldBadges,
    ucs.TagBasedBadges,
    ucs.TotalQuestionsOwned,
    ucs.TotalAnswersOwned,
    ucs.UserOverallContributionScore,
    ucs.Rank_OverallUser,
    ucs.UserContributionQuintile,
    cps.Title AS Post_Title,
    cps.PostTypeId AS Post_Type,
    cps.PostCreationDate,
    cps.PostScore AS Post_Score,
    cps.ViewCount AS Post_ViewCount,
    cps.AnswerCount AS Post_AnswerCount,
    cps.CoalescedFavoriteCount AS Post_FavoriteCount,
    cps.EditCount AS Post_EditCount,
    cps.CloseReopenCount AS Post_CloseReopenCount,
    cps.UniqueVoterCount AS Post_UniqueVoterCount,
    cps.PostImpactScore,
    cps.Rnk_PostImpactPerUser,
    cps.PostImpactDecile,
    -- Extract the first tag from the tags string using string manipulation
    (SELECT t.TagName FROM Tags AS t WHERE t.TagName = SUBSTRING(cps.Tags, 2, POSITION('>' IN cps.Tags) - 2) LIMIT 1) AS PrimaryTag,
    CASE
        WHEN cps.PostStatus LIKE '%Closed%' THEN TRUE
        ELSE FALSE
    END AS IsClosed,
    COALESCE(pl.LinkTypeId, 0) AS RelatedLinkType, -- Use COALESCE for NULL if no related links
    COALESCE(pl.RelatedPostId, -1) AS RelatedPostId, -- Use COALESCE for NULL if no related posts
    -- Correlated subquery: Calculate the average score of comments for this specific post
    (SELECT AVG(s.Score) FROM Comments AS s WHERE s.PostId = cps.PostId AND s.CreationDate BETWEEN cps.PostCreationDate AND cps.LastActivityDate) AS AvgCommentScoreForPost
FROM UserContributionSummary AS ucs
INNER JOIN CalculatedPostScores AS cps ON ucs.UserId = cps.OwnerUserId
LEFT JOIN (
    -- Subquery to select only one linked or duplicate post per PostId to avoid potential Cartesian products
    SELECT DISTINCT ON (PostId) PostId, RelatedPostId, LinkTypeId
    FROM PostLinks
    WHERE LinkTypeId IN (1, 3) -- 1 = Linked, 3 = Duplicate
) AS pl ON cps.PostId = pl.PostId
WHERE
    cps.Rnk_PostImpactPerUser <= 3 -- Retrieve only the top 3 highest-impact posts for each selected user
    AND ucs.UserContributionQuintile <= 2 -- Focus on users in the top 2 quintiles of overall contribution
    AND (
        cps.Tags ILIKE '%<sql>%' OR
        cps.Tags ILIKE '%<database>%' OR
        cps.Tags ILIKE '%<performance>%' OR
        cps.Tags ILIKE '%<optimization>%'
    ) -- Filter for posts related to specific technical topics
    AND ucs.DisplayName IS NOT NULL
    AND cps.Title IS NOT NULL
    AND cps.PostActivityDuration IS NOT NULL
ORDER BY
    ucs.UserOverallContributionScore DESC,
    ucs.DisplayName ASC,
    cps.PostImpactScore DESC;
