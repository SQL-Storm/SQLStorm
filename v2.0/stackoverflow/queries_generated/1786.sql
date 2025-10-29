-- {"query": "1786.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gemini-2.5-flash", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2111, "output_tokens": 3344} 

WITH UserPostMetrics AS (
    SELECT
        p.Id AS PostId,
        p.PostTypeId,
        p.OwnerUserId,
        p.CreationDate AS PostCreationDate,
        p.Score,
        p.ViewCount,
        p.Body,
        p.Title,
        p.Tags,
        p.AnswerCount,
        p.CommentCount,
        p.FavoriteCount,
        -- Calculate self-edit count using a correlated subquery
        (SELECT COUNT(ph.Id)
         FROM PostHistory ph
         WHERE ph.PostId = p.Id
           AND ph.UserId = p.OwnerUserId
           AND ph.PostHistoryTypeId IN (4, 5, 6, 7, 8, 9) -- Edit Title, Edit Body, Edit Tags, Rollback Title, Rollback Body, Rollback Tags
        ) AS SelfEditCount,
        -- Determine if the post is an accepted answer or a question with an accepted answer
        CASE
            WHEN p.PostTypeId = 1 AND p.AcceptedAnswerId IS NOT NULL THEN TRUE
            WHEN p.PostTypeId = 2 AND EXISTS (SELECT 1 FROM Posts q WHERE q.AcceptedAnswerId = p.Id) THEN TRUE
            ELSE FALSE
        END AS IsAcceptedOrHasAcceptedAnswer,
        -- Window function: Rank user's posts by score
        ROW_NUMBER() OVER (PARTITION BY p.OwnerUserId ORDER BY p.Score DESC, p.CreationDate DESC) AS UserPostScoreRank
    FROM
        Posts p
    WHERE
        p.OwnerUserId IS NOT NULL
        AND p.CreationDate >= (CURRENT_TIMESTAMP - INTERVAL '5 years') -- Focus on recent activity
),
UserEngagementSummary AS (
    SELECT
        u.Id AS UserId,
        u.DisplayName,
        u.Reputation,
        u.CreationDate AS UserCreationDate,
        u.LastAccessDate,
        u.WebsiteUrl,
        u.Location,
        u.Views AS UserProfileViews,
        u.UpVotes AS UserUpVotesGiven,
        u.DownVotes AS UserDownVotesGiven,
        -- Aggregate badge counts
        COUNT(CASE WHEN b.Class = 1 THEN 1 END) AS GoldBadges,
        COUNT(CASE WHEN b.Class = 2 THEN 1 END) AS SilverBadges,
        COUNT(CASE WHEN b.Class = 3 THEN 1 END) AS BronzeBadges,
        -- Aggregate vote counts received across all their posts (using a subquery to avoid fanout before aggregation)
        COALESCE(SUM(PostVoteAgg.Upvotes), 0) AS TotalUpvotesReceived,
        COALESCE(SUM(PostVoteAgg.Downvotes), 0) AS TotalDownvotesReceived
    FROM
        Users u
    LEFT JOIN
        Badges b ON u.Id = b.UserId
    LEFT JOIN (
        SELECT
            p.OwnerUserId,
            SUM(CASE WHEN vt.Name = 'UpMod' THEN 1 ELSE 0 END) AS Upvotes,
            SUM(CASE WHEN vt.Name = 'DownMod' THEN 1 ELSE 0 END) AS Downvotes
        FROM
            Posts p
        JOIN
            Votes v ON p.Id = v.PostId
        JOIN
            VoteTypes vt ON v.VoteTypeId = vt.Id
        WHERE vt.Name IN ('UpMod', 'DownMod')
        GROUP BY p.OwnerUserId
    ) AS PostVoteAgg ON u.Id = PostVoteAgg.OwnerUserId
    GROUP BY
        u.Id, u.DisplayName, u.Reputation, u.CreationDate, u.LastAccessDate, u.WebsiteUrl, u.Location,
        u.Views, u.UpVotes, u.DownVotes
),
PostTagAnalysis AS (
    SELECT
        p.Id AS PostId,
        p.Title,
        p.Tags,
        unnest(string_to_array(trim(both '<>' from p.Tags), '><')) AS ExtractedTag
    FROM
        Posts p
    WHERE
        p.PostTypeId = 1 -- Only questions generally have tags in this format
        AND p.Tags IS NOT NULL
        AND LENGTH(p.Tags) > 2 -- Ensure not just '<>'
),
PopularTagsWithStats AS (
    SELECT
        pta.ExtractedTag AS TagName,
        COUNT(DISTINCT pta.PostId) AS TotalTaggedQuestions,
        COALESCE(AVG(p.Score), 0) AS AverageTagQuestionScore,
        SUM(p.ViewCount) AS TotalTagViewCount,
        -- Window function: Rank tags by popularity
        DENSE_RANK() OVER (ORDER BY COUNT(DISTINCT pta.PostId) DESC, COALESCE(AVG(p.Score), 0) DESC) AS TagPopularityRank
    FROM
        PostTagAnalysis pta
    JOIN
        Posts p ON pta.PostId = p.Id
    GROUP BY
        pta.ExtractedTag
    HAVING
        COUNT(DISTINCT pta.PostId) > 50 -- Filter for reasonably popular tags
),
PostCommentSentiment AS (
    SELECT
        c.PostId,
        COUNT(c.Id) AS CommentCount,
        AVG(c.Score) AS AvgCommentScore,
        SUM(CASE WHEN c.Text ILIKE '%thank%' OR c.Text ILIKE '%great%' OR c.Text ILIKE '%helpful%' THEN 1 ELSE 0 END) AS PositiveCommentCount,
        SUM(CASE WHEN c.Text ILIKE '%bug%' OR c.Text ILIKE '%error%' OR c.Text ILIKE '%issue%' THEN 1 ELSE 0 END) AS NegativeCommentCount,
        MAX(CASE WHEN c.Text ILIKE '%solution%' THEN TRUE ELSE FALSE END) AS HasSolutionKeywordComment
    FROM
        Comments c
    GROUP BY
        c.PostId
),
-- CTE with Set Operator: Identify posts that are either trending or controversial
TrendingControversialPosts AS (
    -- Trending Posts: High score, recent activity
    SELECT
        p.Id AS PostId,
        p.Title,
        p.Score,
        p.CreationDate,
        'Trending' AS PostTypeCategory,
        NULL::text AS ControversyReason -- NULL logic example
    FROM
        Posts p
    WHERE
        p.PostTypeId = 1 -- Questions
        AND p.Score > 50
        AND p.ViewCount > 5000
        AND p.CreationDate > (CURRENT_TIMESTAMP - INTERVAL '6 months')
    UNION ALL
    -- Controversial Posts: Significant upvotes AND significant downvotes relative to total votes
    SELECT
        p.Id AS PostId,
        p.Title,
        p.Score,
        p.CreationDate,
        'Controversial' AS PostTypeCategory,
        CASE
            WHEN (CAST(PostVoteStats.DownVoteCount AS DECIMAL) / NULLIF(PostVoteStats.UpVoteCount + PostVoteStats.DownVoteCount, 0)) > 0.25 THEN 'High Downvote Ratio'
            ELSE 'Mixed Opinions'
        END AS ControversyReason
    FROM
        Posts p
    JOIN (
        SELECT
            v.PostId,
            SUM(CASE WHEN vt.Name = 'UpMod' THEN 1 ELSE 0 END) AS UpVoteCount,
            SUM(CASE WHEN vt.Name = 'DownMod' THEN 1 ELSE 0 END) AS DownVoteCount
        FROM
            Votes v
        JOIN
            VoteTypes vt ON v.VoteTypeId = vt.Id
        WHERE vt.Name IN ('UpMod', 'DownMod')
        GROUP BY
            v.PostId
        HAVING
            SUM(CASE WHEN vt.Name = 'UpMod' THEN 1 ELSE 0 END) > 20 -- at least 20 upvotes
            AND SUM(CASE WHEN vt.Name = 'DownMod' THEN 1 ELSE 0 END) > 5 -- at least 5 downvotes
            AND (CAST(SUM(CASE WHEN vt.Name = 'DownMod' THEN 1 ELSE 0 END) AS DECIMAL) /
                 NULLIF(SUM(CASE WHEN vt.Name = 'UpMod' THEN 1 ELSE 0 END) + SUM(CASE WHEN vt.Name = 'DownMod' THEN 1 ELSE 0 END), 0)) > 0.15 -- downvotes make up at least 15% of total votes
    ) AS PostVoteStats ON p.Id = PostVoteStats.PostId
    WHERE p.PostTypeId IN (1, 2) -- Questions or Answers
)
-- Main Query: Analyze users and their top posts, linking to tag performance, comment sentiment, and trending/controversial status
SELECT
    u.UserId,
    u.DisplayName,
    u.Reputation,
    u.UserCreationDate,
    u.LastAccessDate,
    u.WebsiteUrl,
    u.Location,
    u.GoldBadges,
    u.SilverBadges,
    u.BronzeBadges,
    u.TotalUpvotesReceived,
    u.TotalDownvotesReceived,
    -- User level activity metrics based on their posts
    COALESCE(SUM(CASE WHEN upm.PostTypeId = 1 THEN 1 ELSE 0 END), 0) AS TotalQuestionsByOwner,
    COALESCE(SUM(CASE WHEN upm.PostTypeId = 2 THEN 1 ELSE 0 END), 0) AS TotalAnswersByOwner,
    COALESCE(SUM(upm.Score), 0) AS TotalScoreFromOwnedPosts,
    COALESCE(SUM(upm.ViewCount), 0) AS TotalViewsFromOwnedPosts,
    COALESCE(SUM(upm.FavoriteCount), 0) AS TotalFavoriteCountFromOwnedPosts,
    COALESCE(SUM(upm.SelfEditCount), 0) AS TotalSelfEditsByOwner,
    -- Top Post details (e.g., the user's highest scored question)
    MAX(CASE WHEN upm.UserPostScoreRank = 1 AND upm.PostTypeId = 1 THEN upm.Title END) AS TopQuestionTitle,
    MAX(CASE WHEN upm.UserPostScoreRank = 1 AND upm.PostTypeId = 1 THEN upm.Score END) AS TopQuestionScore,
    MAX(CASE WHEN upm.UserPostScoreRank = 1 AND upm.PostTypeId = 1 THEN upm.ViewCount END) AS TopQuestionViewCount,
    -- Complicated calculation: Ratio of accepted answers to total answers for the user
    CAST(COUNT(DISTINCT CASE WHEN upm.PostTypeId = 2 AND upm.IsAcceptedOrHasAcceptedAnswer THEN upm.PostId END) AS DECIMAL) /
        NULLIF(COUNT(DISTINCT CASE WHEN upm.PostTypeId = 2 THEN upm.PostId END), 0) AS AcceptedAnswerRatio,
    -- Correlated subquery for a user's most active post by comments
    (SELECT p_corr.Title
     FROM Posts p_corr
     WHERE p_corr.OwnerUserId = u.UserId
     ORDER BY p_corr.CommentCount DESC, p_corr.Score DESC
     LIMIT 1
    ) AS MostCommentedPostTitle,
    -- Information about tags of user's top post
    STRING_AGG(DISTINCT pts.TagName, ', ') FILTER (WHERE pts.TagName IS NOT NULL) AS TopPostTags,
    COALESCE(AVG(pts.AverageTagQuestionScore), 0) AS AvgScoreOfAssociatedTags,
    COALESCE(MIN(pts.TagPopularityRank), 999999) AS MinTagPopularityRankForTopPostTags,
    -- NULL logic and complex expressions to categorize users
    CASE
        WHEN u.Reputation > 10000 AND COALESCE(SUM(upm.SelfEditCount), 0) > 20 THEN 'Veteran Editor'
        WHEN u.GoldBadges > 0 OR u.TotalUpvotesReceived > 5000 THEN 'Elite Contributor'
        WHEN u.Reputation > 2000 AND (CAST(COUNT(DISTINCT CASE WHEN upm.PostTypeId = 2 AND upm.IsAcceptedOrHasAcceptedAnswer THEN upm.PostId END) AS DECIMAL) /
                                       NULLIF(COUNT(DISTINCT CASE WHEN upm.PostTypeId = 2 THEN upm.PostId END), 0)) > 0.6 THEN 'Answer Guru'
        WHEN u.Location IS NULL OR LENGTH(TRIM(u.Location)) = 0 THEN 'Location Undisclosed Contributor'
        WHEN u.DisplayName IS NULL OR LENGTH(TRIM(u.DisplayName)) = 0 THEN 'Anonymous User'
        ELSE 'Active User'
    END AS UserCategory,
    -- Join with comment sentiment
    COALESCE(AVG(pcs.AvgCommentScore), 0) AS AvgCommentScoreOnUserPosts,
    COALESCE(SUM(pcs.PositiveCommentCount), 0) AS TotalPositiveCommentsOnUserPosts,
    COALESCE(SUM(pcs.NegativeCommentCount), 0) AS TotalNegativeCommentsOnUserPosts,
    -- Information if the user's top post is trending or controversial
    MAX(tcp.PostTypeCategory) AS TopPostCategoryIfTrendingOrControversial,
    MAX(tcp.ControversyReason) AS TopPostControversyReason
FROM
    UserEngagementSummary u
LEFT JOIN
    UserPostMetrics upm ON u.UserId = upm.OwnerUserId
LEFT JOIN
    -- Join with PostTagAnalysis to get tags for the user's top post
    PostTagAnalysis pta_top ON upm.PostId = pta_top.PostId AND upm.UserPostScoreRank = 1 AND upm.PostTypeId = 1
LEFT JOIN
    PopularTagsWithStats pts ON pta_top.ExtractedTag = pts.TagName
LEFT JOIN
    PostCommentSentiment pcs ON upm.PostId = pcs.PostId
LEFT JOIN
    TrendingControversialPosts tcp ON upm.PostId = tcp.PostId AND upm.UserPostScoreRank = 1
GROUP BY
    u.UserId, u.DisplayName, u.Reputation, u.UserCreationDate, u.LastAccessDate, u.WebsiteUrl, u.Location,
    u.GoldBadges, u.SilverBadges, u.BronzeBadges, u.TotalUpvotesReceived, u.TotalDownvotesReceived
HAVING
    u.Reputation > 200 AND COALESCE(SUM(upm.Score), 0) > 50 -- Filter for more impactful users
ORDER BY
    u.Reputation DESC, TotalScoreFromOwnedPosts DESC, TotalQuestionsByOwner DESC
LIMIT 1000;
