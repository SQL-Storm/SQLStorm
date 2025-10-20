-- {"query": "53022.sql", "dataset": "stackoverflow", "version": "v1.1", "prompt": "p2", "model": "grok-4", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2646, "output_tokens": 911} 
WITH UserActivity AS (
    SELECT 
        u.Id AS UserId,
        u.Reputation,
        COUNT(DISTINCT CASE WHEN p.PostTypeId = 1 THEN p.Id END) AS QuestionCount,
        COUNT(DISTINCT CASE WHEN p.PostTypeId = 2 THEN p.Id END) AS AnswerCount,
        SUM(CASE WHEN v.VoteTypeId = 2 THEN 1 ELSE 0 END) AS UpvoteCount,
        SUM(CASE WHEN v.VoteTypeId = 3 THEN 1 ELSE 0 END) AS DownvoteCount,
        AVG(p.Score) AS AvgPostScore,
        MAX(p.ViewCount) AS MaxViewCount
    FROM 
        Users u
    LEFT JOIN 
        Posts p ON u.Id = p.OwnerUserId
    LEFT JOIN 
        Votes v ON p.Id = v.PostId
    WHERE 
        u.Reputation > 1000
    GROUP BY 
        u.Id, u.Reputation
    HAVING 
        COUNT(DISTINCT p.Id) > 50
),
BadgeSummary AS (
    SELECT 
        UserId,
        COUNT(CASE WHEN Class = 1 THEN 1 END) AS GoldBadges,
        COUNT(CASE WHEN Class = 2 THEN 1 END) AS SilverBadges,
        COUNT(CASE WHEN Class = 3 THEN 1 END) AS BronzeBadges
    FROM 
        Badges
    GROUP BY 
        UserId
),
TagPopularity AS (
    SELECT 
        p.OwnerUserId AS UserId,
        UNNEST(string_to_array(substring(p.Tags, 2, length(p.Tags)-2), '><')) AS Tag,
        COUNT(*) AS TagCount,
        ROW_NUMBER() OVER (PARTITION BY p.OwnerUserId ORDER BY COUNT(*) DESC) AS rn
    FROM 
        Posts p
    WHERE 
        p.PostTypeId = 1 AND p.Tags IS NOT NULL
    GROUP BY 
        p.OwnerUserId, Tag
),
TopTags AS (
    SELECT 
        UserId,
        Tag AS TopTag,
        TagCount
    FROM 
        TagPopularity
    WHERE 
        rn = 1
),
PostHistoryEdits AS (
    SELECT 
        ph.PostId,
        COUNT(*) AS EditCount,
        MAX(ph.CreationDate) AS LastEditDate
    FROM 
        PostHistory ph
    WHERE 
        ph.PostHistoryTypeId IN (4,5,6,7,8,9)
    GROUP BY 
        ph.PostId
),
CommentActivity AS (
    SELECT 
        c.UserId,
        COUNT(*) AS CommentCount,
        AVG(c.Score) AS AvgCommentScore
    FROM 
        Comments c
    GROUP BY 
        c.UserId
)
SELECT 
    ua.UserId,
    ua.Reputation,
    ua.QuestionCount,
    ua.AnswerCount,
    ua.UpvoteCount,
    ua.DownvoteCount,
    ua.AvgPostScore,
    ua.MaxViewCount,
    bs.GoldBadges,
    bs.SilverBadges,
    bs.BronzeBadges,
    tt.TopTag,
    tt.TagCount,
    SUM(pe.EditCount) AS TotalEdits,
    MAX(pe.LastEditDate) AS LatestEdit,
    ca.CommentCount,
    ca.AvgCommentScore,
    RANK() OVER (ORDER BY ua.Reputation DESC, bs.GoldBadges DESC) AS OverallRank
FROM 
    UserActivity ua
LEFT JOIN 
    BadgeSummary bs ON ua.UserId = bs.UserId
LEFT JOIN 
    TopTags tt ON ua.UserId = tt.UserId
LEFT JOIN 
    Posts p ON ua.UserId = p.OwnerUserId
LEFT JOIN 
    PostHistoryEdits pe ON p.Id = pe.PostId
LEFT JOIN 
    CommentActivity ca ON ua.UserId = ca.UserId
WHERE 
    bs.GoldBadges >= 5 OR ua.QuestionCount > 100
GROUP BY 
    ua.UserId, ua.Reputation, ua.QuestionCount, ua.AnswerCount, ua.UpvoteCount, ua.DownvoteCount, ua.AvgPostScore, ua.MaxViewCount,
    bs.GoldBadges, bs.SilverBadges, bs.BronzeBadges, tt.TopTag, tt.TagCount, ca.CommentCount, ca.AvgCommentScore
ORDER BY 
    OverallRank
LIMIT 100;