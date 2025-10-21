-- {"query": "55013.sql", "dataset": "stackoverflow", "version": "v1.1", "prompt": "p2", "model": "gpt-oss-120b", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2048, "output_tokens": 1308} 
WITH 
-- 1. Recent activity per user (last 90 days)
user_recent_activity AS (
    SELECT 
        u.Id AS UserId,
        MAX(p.CreationDate) AS LastPostDate,
        MAX(c.CreationDate) AS LastCommentDate,
        GREATEST(
            COALESCE(MAX(p.CreationDate), '1970-01-01'), 
            COALESCE(MAX(c.CreationDate), '1970-01-01')
        ) AS LastActivityDate
    FROM Users u
    LEFT JOIN Posts p ON p.OwnerUserId = u.Id AND p.CreationDate >= cast('2024-10-01 12:34:56' as timestamp) - interval '90 days'
    LEFT JOIN Comments c ON c.UserId = u.Id AND c.CreationDate >= cast('2024-10-01 12:34:56' as timestamp) - interval '90 days'
    GROUP BY u.Id
),

-- 2. Aggregate badge counts per user, split by class
user_badge_counts AS (
    SELECT 
        b.UserId,
        COUNT(*) FILTER (WHERE b.Class = 1) AS GoldBadges,
        COUNT(*) FILTER (WHERE b.Class = 2) AS SilverBadges,
        COUNT(*) FILTER (WHERE b.Class = 3) AS BronzeBadges,
        COUNT(*) AS TotalBadges
    FROM Badges b
    GROUP BY b.UserId
),

-- 3. Compute post statistics per user (questions vs answers)
user_post_stats AS (
    SELECT 
        p.OwnerUserId AS UserId,
        COUNT(*) FILTER (WHERE p.PostTypeId = 1) AS QuestionCount,
        COUNT(*) FILTER (WHERE p.PostTypeId = 2) AS AnswerCount,
        COALESCE(SUM(p.Score),0) AS TotalScore,
        AVG(p.Score) FILTER (WHERE p.PostTypeId = 1) AS AvgQuestionScore,
        AVG(p.Score) FILTER (WHERE p.PostTypeId = 2) AS AvgAnswerScore,
        COALESCE(SUM(p.ViewCount),0) AS TotalViews
    FROM Posts p
    WHERE p.OwnerUserId IS NOT NULL
    GROUP BY p.OwnerUserId
),

-- 4. Top tags a user has participated in (via questions and answers)
user_top_tags AS (
    SELECT 
        p.OwnerUserId AS UserId,
        unnest(string_to_array(substr(p.Tags, 2, length(p.Tags)-2), '><')) AS Tag,
        COUNT(*) AS TagUsage
    FROM Posts p
    WHERE p.PostTypeId IN (1,2) AND p.Tags IS NOT NULL
    GROUP BY p.OwnerUserId, Tag
),

-- 5. Rank top 5 tags per user
user_tag_rankings AS (
    SELECT 
        UserId,
        Tag,
        TagUsage,
        ROW_NUMBER() OVER (PARTITION BY UserId ORDER BY TagUsage DESC) AS TagRank
    FROM user_top_tags
),

-- 6. Compile comprehensive user profile
user_profile AS (
    SELECT 
        u.Id AS UserId,
        u.DisplayName,
        u.Reputation,
        u.CreationDate,
        COALESCE(ura.LastActivityDate, u.CreationDate) AS LastActivityDate,
        COALESCE(upc.QuestionCount,0) AS QuestionCount,
        COALESCE(upc.AnswerCount,0) AS AnswerCount,
        COALESCE(upc.TotalScore,0) AS TotalScore,
        COALESCE(upc.AvgQuestionScore,0) AS AvgQuestionScore,
        COALESCE(upc.AvgAnswerScore,0) AS AvgAnswerScore,
        COALESCE(upc.TotalViews,0) AS TotalViews,
        COALESCE(ubc.GoldBadges,0) AS GoldBadges,
        COALESCE(ubc.SilverBadges,0) AS SilverBadges,
        COALESCE(ubc.BronzeBadges,0) AS BronzeBadges,
        COALESCE(ubc.TotalBadges,0) AS TotalBadges
    FROM Users u
    LEFT JOIN user_recent_activity ura ON ura.UserId = u.Id
    LEFT JOIN user_post_stats upc ON upc.UserId = u.Id
    LEFT JOIN user_badge_counts ubc ON ubc.UserId = u.Id
)

SELECT 
    up.UserId,
    up.DisplayName,
    up.Reputation,
    up.QuestionCount,
    up.AnswerCount,
    up.TotalScore,
    up.AvgQuestionScore,
    up.AvgAnswerScore,
    up.TotalViews,
    up.GoldBadges,
    up.SilverBadges,
    up.BronzeBadges,
    up.TotalBadges,
    up.LastActivityDate,
    -- Concatenate top 5 tags into a single column
    STRING_AGG(
        CASE WHEN utr.TagRank <= 5 THEN utr.Tag || ':' || utr.TagUsage::text END,
        ', '
        ORDER BY utr.TagRank
    ) AS TopTags
FROM user_profile up
LEFT JOIN user_tag_rankings utr ON utr.UserId = up.UserId
WHERE up.Reputation > 1000
GROUP BY 
    up.UserId, up.DisplayName, up.Reputation, up.QuestionCount, up.AnswerCount,
    up.TotalScore, up.AvgQuestionScore, up.AvgAnswerScore, up.TotalViews,
    up.GoldBadges, up.SilverBadges, up.BronzeBadges, up.TotalBadges, up.LastActivityDate
ORDER BY up.TotalScore DESC
LIMIT 100;