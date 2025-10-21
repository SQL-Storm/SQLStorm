-- {"query": "49078.sql", "dataset": "stackoverflow", "version": "v1.1", "prompt": "p2", "model": "gemini-2.5-flash", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2074, "output_tokens": 2145} 
WITH RelevantPosts AS (
    -- Select posts (questions or answers) created within the last 3 years
    -- and extract tags into an array for efficient filtering.
    SELECT
        p.Id AS PostId,
        p.PostTypeId,
        p.OwnerUserId,
        p.CreationDate,
        p.Score,
        p.ViewCount,
        p.AnswerCount,        -- Only relevant for PostTypeId = 1 (Questions)
        p.CommentCount,
        p.FavoriteCount,
        string_to_array(substring(p.Tags, 2, length(p.Tags)-2), '><') AS TagArray
    FROM
        Posts p
    WHERE
        p.PostTypeId IN (1, 2) -- 1 = Question, 2 = Answer
        AND p.CreationDate >= (cast('2024-10-01 12:34:56' as timestamp) - INTERVAL '3 years')
        AND p.OwnerUserId IS NOT NULL -- Exclude community-owned or deleted user posts for this analysis
        AND p.Tags IS NOT NULL
),
FilteredRelevantPosts AS (
    -- Filter relevant posts by specific programming language tags,
    -- focusing on 'python', 'javascript', or 'sql'.
    SELECT
        rp.PostId,
        rp.PostTypeId,
        rp.OwnerUserId,
        rp.CreationDate,
        rp.Score,
        rp.ViewCount,
        rp.AnswerCount,
        rp.CommentCount,
        rp.FavoriteCount
    FROM
        RelevantPosts rp
    WHERE
        'python' = ANY(rp.TagArray) OR 'javascript' = ANY(rp.TagArray) OR 'sql' = ANY(rp.TagArray)
),
PostVoteAndEditMetrics AS (
    -- Aggregate vote and edit history metrics for each filtered post.
    -- Counts distinct upvotes, accepted answer votes, and significant post edits.
    SELECT
        frp.PostId,
        frp.PostTypeId,
        frp.OwnerUserId,
        frp.CreationDate,
        frp.Score,
        frp.ViewCount,
        frp.AnswerCount,
        frp.CommentCount,
        frp.FavoriteCount,
        COUNT(DISTINCT v_up.Id) FILTER (WHERE v_up.VoteTypeId = 2) AS UpvoteCount, -- 2 = UpMod
        COUNT(DISTINCT v_acc.Id) FILTER (WHERE v_acc.VoteTypeId = 1) AS AcceptedAnswerVoteCount, -- 1 = AcceptedByOriginator
        COUNT(DISTINCT ph_edit.Id) FILTER (WHERE ph_edit.PostHistoryTypeId IN (4, 5, 6, 8, 9)) AS EditHistoryCount -- 4=Edit Title, 5=Edit Body, 6=Edit Tags, 8=Rollback Body, 9=Rollback Tags
    FROM
        FilteredRelevantPosts frp
    LEFT JOIN Votes v_up ON frp.PostId = v_up.PostId AND v_up.VoteTypeId = 2
    LEFT JOIN Votes v_acc ON frp.PostId = v_acc.PostId AND v_acc.VoteTypeId = 1
    LEFT JOIN PostHistory ph_edit ON frp.PostId = ph_edit.PostId
    GROUP BY
        frp.PostId, frp.PostTypeId, frp.OwnerUserId, frp.CreationDate, frp.Score, frp.ViewCount, frp.AnswerCount, frp.CommentCount, frp.FavoriteCount
),
UserActivitySummary AS (
    -- Summarize user contributions based on the post metrics, reputation, and activity.
    -- Calculate total scores, views, answers, comments, upvotes, accepted answers, and edits.
    -- Also calculates average scores for questions and answers.
    SELECT
        u.Id AS UserId,
        u.DisplayName,
        u.Reputation,
        u.UpVotes AS UserUpvoteCount, -- Total upvotes user has given
        u.DownVotes AS UserDownvoteCount, -- Total downvotes user has given
        COUNT(DISTINCT pved.PostId) AS TotalPostsContributed,
        SUM(pved.Score) AS TotalScoreReceived,
        SUM(pved.ViewCount) AS TotalViewsOnPosts,
        SUM(pved.AnswerCount) AS TotalAnswersToQuestions,
        SUM(pved.CommentCount) AS TotalCommentsReceived,
        SUM(pved.FavoriteCount) AS TotalFavoritesReceived,
        SUM(pved.UpvoteCount) AS TotalUpvotesAcrossPosts,
        SUM(pved.AcceptedAnswerVoteCount) AS TotalAcceptedAnswers,
        SUM(pved.EditHistoryCount) AS TotalEditsMadeByUsersPosts,
        AVG(CASE WHEN pved.PostTypeId = 1 THEN pved.Score ELSE NULL END) AS AvgQuestionScore,
        AVG(CASE WHEN pved.PostTypeId = 2 THEN pved.Score ELSE NULL END) AS AvgAnswerScore
    FROM
        Users u
    JOIN
        PostVoteAndEditMetrics pved ON u.Id = pved.OwnerUserId
    GROUP BY
        u.Id, u.DisplayName, u.Reputation, u.UpVotes, u.DownVotes
    HAVING
        COUNT(DISTINCT pved.PostId) >= 5 -- Minimum posts in the filtered set
        AND u.Reputation >= 500 -- Minimum overall reputation
),
UserBadgeSummary AS (
    -- Count the number of Gold, Silver, and Bronze badges for each user.
    SELECT
        b.UserId,
        COUNT(CASE WHEN b.Class = 1 THEN 1 ELSE NULL END) AS GoldBadges,
        COUNT(CASE WHEN b.Class = 2 THEN 1 ELSE NULL END) AS SilverBadges,
        COUNT(CASE WHEN b.Class = 3 THEN 1 ELSE NULL END) AS BronzeBadges
    FROM
        Badges b
    GROUP BY
        b.UserId
)
-- Final selection: Calculate an 'Influence Score' for each user based on
-- their activity, reputation, and badge achievements within the relevant tag areas.
-- Rank users by this score and retrieve the top 100.
SELECT
    uas.UserId,
    uas.DisplayName,
    uas.Reputation,
    uas.TotalPostsContributed,
    uas.TotalScoreReceived,
    uas.TotalUpvotesAcrossPosts,
    uas.TotalAcceptedAnswers,
    uas.TotalEditsMadeByUsersPosts,
    COALESCE(ubs.GoldBadges, 0) AS GoldBadges,
    COALESCE(ubs.SilverBadges, 0) AS SilverBadges,
    COALESCE(ubs.BronzeBadges, 0) AS BronzeBadges,
    (
        uas.TotalUpvotesAcrossPosts * 0.75 +
        uas.TotalAcceptedAnswers * 2.0 +
        uas.TotalScoreReceived * 0.5 +
        uas.TotalViewsOnPosts * 0.001 +
        uas.TotalCommentsReceived * 0.1 +
        uas.TotalFavoritesReceived * 1.5 +
        uas.TotalEditsMadeByUsersPosts * 0.2 +
        uas.Reputation * 0.005 +
        uas.UserUpvoteCount * 0.001 + -- Consider votes given by user
        uas.UserDownvoteCount * -0.0005 + -- Slightly penalize downvotes given
        COALESCE(ubs.GoldBadges, 0) * 20.0 +
        COALESCE(ubs.SilverBadges, 0) * 10.0 +
        COALESCE(ubs.BronzeBadges, 0) * 2.0 +
        uas.TotalPostsContributed * 0.5 +
        COALESCE(uas.AvgQuestionScore, 0) * 0.5 +
        COALESCE(uas.AvgAnswerScore, 0) * 0.75
    ) AS InfluenceScore,
    RANK() OVER (ORDER BY (
        uas.TotalUpvotesAcrossPosts * 0.75 +
        uas.TotalAcceptedAnswers * 2.0 +
        uas.TotalScoreReceived * 0.5 +
        uas.TotalViewsOnPosts * 0.001 +
        uas.TotalCommentsReceived * 0.1 +
        uas.TotalFavoritesReceived * 1.5 +
        uas.TotalEditsMadeByUsersPosts * 0.2 +
        uas.Reputation * 0.005 +
        uas.UserUpvoteCount * 0.001 +
        uas.UserDownvoteCount * -0.0005 +
        COALESCE(ubs.GoldBadges, 0) * 20.0 +
        COALESCE(ubs.SilverBadges, 0) * 10.0 +
        COALESCE(ubs.BronzeBadges, 0) * 2.0 +
        uas.TotalPostsContributed * 0.5 +
        COALESCE(uas.AvgQuestionScore, 0) * 0.5 +
        COALESCE(uas.AvgAnswerScore, 0) * 0.75
    ) DESC) AS InfluenceRank
FROM
    UserActivitySummary uas
LEFT JOIN
    UserBadgeSummary ubs ON uas.UserId = ubs.UserId
ORDER BY
    InfluenceRank ASC
LIMIT 100;