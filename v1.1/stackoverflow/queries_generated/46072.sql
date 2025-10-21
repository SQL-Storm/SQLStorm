-- {"query": "46072.sql", "dataset": "stackoverflow", "version": "v1.1", "prompt": "p2", "model": "claude-4.5-sonnet", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2294, "output_tokens": 2095}

WITH RECURSIVE UserEngagementMetrics AS (
    SELECT 
        u.Id as UserId,
        u.DisplayName,
        u.Reputation,
        u.CreationDate as UserCreationDate,
        COUNT(DISTINCT p.Id) as TotalPosts,
        COUNT(DISTINCT CASE WHEN p.PostTypeId = 1 THEN p.Id END) as QuestionCount,
        COUNT(DISTINCT CASE WHEN p.PostTypeId = 2 THEN p.Id END) as AnswerCount,
        COALESCE(AVG(p.Score), 0) as AvgPostScore,
        COALESCE(SUM(p.ViewCount), 0) as TotalViews
    FROM Users u
    LEFT JOIN Posts p ON u.Id = p.OwnerUserId
    WHERE u.CreationDate >= CURRENT_DATE - INTERVAL '5 years'
    GROUP BY u.Id, u.DisplayName, u.Reputation, u.CreationDate
),
TagExpertise AS (
    SELECT 
        p.OwnerUserId,
        string_to_array(substring(p.Tags, 2, length(p.Tags)-2), '><') as tag_array,
        COUNT(*) as tag_post_count,
        AVG(p.Score) as avg_tag_score
    FROM Posts p
    WHERE p.PostTypeId = 1 
        AND p.Tags IS NOT NULL
        AND p.OwnerUserId IS NOT NULL
    GROUP BY p.OwnerUserId, p.Tags
),
TopTagsPerUser AS (
    SELECT 
        te.OwnerUserId,
        unnest(te.tag_array) as TagName,
        SUM(te.tag_post_count) as PostsInTag,
        AVG(te.avg_tag_score) as AvgScoreInTag,
        ROW_NUMBER() OVER (PARTITION BY te.OwnerUserId ORDER BY SUM(te.tag_post_count) DESC) as tag_rank
    FROM TagExpertise te
    GROUP BY te.OwnerUserId, unnest(te.tag_array)
),
BadgeStats AS (
    SELECT 
        b.UserId,
        COUNT(*) as TotalBadges,
        COUNT(CASE WHEN b.Class = 1 THEN 1 END) as GoldBadges,
        COUNT(CASE WHEN b.Class = 2 THEN 1 END) as SilverBadges,
        COUNT(CASE WHEN b.Class = 3 THEN 1 END) as BronzeBadges
    FROM Badges b
    GROUP BY b.UserId
),
AnswerAcceptanceMetrics AS (
    SELECT 
        ans.OwnerUserId,
        COUNT(*) as TotalAnswers,
        COUNT(CASE WHEN q.AcceptedAnswerId = ans.Id THEN 1 END) as AcceptedAnswers,
        CASE 
            WHEN COUNT(*) > 0 THEN 
                ROUND(100.0 * COUNT(CASE WHEN q.AcceptedAnswerId = ans.Id THEN 1 END) / COUNT(*), 2)
            ELSE 0 
        END as AcceptanceRate
    FROM Posts ans
    JOIN Posts q ON ans.ParentId = q.Id
    WHERE ans.PostTypeId = 2 AND q.PostTypeId = 1
    GROUP BY ans.OwnerUserId
),
VotingBehavior AS (
    SELECT 
        v.UserId,
        COUNT(*) as TotalVotes,
        COUNT(CASE WHEN v.VoteTypeId = 2 THEN 1 END) as UpvotesGiven,
        COUNT(CASE WHEN v.VoteTypeId = 3 THEN 1 END) as DownvotesGiven,
        COUNT(CASE WHEN v.VoteTypeId = 5 THEN 1 END) as FavoritesGiven
    FROM Votes v
    WHERE v.UserId IS NOT NULL
        AND v.VoteTypeId IN (2, 3, 5)
    GROUP BY v.UserId
),
CommentActivity AS (
    SELECT 
        c.UserId,
        COUNT(*) as TotalComments,
        AVG(c.Score) as AvgCommentScore,
        COUNT(DISTINCT c.PostId) as UniquePostsCommented
    FROM Comments c
    WHERE c.UserId IS NOT NULL
    GROUP BY c.UserId
)
SELECT 
    uem.UserId,
    uem.DisplayName,
    uem.Reputation,
    EXTRACT(YEAR FROM AGE(CURRENT_DATE, uem.UserCreationDate)) as YearsActive,
    uem.QuestionCount,
    uem.AnswerCount,
    uem.TotalPosts,
    ROUND(uem.AvgPostScore::numeric, 2) as AvgPostScore,
    uem.TotalViews,
    COALESCE(bs.TotalBadges, 0) as TotalBadges,
    COALESCE(bs.GoldBadges, 0) as GoldBadges,
    COALESCE(bs.SilverBadges, 0) as SilverBadges,
    COALESCE(bs.BronzeBadges, 0) as BronzeBadges,
    COALESCE(aam.AcceptanceRate, 0) as AnswerAcceptanceRate,
    COALESCE(aam.AcceptedAnswers, 0) as AcceptedAnswers,
    COALESCE(vb.UpvotesGiven, 0) as UpvotesGiven,
    COALESCE(vb.DownvotesGiven, 0) as DownvotesGiven,
    COALESCE(ca.TotalComments, 0) as TotalComments,
    COALESCE(ca.AvgCommentScore, 0) as AvgCommentScore,
    STRING_AGG(DISTINCT ttp.TagName || ':' || ttp.PostsInTag::text, ', ' ORDER BY ttp.TagName || ':' || ttp.PostsInTag::text) 
        FILTER (WHERE ttp.tag_rank <= 5) as TopFiveTags,
    CASE 
        WHEN uem.Reputation >= 10000 AND bs.GoldBadges >= 5 THEN 'Elite'
        WHEN uem.Reputation >= 5000 AND uem.TotalPosts >= 50 THEN 'Expert'
        WHEN uem.Reputation >= 1000 THEN 'Active'
        ELSE 'Beginner'
    END as UserTier,
    ROUND((uem.Reputation::numeric / NULLIF(uem.TotalPosts, 0))::numeric, 2) as ReputationPerPost
FROM UserEngagementMetrics uem
LEFT JOIN BadgeStats bs ON uem.UserId = bs.UserId
LEFT JOIN AnswerAcceptanceMetrics aam ON uem.UserId = aam.OwnerUserId
LEFT JOIN VotingBehavior vb ON uem.UserId = vb.UserId
LEFT JOIN CommentActivity ca ON uem.UserId = ca.UserId
LEFT JOIN TopTagsPerUser ttp ON uem.UserId = ttp.OwnerUserId AND ttp.tag_rank <= 5
WHERE uem.TotalPosts > 10
    AND uem.Reputation > 500
GROUP BY 
    uem.UserId, uem.DisplayName, uem.Reputation, uem.UserCreationDate,
    uem.QuestionCount, uem.AnswerCount, uem.TotalPosts, uem.AvgPostScore, uem.TotalViews,
    bs.TotalBadges, bs.GoldBadges, bs.SilverBadges, bs.BronzeBadges,
    aam.AcceptanceRate, aam.AcceptedAnswers,
    vb.UpvotesGiven, vb.DownvotesGiven,
    ca.TotalComments, ca.AvgCommentScore
ORDER BY uem.Reputation DESC, uem.TotalPosts DESC
LIMIT 1000;
