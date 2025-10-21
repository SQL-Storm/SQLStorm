-- {"query": "53026.sql", "dataset": "stackoverflow", "version": "v1.1", "prompt": "p2", "model": "grok-4", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2646, "output_tokens": 869} 
WITH TopTags AS (
    SELECT 
        t.Id AS TagId,
        t.TagName,
        t.Count AS TagCount,
        ROW_NUMBER() OVER (ORDER BY t.Count DESC) AS TagRank
    FROM 
        Tags t
    WHERE 
        t.Count > 1000
),
UserActivity AS (
    SELECT 
        u.Id AS UserId,
        u.Reputation,
        COUNT(DISTINCT p.Id) AS PostCount,
        SUM(p.Score) AS TotalScore,
        AVG(p.ViewCount) AS AvgViewCount,
        COUNT(DISTINCT CASE WHEN p.PostTypeId = 1 THEN p.Id END) AS QuestionCount,
        COUNT(DISTINCT CASE WHEN p.PostTypeId = 2 THEN p.Id END) AS AnswerCount
    FROM 
        Users u
    LEFT JOIN 
        Posts p ON u.Id = p.OwnerUserId
    WHERE 
        u.Reputation > 10000
    GROUP BY 
        u.Id, u.Reputation
    HAVING 
        COUNT(DISTINCT p.Id) > 50
),
UserBadges AS (
    SELECT 
        b.UserId,
        COUNT(b.Id) AS BadgeCount,
        SUM(CASE WHEN b.Class = 1 THEN 1 ELSE 0 END) AS GoldBadges,
        SUM(CASE WHEN b.Class = 2 THEN 1 ELSE 0 END) AS SilverBadges,
        SUM(CASE WHEN b.Class = 3 THEN 1 ELSE 0 END) AS BronzeBadges
    FROM 
        Badges b
    GROUP BY 
        b.UserId
),
UserVotes AS (
    SELECT 
        v.UserId,
        COUNT(v.Id) AS VoteCount,
        SUM(CASE WHEN v.VoteTypeId = 2 THEN 1 ELSE 0 END) AS UpVotesGiven,
        SUM(CASE WHEN v.VoteTypeId = 3 THEN 1 ELSE 0 END) AS DownVotesGiven
    FROM 
        Votes v
    WHERE 
        v.UserId IS NOT NULL
    GROUP BY 
        v.UserId
),
PostComments AS (
    SELECT 
        p.OwnerUserId,
        COUNT(c.Id) AS CommentCount,
        AVG(c.Score) AS AvgCommentScore
    FROM 
        Posts p
    JOIN 
        Comments c ON p.Id = c.PostId
    GROUP BY 
        p.OwnerUserId
),
UserTagActivity AS (
    SELECT 
        u.UserId,
        tt.TagId,
        COUNT(DISTINCT p.Id) AS PostsInTag
    FROM 
        UserActivity u
    JOIN 
        Posts p ON u.UserId = p.OwnerUserId
    CROSS JOIN 
        TopTags tt
    WHERE 
        p.Tags LIKE '%' || tt.TagName || '%'
    GROUP BY 
        u.UserId, tt.TagId
    HAVING 
        COUNT(DISTINCT p.Id) > 10
)
SELECT 
    ua.UserId,
    ua.Reputation,
    ua.PostCount,
    ua.TotalScore,
    ua.AvgViewCount,
    ua.QuestionCount,
    ua.AnswerCount,
    ub.BadgeCount,
    ub.GoldBadges,
    ub.SilverBadges,
    ub.BronzeBadges,
    uv.VoteCount,
    uv.UpVotesGiven,
    uv.DownVotesGiven,
    pc.CommentCount,
    pc.AvgCommentScore,
    tt.TagName,
    uta.PostsInTag,
    ROW_NUMBER() OVER (PARTITION BY tt.TagId ORDER BY ua.Reputation DESC, ua.TotalScore DESC) AS RankInTag
FROM 
    UserActivity ua
LEFT JOIN 
    UserBadges ub ON ua.UserId = ub.UserId
LEFT JOIN 
    UserVotes uv ON ua.UserId = uv.UserId
LEFT JOIN 
    PostComments pc ON ua.UserId = pc.OwnerUserId
JOIN 
    UserTagActivity uta ON ua.UserId = uta.UserId
JOIN 
    TopTags tt ON uta.TagId = tt.TagId
WHERE 
    tt.TagRank <= 10
ORDER BY 
    tt.TagRank, RankInTag
LIMIT 1000;