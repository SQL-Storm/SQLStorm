-- {"query": "1804.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gemini-2.5-flash", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2111, "output_tokens": 3562} 

WITH UserPerformance AS (
    -- CTE 1: Aggregates detailed user statistics, reputation ranks, and badge counts.
    -- This helps identify influential or highly active users.
    SELECT
        u.Id AS UserId,
        u.Reputation,
        u.Views AS UserProfileViews,
        u.UpVotes AS TotalUpVotesGiven,
        u.DownVotes AS TotalDownVotesGiven,
        u.CreationDate AS UserCreationDate,
        COUNT(DISTINCT p.Id) AS TotalPostsOwned,
        COUNT(CASE WHEN p.PostTypeId = 1 THEN p.Id END) AS TotalQuestionsAsked,
        COUNT(CASE WHEN p.PostTypeId = 2 THEN p.Id END) AS TotalAnswersGiven,
        SUM(COALESCE(p.Score, 0)) AS SumOfPostScoresOwned,
        SUM(CASE WHEN p.AcceptedAnswerId IS NOT NULL AND p.OwnerUserId = u.Id THEN 1 ELSE 0 END) AS AcceptedAnswersCount,
        MAX(p.CreationDate) AS LatestPostDate,
        COUNT(c.Id) AS TotalCommentsMade,
        MAX(c.CreationDate) AS LatestCommentDate,
        COUNT(DISTINCT CASE WHEN b.Class = 1 THEN b.Id END) AS GoldBadgesCount,
        COUNT(DISTINCT CASE WHEN b.Class = 2 THEN b.Id END) AS SilverBadgesCount,
        COUNT(DISTINCT CASE WHEN b.Class = 3 THEN b.Id END) AS BronzeBadgesCount,
        NTILE(10) OVER (ORDER BY u.Reputation DESC, u.UpVotes DESC) AS ReputationDecile, -- Divides users into 10 groups by reputation
        LAG(u.Reputation, 1, 0) OVER (ORDER BY u.Reputation) AS PreviousUserReputation, -- Reputation of the user just before in rank
        RANK() OVER (ORDER BY u.Reputation DESC, u.UpVotes DESC) AS GlobalReputationRank
    FROM
        Users u
    LEFT JOIN
        Posts p ON u.Id = p.OwnerUserId
    LEFT JOIN
        Comments c ON u.Id = c.UserId
    LEFT JOIN
        Badges b ON u.Id = b.UserId
    GROUP BY
        u.Id, u.Reputation, u.Views, u.UpVotes, u.DownVotes, u.CreationDate
),
PostEngagement AS (
    -- CTE 2: Analyzes post engagement, editing patterns, and interaction metrics.
    -- Includes window functions for moving averages and time differences between historical events.
    SELECT
        p.Id AS PostId,
        p.PostTypeId,
        p.CreationDate AS PostCreationDate,
        p.Score,
        p.ViewCount,
        p.AnswerCount,
        p.CommentCount AS InitialCommentCount, -- From Posts table
        p.FavoriteCount,
        p.LastEditDate,
        p.LastActivityDate,
        p.ClosedDate,
        (EXTRACT(EPOCH FROM (NOW() - p.CreationDate)) / 86400)::INT AS PostAgeDays,
        (EXTRACT(EPOCH FROM (NOW() - COALESCE(p.LastActivityDate, p.CreationDate))) / 3600)::INT AS HoursSinceLastActivity,
        COUNT(ph.Id) AS TotalHistoryEvents,
        SUM(CASE WHEN ph.PostHistoryTypeId IN (4, 5, 6) THEN 1 ELSE 0 END) AS EditCount, -- Title, Body, Tags edits
        MAX(CASE WHEN ph.PostHistoryTypeId IN (4, 5, 6) THEN ph.CreationDate END) AS LastHistoryEditDate,
        MIN(CASE WHEN ph.PostHistoryTypeId IN (4, 5, 6) THEN ph.CreationDate END) AS FirstHistoryEditDate,
        (EXTRACT(EPOCH FROM (MIN(CASE WHEN ph.PostHistoryTypeId IN (4, 5, 6) THEN ph.CreationDate END) - p.CreationDate))) AS TimeToFirstEditSeconds,
        AVG(p.Score) OVER (PARTITION BY p.OwnerUserId ORDER BY p.CreationDate ROWS BETWEEN 5 PRECEDING AND CURRENT ROW) AS OwnerPostScoreMovingAvg,
        DENSE_RANK() OVER (PARTITION BY p.PostTypeId ORDER BY p.Score DESC, p.ViewCount DESC) AS PostEngagementRank,
        LEAD(p.Score, 1, 0) OVER (PARTITION BY p.OwnerUserId ORDER BY p.CreationDate) - p.Score AS ScoreChangeToNextPost,
        CASE
            WHEN EXISTS (SELECT 1 FROM PostLinks pl WHERE pl.PostId = p.Id AND pl.LinkTypeId = 3) THEN TRUE
            ELSE FALSE
        END AS IsDuplicatePost,
        CASE
            WHEN p.AcceptedAnswerId IS NOT NULL THEN TRUE
            ELSE FALSE
        END AS HasAcceptedAnswer,
        COALESCE(p.CommunityOwnedDate IS NOT NULL, FALSE) AS IsCommunityOwned
    FROM
        Posts p
    LEFT JOIN
        PostHistory ph ON p.Id = ph.PostId
    GROUP BY
        p.Id, p.PostTypeId, p.CreationDate, p.Score, p.ViewCount, p.AnswerCount, p.CommentCount, p.FavoriteCount,
        p.LastEditDate, p.LastActivityDate, p.ClosedDate, p.OwnerUserId, p.CommunityOwnedDate
),
TagAnalysis AS (
    -- CTE 3: Extracts, counts, and ranks tags, providing insights into tag popularity and quality.
    -- Uses string manipulation and aggregation.
    SELECT
        TRIM(UNNEST(string_to_array(SUBSTRING(p.Tags FROM 2 FOR LENGTH(p.Tags)-2), '><'))) AS TagName,
        COUNT(DISTINCT p.Id) AS PostsWithTagCount,
        AVG(p.Score) AS AverageScoreForTagPosts,
        MAX(p.CreationDate) AS LatestPostWithTagDate,
        SUM(p.ViewCount) AS TotalTagViewCount,
        DENSE_RANK() OVER (ORDER BY COUNT(DISTINCT p.Id) DESC, AVG(p.Score) DESC) AS TagPopularityRank
    FROM
        Posts p
    WHERE
        p.Tags IS NOT NULL AND LENGTH(p.Tags) > 2 -- Ensure tags string is not empty or just "<>"
    GROUP BY
        TRIM(UNNEST(string_to_array(SUBSTRING(p.Tags FROM 2 FOR LENGTH(p.Tags)-2), '><')))
    HAVING
        COUNT(DISTINCT p.Id) > 10 -- Only consider tags used in more than 10 posts
),
ModerationOverview AS (
    -- CTE 4: Focuses on moderation actions, tracking close/reopen events and their timings.
    -- Includes correlated subquery to fetch the specific close reason name.
    SELECT
        ph.PostId,
        ph.PostHistoryTypeId,
        ph.CreationDate AS EventTimestamp,
        ph.UserId AS ModeratorActorId,
        COALESCE(u.DisplayName, ph.UserDisplayName) AS ModeratorActorDisplayName,
        ph.Comment AS EventComment,
        cr.Name AS CloseReasonName,
        LAG(ph.CreationDate) OVER (PARTITION BY ph.PostId ORDER BY ph.CreationDate) AS PreviousModerationEventTime,
        EXTRACT(EPOCH FROM (ph.CreationDate - LAG(ph.CreationDate) OVER (PARTITION BY ph.PostId ORDER BY ph.CreationDate))) AS SecondsSinceLastModEvent,
        COUNT(CASE WHEN ph.PostHistoryTypeId = 10 THEN 1 END) OVER (PARTITION BY ph.PostId) AS TotalCloseEventsForPost,
        COUNT(CASE WHEN ph.PostHistoryTypeId = 11 THEN 1 END) OVER (PARTITION BY ph.PostId) AS TotalReopenEventsForPost,
        ROW_NUMBER() OVER (PARTITION BY ph.PostId, ph.PostHistoryTypeId ORDER BY ph.CreationDate DESC) AS LatestEventTypeRank
    FROM
        PostHistory ph
    LEFT JOIN
        Users u ON ph.UserId = u.Id
    LEFT JOIN
        CloseReasonTypes cr ON ph.PostHistoryTypeId = 10 AND ph.Comment = cr.Id::text -- Correlated condition on PostHistoryTypeId
    WHERE
        ph.PostHistoryTypeId IN (10, 11, 12, 13, 14, 15, 19, 20) -- Close, Reopen, Delete, Undelete, Lock, Unlock, Protect, Unprotect
)
-- Main query: Combines insights from all CTEs to generate a comprehensive view of posts, users, tags, and moderation.
SELECT
    p.Id AS Post_ID,
    pt.Name AS Post_Type_Name,
    p.Title AS Post_Title,
    COALESCE(u.DisplayName, p.OwnerDisplayName, 'Deleted User') AS Post_Owner_DisplayName,
    up.Reputation AS Owner_Reputation,
    up.TotalPostsOwned AS Owner_Total_Posts,
    up.TotalQuestionsAsked AS Owner_Questions_Asked,
    up.GoldBadgesCount AS Owner_Gold_Badges,
    pe.Score AS Post_Score,
    pe.ViewCount AS Post_View_Count,
    pe.InitialCommentCount AS Post_Initial_Comment_Count,
    (SELECT COUNT(c.Id) FROM Comments c WHERE c.PostId = p.Id) AS Current_Total_Comments, -- Correlated subquery for actual comment count
    pe.FavoriteCount AS Post_Favorite_Count,
    pe.PostAgeDays AS Post_Age_In_Days,
    pe.HoursSinceLastActivity AS Hours_Since_Last_Activity,
    pe.EditCount AS Post_Edit_Count,
    pe.TimeToFirstEditSeconds AS Time_To_First_Edit_Seconds,
    pe.PostEngagementRank AS Post_Engagement_Rank,
    pe.OwnerPostScoreMovingAvg AS Owner_Post_Score_Moving_Avg,
    pe.IsDuplicatePost AS Is_Duplicate_Post_Flag,
    pe.HasAcceptedAnswer AS Has_Accepted_Answer_Flag,
    pe.IsCommunityOwned AS Is_Community_Owned_Flag,
    STRING_AGG(ta.TagName, ', ') AS Associated_Tags_List, -- Aggregates tags for display
    MAX(ta.AverageScoreForTagPosts) AS Max_Avg_Score_Of_Associated_Tags,
    MAX(CASE WHEN mo.PostHistoryTypeId = 10 AND mo.LatestEventTypeRank = 1 THEN mo.EventTimestamp END) AS Last_Closed_Date,
    MAX(CASE WHEN mo.PostHistoryTypeId = 11 AND mo.LatestEventTypeRank = 1 THEN mo.EventTimestamp END) AS Last_Reopened_Date,
    MAX(CASE WHEN mo.PostHistoryTypeId = 10 AND mo.LatestEventTypeRank = 1 THEN mo.CloseReasonName END) AS Last_Close_Reason,
    MAX(mo.TotalCloseEventsForPost) AS Total_Times_Closed,
    MAX(mo.TotalReopenEventsForPost) AS Total_Times_Reopened,
    (SELECT COUNT(DISTINCT vl.PostId) FROM PostLinks pl LEFT JOIN Posts vl ON pl.PostId = vl.Id WHERE pl.RelatedPostId = p.Id AND pl.LinkTypeId = 1) AS Count_Of_Posts_Linking_To_This, -- Correlated subquery
    (SELECT SUM(v.BountyAmount) FROM Votes v WHERE v.PostId = p.Id AND v.VoteTypeId = 8) AS Total_Bounty_Amount, -- Correlated subquery
    CASE
        WHEN pe.Score >= 200 AND pe.PostAgeDays < 90 AND pe.HasAcceptedAnswer AND up.Reputation > 10000 THEN 'Highly_Successful_Recent_Post_By_Veteran'
        WHEN pe.EditCount > 10 AND pe.Score < 10 AND pe.IsDuplicatePost THEN 'Problematic_Heavily_Edited_Duplicate'
        WHEN pe.TotalHistoryEvents > 50 AND pe.IsCommunityOwned THEN 'Community_Managed_High_Activity'
        WHEN p.ClosedDate IS NOT NULL AND (SELECT COUNT(DISTINCT Id) FROM PostHistory ph_inner WHERE ph_inner.PostId = p.Id AND ph_inner.PostHistoryTypeId = 11) > 0 THEN 'Closed_Then_Reopened_Post'
        WHEN p.Title ILIKE '%performance%' OR p.Body ILIKE '%optimization%' THEN 'Performance_Related_Content'
        ELSE 'General_Content'
    END AS Post_Quality_Category,
    up.ReputationDecile,
    up.GlobalReputationRank
