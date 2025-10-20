WITH RECURSIVE user_stats AS (
    SELECT 
        u.Id AS UserId,
        u.DisplayName,
        u.Reputation,
        COUNT(DISTINCT p.Id) AS TotalPosts,
        COALESCE(SUM(p.Score), 0) AS TotalPostScore,
        COUNT(DISTINCT c.Id) AS TotalComments,
        AVG(p.Score) AS AvgPostScore,
        COUNT(DISTINCT CASE WHEN v.VoteTypeId = 2 THEN v.Id END) AS TotalUpvotesReceived
    FROM Users u
    LEFT JOIN Posts p ON u.Id = p.OwnerUserId
    LEFT JOIN Comments c ON p.Id = c.PostId
    LEFT JOIN Votes v ON p.Id = v.PostId
    GROUP BY u.Id, u.DisplayName, u.Reputation
),
badge_stats AS (
    SELECT 
        b.UserId,
        COUNT(*) AS TotalBadges,
        COUNT(CASE WHEN b.Class = 1 THEN 1 END) AS GoldBadges,
        COUNT(CASE WHEN b.Class = 2 THEN 1 END) AS SilverBadges,
        COUNT(CASE WHEN b.Class = 3 THEN 1 END) AS BronzeBadges
    FROM Badges b
    GROUP BY b.UserId
),
post_tags AS (
    SELECT
        p.Id AS PostId,
        p.OwnerUserId,
        TRIM(BOTH '<>' FROM p.Tags) AS tags_str
    FROM Posts p
    WHERE p.Tags IS NOT NULL AND p.PostTypeId = 1
),
split_tags AS (
    -- anchor
    SELECT
        PostId,
        OwnerUserId,
        CASE
            WHEN tags_str = '' THEN NULL
            WHEN POSITION('><' IN tags_str) = 0 THEN tags_str
            ELSE SUBSTR(tags_str, 1, POSITION('><' IN tags_str) - 1)
        END AS tag,
        CASE
            WHEN POSITION('><' IN tags_str) = 0 THEN NULL
            ELSE SUBSTR(tags_str, POSITION('><' IN tags_str) + 2)
        END AS rest
    FROM post_tags

    UNION ALL

    -- recursive
    SELECT
        PostId,
        OwnerUserId,
        CASE
            WHEN rest = '' THEN NULL
            WHEN POSITION('><' IN rest) = 0 THEN rest
            ELSE SUBSTR(rest, 1, POSITION('><' IN rest) - 1)
        END AS tag,
        CASE
            WHEN POSITION('><' IN rest) = 0 THEN NULL
            ELSE SUBSTR(rest, POSITION('><' IN rest) + 2)
        END AS rest
    FROM split_tags
    WHERE rest IS NOT NULL
),
tag_usage AS (
    SELECT
        st.OwnerUserId,
        st.tag AS TagName,
        COUNT(*) AS TagPosts,
        AVG(p.Score) AS AvgTagScore
    FROM split_tags st
    JOIN Posts p ON p.Id = st.PostId
    WHERE st.tag IS NOT NULL
    GROUP BY st.OwnerUserId, st.tag
)
SELECT 
    us.UserId,
    us.DisplayName,
    us.Reputation,
    us.TotalPosts,
    us.TotalPostScore,
    us.TotalComments,
    ROUND(us.AvgPostScore, 2) AS AvgPostScore,
    us.TotalUpvotesReceived,
    COALESCE(bs.TotalBadges, 0) AS TotalBadges,
    COALESCE(bs.GoldBadges, 0) AS GoldBadges,
    COALESCE(bs.SilverBadges, 0) AS SilverBadges,
    COALESCE(bs.BronzeBadges, 0) AS BronzeBadges,
    STRING_AGG(DISTINCT (tu.TagName || ': ' || tu.TagPosts || ' posts, avg score ' || ROUND(tu.AvgTagScore, 2)), '; ') AS TopTags,
    ROW_NUMBER() OVER (ORDER BY us.Reputation DESC, us.TotalUpvotesReceived DESC) AS Rank
FROM user_stats us
LEFT JOIN badge_stats bs ON us.UserId = bs.UserId
LEFT JOIN tag_usage tu ON us.UserId = tu.OwnerUserId
WHERE us.TotalPosts > 0
GROUP BY us.UserId, us.DisplayName, us.Reputation, us.TotalPosts, us.TotalPostScore, us.TotalComments, us.AvgPostScore, us.TotalUpvotesReceived, bs.TotalBadges, bs.GoldBadges, bs.SilverBadges, bs.BronzeBadges
ORDER BY Rank
LIMIT 100;