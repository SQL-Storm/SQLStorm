-- {"query": "52016.sql", "dataset": "stackoverflow", "version": "v1.1", "prompt": "p2", "model": "grok-code-fast", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2165, "output_tokens": 569} 
WITH user_activity AS (
    SELECT
        u.Id AS UserId,
        u.DisplayName,
        u.Reputation,
        COUNT(DISTINCT p.Id) AS TotalPosts,
        COUNT(DISTINCT CASE WHEN p.PostTypeId = 1 THEN p.Id END) AS Questions,
        COUNT(DISTINCT CASE WHEN p.PostTypeId = 2 THEN p.Id END) AS Answers,
        COUNT(DISTINCT c.Id) AS Comments,
        COUNT(DISTINCT v.Id) AS VotesReceived,
        AVG(p.Score) AS AvgPostScore,
        SUM(b.Class) AS BadgePoints
    FROM
        Users u
    LEFT JOIN Posts p ON u.Id = p.OwnerUserId
    LEFT JOIN Comments c ON u.Id = c.UserId
    LEFT JOIN Votes v ON p.Id = v.PostId AND v.VoteTypeId IN (2, 3)
    LEFT JOIN Badges b ON u.Id = b.UserId
    GROUP BY
        u.Id, u.DisplayName, u.Reputation
),
post_stats AS (
    SELECT
        p.OwnerUserId,
        COUNT(DISTINCT ph.Id) AS EditCount,
        AVG(pl.RelatedPostId) AS AvgLinks,
        MAX(p.ViewCount) AS MaxViews
    FROM
        Posts p
    LEFT JOIN PostHistory ph ON p.Id = ph.PostId AND ph.PostHistoryTypeId IN (4, 5, 6)
    LEFT JOIN PostLinks pl ON p.Id = pl.PostId
    GROUP BY
        p.OwnerUserId
),
comment_aggregates AS (
    SELECT
        c.UserId,
        AVG(c.Score) AS AvgCommentScore,
        COUNT(DISTINCT c.PostId) AS UniquePostsCommentedOn
    FROM
        Comments c
    GROUP BY
        c.UserId
)
SELECT
    ua.UserId,
    ua.DisplayName,
    ua.Reputation,
    ua.TotalPosts,
    ua.Questions,
    ua.Answers,
    ua.Comments,
    ua.VotesReceived,
    ua.AvgPostScore,
    ua.BadgePoints,
    ps.EditCount,
    ps.AvgLinks,
    ps.MaxViews,
    ca.AvgCommentScore,
    ca.UniquePostsCommentedOn,
    (ua.Reputation / NULLIF(ua.TotalPosts, 0)) AS ReputationPerPost,
    RANK() OVER (ORDER BY ua.Reputation DESC) AS ReputationRank
FROM
    user_activity ua
LEFT JOIN post_stats ps ON ua.UserId = ps.OwnerUserId
LEFT JOIN comment_aggregates ca ON ua.UserId = ca.UserId
WHERE
    ua.TotalPosts > 10
    AND ua.Reputation > 100
ORDER BY
    ReputationRank
LIMIT 100;