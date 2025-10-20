-- {"query": "49026.sql", "dataset": "stackoverflow", "version": "v1.1", "prompt": "p2", "model": "gemini-2.5-flash", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2074, "output_tokens": 2235} 
WITH PopularTags AS (
    -- Identify the top N most popular tags by post count
    SELECT TagName
    FROM Tags
    ORDER BY Count DESC
    LIMIT 50 -- Consider the top 50 most popular tags
),
UserPostAggregates AS (
    -- Aggregates for each user's posts (questions and answers), including their own edits
    SELECT
        p.OwnerUserId AS UserId,
        COUNT(CASE WHEN p.PostTypeId = 1 THEN 1 END) AS QuestionCount,
        COUNT(CASE WHEN p.PostTypeId = 2 THEN 1 END) AS AnswerCount,
        SUM(p.Score) AS TotalPostScore,
        SUM(CASE WHEN p.PostTypeId = 1 THEN p.ViewCount ELSE 0 END) AS TotalQuestionViews,
        COUNT(DISTINCT CASE WHEN ph.PostHistoryTypeId IN (4, 5, 6, 24) AND ph.UserId = p.OwnerUserId THEN ph.PostId END) AS SelfEditedPostsCount -- Edits + Suggested Edit Applied by the post owner
    FROM Posts p
    LEFT JOIN PostHistory ph ON p.Id = ph.PostId
    WHERE p.OwnerUserId IS NOT NULL
    GROUP BY p.OwnerUserId
),
UserCommentAggregates AS (
    -- Aggregates for user comments
    SELECT
        c.UserId,
        COUNT(c.Id) AS CommentCount,
        SUM(c.Score) AS TotalCommentScore
    FROM Comments c
    WHERE c.UserId IS NOT NULL
    GROUP BY c.UserId
),
UserBadgeAggregates AS (
    -- Aggregates for user badges, counting different classes
    SELECT
        b.UserId,
        COUNT(b.Id) AS TotalBadges,
        COUNT(CASE WHEN b.Class = 1 THEN 1 END) AS GoldBadges,
        COUNT(CASE WHEN b.Class = 2 THEN 1 END) AS SilverBadges,
        COUNT(CASE WHEN b.Class = 3 THEN 1 END) AS BronzeBadges
    FROM Badges b
    GROUP BY b.UserId
),
PostVoteAggregates AS (
    -- Total upvotes and downvotes received by each user's posts
    SELECT
        p.OwnerUserId AS UserId,
        SUM(CASE WHEN v.VoteTypeId = 2 THEN 1 ELSE 0 END) AS TotalUpvotesReceived,
        SUM(CASE WHEN v.VoteTypeId = 3 THEN 1 ELSE 0 END) AS TotalDownvotesReceived
    FROM Posts p
    JOIN Votes v ON p.Id = v.PostId
    WHERE p.OwnerUserId IS NOT NULL
    GROUP BY p.OwnerUserId
),
UserPopularTagQuestions AS (
    -- Counts distinct popular tags associated with a user's questions
    SELECT
        p.OwnerUserId AS UserId,
        COUNT(DISTINCT pt.TagName) AS PopularTagQuestionsCount
    FROM Posts p
    JOIN LATERAL UNNEST(STRING_TO_ARRAY(SUBSTRING(p.Tags, 2, LENGTH(p.Tags) - 2), '><')) AS tag_name ON TRUE
    JOIN PopularTags pt ON tag_name = pt.TagName
    WHERE p.PostTypeId = 1 AND p.OwnerUserId IS NOT NULL AND p.Tags IS NOT NULL
    GROUP BY p.OwnerUserId
),
UserPerformanceData AS (
    -- Intermediate CTE to consolidate all user performance metrics
    SELECT
        u.Id AS UserId,
        u.DisplayName,
        u.Reputation,
        u.CreationDate,
        u.LastAccessDate,
        COALESCE(upa.QuestionCount, 0) AS QuestionCount,
        COALESCE(upa.AnswerCount, 0) AS AnswerCount,
        COALESCE(upa.TotalPostScore, 0) AS TotalPostScore,
        COALESCE(upa.TotalQuestionViews, 0) AS TotalQuestionViews,
        COALESCE(uca.CommentCount, 0) AS CommentCount,
        COALESCE(uca.TotalCommentScore, 0) AS TotalCommentScore,
        COALESCE(uba.GoldBadges, 0) AS GoldBadges,
        COALESCE(uba.SilverBadges, 0) AS SilverBadges,
        COALESCE(uba.BronzeBadges, 0) AS BronzeBadges,
        COALESCE(upa.SelfEditedPostsCount, 0) AS SelfEditedPostsCount,
        COALESCE(pva.TotalUpvotesReceived, 0) AS TotalUpvotesReceived,
        COALESCE(pva.TotalDownvotesReceived, 0) AS TotalDownvotesReceived,
        COALESCE(uptq.PopularTagQuestionsCount, 0) AS PopularTagQuestionsCount
    FROM Users u
    LEFT JOIN UserPostAggregates upa ON u.Id = upa.UserId
    LEFT JOIN UserCommentAggregates uca ON u.Id = uca.UserId
    LEFT JOIN UserBadgeAggregates uba ON u.Id = uba.UserId
    LEFT JOIN PostVoteAggregates pva ON u.Id = pva.UserId
    LEFT JOIN UserPopularTagQuestions uptq ON u.Id = uptq.UserId
    WHERE
        u.Reputation > 2500 -- Minimum reputation for consideration
        AND u.LastAccessDate >= cast('2024-10-01 12:34:56' as timestamp) - INTERVAL '1.5 year' -- Active in the last 18 months
        AND COALESCE(upa.QuestionCount, 0) >= 5 -- Must have asked at least 5 questions
        AND COALESCE(upa.AnswerCount, 0) >= 15 -- Must have provided at least 15 answers
        AND COALESCE(uba.GoldBadges, 0) >= 1 -- Must have at least one gold badge
        AND COALESCE(uba.SilverBadges, 0) >= 2 -- Must have at least two silver badges
        AND COALESCE(upa.SelfEditedPostsCount, 0) >= 10 -- Must have edited their own posts or applied suggested edits to them at least 10 times
        AND COALESCE(uca.CommentCount, 0) >= 20 -- Must have made at least 20 comments
        AND COALESCE(uptq.PopularTagQuestionsCount, 0) >= 3 -- Must have asked questions in at least 3 popular tags
)
-- Final selection, score calculation, and ranking
SELECT
    upd.UserId,
    upd.DisplayName,
    upd.Reputation,
    upd.QuestionCount,
    upd.AnswerCount,
    upd.TotalPostScore,
    upd.CommentCount,
    upd.GoldBadges,
    upd.SilverBadges,
    upd.SelfEditedPostsCount,
    upd.TotalUpvotesReceived,
    upd.TotalDownvotesReceived,
    upd.PopularTagQuestionsCount,
    -- Calculate a comprehensive InfluenceScore based on weighted metrics
    (upd.Reputation * 0.05) + -- Reputation is a foundational factor
    (upd.TotalPostScore * 0.2) + -- Score on posts (questions/answers) reflects quality
    (upd.QuestionCount * 0.5) + -- Contribution via asking questions
    (upd.AnswerCount * 0.7) + -- Contribution via providing answers (valued higher for expertise)
    (upd.CommentCount * 0.1) + -- Engagement via comments
    (upd.GoldBadges * 10.0) + -- High value for gold badges, indicating significant achievement
    (upd.SilverBadges * 5.0) + -- Moderate value for silver badges
    (upd.SelfEditedPostsCount * 0.2) + -- Community improvement via self-edits/applications
    (upd.PopularTagQuestionsCount * 1.5) + -- Engagement in prominent topics
    (upd.TotalUpvotesReceived * 0.05) - -- Positive feedback on posts
    (upd.TotalDownvotesReceived * 0.02) + -- Penalty for negative feedback
    (CASE WHEN upd.TotalQuestionViews > 100000 THEN 5 ELSE 0 END) + -- Bonus for highly viewed questions
    (CASE WHEN upd.TotalCommentScore > 50 THEN 1 ELSE 0 END) -- Bonus for highly rated comments
    AS InfluenceScore,
    RANK() OVER (ORDER BY
        (upd.Reputation * 0.05) +
        (upd.TotalPostScore * 0.2) +
        (upd.QuestionCount * 0.5) +
        (upd.AnswerCount * 0.7) +
        (upd.CommentCount * 0.1) +
        (upd.GoldBadges * 10.0) +
        (upd.SilverBadges * 5.0) +
        (upd.SelfEditedPostsCount * 0.2) +
        (upd.PopularTagQuestionsCount * 1.5) +
        (upd.TotalUpvotesReceived * 0.05) -
        (upd.TotalDownvotesReceived * 0.02) +
        (CASE WHEN upd.TotalQuestionViews > 100000 THEN 5 ELSE 0 END) +
        (CASE WHEN upd.TotalCommentScore > 50 THEN 1 ELSE 0 END)
    DESC, upd.Reputation DESC, upd.CreationDate ASC) AS GlobalRank,
    NTILE(5) OVER (ORDER BY upd.Reputation DESC, upd.TotalPostScore DESC) AS ReputationQuintile,
    (EXTRACT(YEAR FROM cast('2024-10-01 12:34:56' as timestamp)) - EXTRACT(YEAR FROM upd.CreationDate)) AS YearsOnPlatform
FROM UserPerformanceData upd
ORDER BY InfluenceScore DESC, upd.Reputation DESC
LIMIT 100;