FROM
    Posts p
INNER JOIN
    PostTypes pt ON p.PostTypeId = pt.Id
LEFT JOIN
    UserPerformance up ON p.OwnerUserId = up.UserId
LEFT JOIN
    Users u ON p.OwnerUserId = u.Id -- To get the current DisplayName if available
LEFT JOIN
    PostEngagement pe ON p.Id = pe.PostId
LEFT JOIN LATERAL (
    -- Lateral join to efficiently split and join tags from Posts to TagAnalysis
    SELECT
        ta.TagName,
        ta.AverageScoreForTagPosts
    FROM
        TagAnalysis ta
    WHERE
        p.Tags LIKE '%' || ta.TagName || '%' -- Uses string matching against pre-aggregated tags
) AS ta ON TRUE
LEFT JOIN LATERAL (
    -- Lateral join to get the most recent relevant moderation event for each post
    SELECT
        mo.EventTimestamp,
        mo.PostHistoryTypeId,
        mo.CloseReasonName,
        mo.TotalCloseEventsForPost,
        mo.TotalReopenEventsForPost
    FROM
        ModerationOverview mo
    WHERE
        mo.PostId = p.Id AND mo.LatestEventTypeRank = 1 -- Get only the latest event of each type (close, reopen, etc.)
    ORDER BY mo.EventTimestamp DESC
    LIMIT 1
) AS mo ON TRUE
WHERE
    p.CreationDate >= NOW() - INTERVAL '3 year' -- Focus on recent posts
    AND p.ViewCount > 1000
    AND (p.Score >= 50 OR pe.EditCount > 5) -- High-scoring OR heavily edited posts
    AND (u.Location IS NOT NULL OR u.WebsiteUrl IS NOT NULL OR up.GoldBadgesCount >= 1) -- User has some profile info or a gold badge
    AND NOT (p.Body ILIKE '%spam%' OR p.Title ILIKE '%spam%') -- Filter out obvious spam
    AND COALESCE(pe.IsDuplicatePost, FALSE) = FALSE -- Only non-duplicate posts or where info is missing
GROUP BY
    p.Id, pt.Name, p.Title, COALESCE(u.DisplayName, p.OwnerDisplayName, 'Deleted User'), up.Reputation, up.TotalPostsOwned, up.TotalQuestionsAsked, up.GoldBadgesCount,
    pe.Score, pe.ViewCount, pe.InitialCommentCount, pe.FavoriteCount, pe.PostAgeDays, pe.HoursSinceLastActivity, pe.EditCount, pe.TimeToFirstEditSeconds,
    pe.PostEngagementRank, pe.OwnerPostScoreMovingAvg, pe.IsDuplicatePost, pe.HasAcceptedAnswer, pe.IsCommunityOwned,
    p.CreationDate, p.ClosedDate, up.ReputationDecile, up.GlobalReputationRank
ORDER BY
    Post_Score DESC, Post_View_Count DESC, Owner_Reputation DESC, Post_Age_In_Days ASC
LIMIT 1000;
