-- {"query": "53097.sql", "dataset": "stackoverflow", "version": "v1.1", "prompt": "p2", "model": "grok-4", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2646, "output_tokens": 1216} 

WITH UserActivity AS (
    SELECT 
        u.Id AS UserId,
        u.Reputation,
        COUNT(DISTINCT p.Id) AS TotalPosts,
        SUM(p.Score) AS TotalScore,
        AVG(p.Score) AS AvgScore,
        MAX(p.CreationDate) AS LastPostDate
    FROM 
        Users u
    LEFT JOIN 
        Posts p ON u.Id = p.OwnerUserId
    WHERE 
        p.PostTypeId IN (1, 2)  -- Questions and Answers
    GROUP BY 
        u.Id, u.Reputation
    HAVING 
        COUNT(DISTINCT p.Id) > 10
),
BadgeSummary AS (
    SELECT 
        b.UserId,
        COUNT(CASE WHEN b.Class = 1 THEN 1 END) AS GoldBadges,
        COUNT(CASE WHEN b.Class = 2 THEN 1 END) AS SilverBadges,
        COUNT(CASE WHEN b.Class = 3 THEN 1 END) AS BronzeBadges
    FROM 
        Badges b
    GROUP BY 
        b.UserId
),
VoteAnalysis AS (
    SELECT 
        v.PostId,
        COUNT(CASE WHEN v.VoteTypeId = 2 THEN 1 END) AS Upvotes,
        COUNT(CASE WHEN v.VoteTypeId = 3 THEN 1 END) AS Downvotes,
        SUM(CASE WHEN v.VoteTypeId IN (8, 9) THEN v.BountyAmount ELSE 0 END) AS TotalBounty
    FROM 
        Votes v
    WHERE 
        v.CreationDate >= '2020-01-01'
    GROUP BY 
        v.PostId
),
TagPopularity AS (
    SELECT 
        t.Id AS TagId,
        t.TagName,
        t.Count AS TagCount,
        RANK() OVER (ORDER BY t.Count DESC) AS TagRank
    FROM 
        Tags t
    WHERE 
        t.Count > 1000
),
PostTags AS (
    SELECT 
        p.Id AS PostId,
        p.OwnerUserId,
        TRIM(UNNEST(string_to_array(substring(p.Tags, 2, length(p.Tags)-2), '><'))) AS TagName
    FROM 
        Posts p
    WHERE 
        p.PostTypeId = 1  -- Questions
),
UserTagExpertise AS (
    SELECT 
        pt.OwnerUserId AS UserId,
        pt.TagName,
        COUNT(pt.PostId) AS QuestionsInTag,
        SUM(va.Upvotes) AS TotalUpvotesInTag
    FROM 
        PostTags pt
    JOIN 
        Posts p ON pt.PostId = p.Id
    JOIN 
        VoteAnalysis va ON p.Id = va.PostId
    GROUP BY 
        pt.OwnerUserId, pt.TagName
    HAVING 
        COUNT(pt.PostId) > 5
),
EditHistory AS (
    SELECT 
        ph.PostId,
        COUNT(ph.Id) AS EditCount,
        MAX(ph.CreationDate) AS LastEditDate
    FROM 
        PostHistory ph
    WHERE 
        ph.PostHistoryTypeId IN (4, 5, 6, 7, 8, 9)  -- Edits and Rollbacks
    GROUP BY 
        ph.PostId
),
CommentActivity AS (
    SELECT 
        c.PostId,
        COUNT(c.Id) AS CommentCount,
        AVG(c.Score) AS AvgCommentScore
    FROM 
        Comments c
    GROUP BY 
        c.PostId
),
LinkedPosts AS (
    SELECT 
        pl.PostId,
        COUNT(DISTINCT pl.RelatedPostId) AS LinkedCount
    FROM 
        PostLinks pl
    WHERE 
        pl.LinkTypeId = 1  -- Linked
    GROUP BY 
        pl.PostId
)
SELECT 
    ua.UserId,
    ua.Reputation,
    ua.TotalPosts,
    ua.TotalScore,
    ua.AvgScore,
    ua.LastPostDate,
    bs.GoldBadges,
    bs.SilverBadges,
    bs.BronzeBadges,
    tp.TagName AS TopTag,
    ute.QuestionsInTag,
    ute.TotalUpvotesInTag,
    eh.EditCount,
    ca.CommentCount,
    ca.AvgCommentScore,
    lp.LinkedCount,
    ROW_NUMBER() OVER (PARTITION BY tp.TagRank ORDER BY ua.TotalScore DESC) AS RankInTag
FROM 
    UserActivity ua
JOIN 
    BadgeSummary bs ON ua.UserId = bs.UserId
JOIN 
    UserTagExpertise ute ON ua.UserId = ute.UserId
JOIN 
    TagPopularity tp ON ute.TagName = tp.TagName AND tp.TagRank <= 10
LEFT JOIN 
    Posts p ON ua.UserId = p.OwnerUserId AND p.PostTypeId = 1
LEFT JOIN 
    EditHistory eh ON p.Id = eh.PostId
LEFT JOIN 
    CommentActivity ca ON p.Id = ca.PostId
LEFT JOIN 
    LinkedPosts lp ON p.Id = lp.PostId
LEFT JOIN 
    VoteAnalysis va ON p.Id = va.PostId
WHERE 
    ua.Reputation > 1000
    AND bs.GoldBadges >= 1
    AND va.TotalBounty > 0
GROUP BY 
    ua.UserId, ua.Reputation, ua.TotalPosts, ua.TotalScore, ua.AvgScore, ua.LastPostDate,
    bs.GoldBadges, bs.SilverBadges, bs.BronzeBadges,
    tp.TagName, ute.QuestionsInTag, ute.TotalUpvotesInTag,
    eh.EditCount, ca.CommentCount, ca.AvgCommentScore, lp.LinkedCount, tp.TagRank
HAVING 
    SUM(va.TotalBounty) > 100
ORDER BY 
    ua.TotalScore DESC, tp.TagRank ASC
LIMIT 100;
