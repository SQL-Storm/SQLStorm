WITH user_post_stats AS (
    SELECT 
        p.OwnerUserId AS UserId,
        COUNT(p.Id) AS TotalPosts,
        SUM(CASE WHEN p.PostTypeId = 1 THEN 1 ELSE 0 END) AS QuestionCount,
        AVG(CASE WHEN p.Score IS NOT NULL THEN p.Score ELSE 0 END) AS AvgScore,
        SUM(CASE WHEN p.ClosedDate IS NOT NULL THEN 1 ELSE 0 END) AS ClosedPosts,
        SUM(CASE WHEN p.AcceptedAnswerId IS NOT NULL THEN 1 ELSE 0 END) AS AcceptedQuestions,
        STRING_AGG(DISTINCT tag, ', ') AS AllTags
    FROM Posts p
    CROSS JOIN LATERAL (
        SELECT tag
        FROM (
            SELECT UNNEST(
                CASE
                    WHEN p.Tags IS NULL OR p.Tags = '' THEN ARRAY[]::text[]
                    ELSE regexp_split_to_array(substring(p.Tags FROM 2 FOR char_length(p.Tags) - 2), '><')
                END
            ) AS tag
        ) s
    ) t
    WHERE p.OwnerUserId IS NOT NULL
    GROUP BY p.OwnerUserId
),
user_vote_stats AS (
    SELECT 
        v.UserId,
        COUNT(v.Id) AS TotalVotes,
        SUM(CASE WHEN vt.Name = 'UpMod' THEN 1 WHEN vt.Name = 'DownMod' THEN -1 ELSE 0 END) AS NetVotes,
        AVG(EXTRACT(EPOCH FROM (v.CreationDate - u.CreationDate))/3600) AS AvgHoursSinceSignup
    FROM Votes v
    JOIN VoteTypes vt ON v.VoteTypeId = vt.Id
    JOIN Users u ON v.UserId = u.Id
    WHERE v.UserId IS NOT NULL
    GROUP BY v.UserId
),
user_comment_stats AS (
    SELECT 
        c.UserId,
        COUNT(c.Id) AS CommentCount,
        SUM(c.Score) AS TotalCommentScore,
        MAX(c.CreationDate) AS LatestCommentDate
    FROM Comments c
    WHERE c.UserId IS NOT NULL
    GROUP BY c.UserId
),
badge_summary AS (
    SELECT 
        b.UserId,
        COUNT(CASE WHEN b.Class = 1 THEN 1 END) AS GoldBadges,
        COUNT(CASE WHEN b.Class = 2 THEN 1 END) AS SilverBadges,
        COUNT(CASE WHEN b.Class = 3 THEN 1 END) AS BronzeBadges,
        COUNT(CASE WHEN b.TagBased = true THEN 1 END) AS TagBasedBadges,
        STRING_AGG(b.Name, '; ') AS BadgeNames
    FROM Badges b
    GROUP BY b.UserId
),
ranked_users AS (
    SELECT 
        u.Id,
        u.DisplayName,
        u.Reputation,
        COALESCE(ups.TotalPosts, 0) AS TotalPosts,
        COALESCE(uvs.NetVotes, 0) AS NetVotes,
        COALESCE(ucs.CommentCount, 0) AS CommentCount,
        COALESCE(bs.GoldBadges, 0) AS GoldBadges,
        COALESCE(bs.SilverBadges, 0) AS SilverBadges,
        COALESCE(bs.BronzeBadges, 0) AS BronzeBadges,
        COALESCE(ups.AvgScore, 0) AS AvgPostScore,
        RANK() OVER (ORDER BY u.Reputation DESC, COALESCE(ups.TotalPosts, 0) DESC) AS ReputationRank,
        DENSE_RANK() OVER (PARTITION BY LEFT(COALESCE(u.Location, 'Unknown'), 10) ORDER BY COALESCE(uvs.NetVotes, 0) DESC) AS LocationNetVoteRank,
        CASE 
            WHEN u.AboutMe IS NULL OR TRIM(u.AboutMe) = '' THEN 'No Bio'
            WHEN POSITION('stackoverflow' IN LOWER(u.AboutMe)) > 0 THEN 'SO Mentioned'
            ELSE 'Other'
        END AS BioCategory,
        COALESCE(ups.AllTags, '') AS AggregatedTags,
        CASE 
            WHEN COALESCE(ups.ClosedPosts,0) > 0 AND COALESCE(ups.AcceptedQuestions,0) = 0 THEN 'Many Closed, No Accepted'
            WHEN COALESCE(ups.QuestionCount,0) = 0 THEN 'No Questions'
            ELSE 'Active'
        END AS PostStatus,
        ROW_NUMBER() OVER (PARTITION BY EXTRACT(YEAR FROM u.CreationDate) ORDER BY u.Reputation DESC) AS YearReputationRank
    FROM Users u
    LEFT JOIN user_post_stats ups ON u.Id = ups.UserId
    LEFT JOIN user_vote_stats uvs ON u.Id = uvs.UserId
    LEFT JOIN user_comment_stats ucs ON u.Id = ucs.UserId
    LEFT JOIN badge_summary bs ON u.Id = bs.UserId
    WHERE u.Reputation > 1000
      AND (COALESCE(ups.TotalPosts, 0) > 0 OR COALESCE(uvs.TotalVotes, 0) > 0 OR COALESCE(ucs.CommentCount, 0) > 0)
),
high_engagement_users AS (
    SELECT ru.Id,
           ru.DisplayName,
           ru.Reputation,
           ru.TotalPosts,
           ru.NetVotes,
           ru.CommentCount,
           ROUND((ru.TotalPosts + ru.NetVotes / 10.0 + ru.CommentCount) / NULLIF(ru.Reputation / 100.0, 0), 2) AS EngagementRatio,
           ru.BioCategory,
           ru.PostStatus,
           ru.ReputationRank,
           ru.LocationNetVoteRank,
           ru.YearReputationRank,
           ru.AggregatedTags,
           ru.GoldBadges,
           ru.SilverBadges,
           ru.BronzeBadges
    FROM ranked_users ru
    WHERE ru.TotalPosts > 10
       OR EXISTS (SELECT 1 FROM Badges b WHERE b.UserId = ru.Id AND b.TagBased = true)
       OR ru.DisplayName LIKE '%San Francisco%'
),
low_engagement_users AS (
    SELECT ru.Id,
           ru.DisplayName,
           ru.Reputation,
           ru.TotalPosts,
           ru.NetVotes,
           ru.CommentCount,
           ROUND((ru.TotalPosts + ru.NetVotes / 10.0 + ru.CommentCount) / NULLIF(ru.Reputation / 100.0, 0), 2) AS EngagementRatio,
           ru.BioCategory,
           ru.PostStatus,
           ru.ReputationRank,
           ru.LocationNetVoteRank,
           ru.YearReputationRank,
           ru.AggregatedTags,
           ru.GoldBadges,
           ru.SilverBadges,
           ru.BronzeBadges
    FROM ranked_users ru
    WHERE ru.TotalPosts <= 5
       AND NOT EXISTS (SELECT 1 FROM Badges b WHERE b.UserId = ru.Id AND b.Class <= 2)
)
SELECT 
    'High Engagement' AS Category,
    heu.Id,
    heu.DisplayName,
    heu.Reputation,
    heu.TotalPosts,
    heu.NetVotes,
    heu.CommentCount,
    heu.EngagementRatio,
    heu.BioCategory,
    heu.PostStatus,
    heu.ReputationRank,
    heu.LocationNetVoteRank,
    heu.YearReputationRank,
    SUBSTRING(heu.AggregatedTags FROM 1 FOR 200) AS TopTags,
    heu.GoldBadges,
    heu.SilverBadges,
    heu.BronzeBadges
FROM high_engagement_users heu

UNION ALL

SELECT 
    'Low Engagement' AS Category,
    leu.Id,
    leu.DisplayName,
    leu.Reputation,
    leu.TotalPosts,
    leu.NetVotes,
    leu.CommentCount,
    leu.EngagementRatio,
    leu.BioCategory,
    leu.PostStatus,
    leu.ReputationRank,
    leu.LocationNetVoteRank,
    leu.YearReputationRank,
    SUBSTRING(leu.AggregatedTags FROM 1 FOR 200) AS TopTags,
    leu.GoldBadges,
    leu.SilverBadges,
    leu.BronzeBadges
FROM low_engagement_users leu

ORDER BY Reputation DESC, EngagementRatio DESC, DisplayName;