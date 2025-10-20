-- {"query": "53039.sql", "dataset": "stackoverflow", "version": "v1.1", "prompt": "p2", "model": "grok-4", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2646, "output_tokens": 1287} 

WITH RecentPosts AS (
    SELECT 
        p.Id, 
        p.PostTypeId, 
        p.CreationDate, 
        p.Score, 
        p.ViewCount, 
        p.OwnerUserId, 
        p.Tags, 
        p.AnswerCount, 
        p.CommentCount, 
        p.FavoriteCount,
        ROW_NUMBER() OVER (PARTITION BY p.OwnerUserId ORDER BY p.Score DESC) AS UserPostRank
    FROM 
        Posts p
    WHERE 
        p.CreationDate >= CURRENT_DATE - INTERVAL '2 years'
        AND p.Score > 0
),
ExplodedTags AS (
    SELECT 
        rp.Id AS PostId, 
        unnest(string_to_array(substring(rp.Tags, 2, length(rp.Tags) - 2), '><')) AS TagName
    FROM 
        RecentPosts rp
    WHERE 
        rp.PostTypeId = 1
),
TagUserActivity AS (
    SELECT 
        et.TagName, 
        rp.OwnerUserId, 
        COUNT(DISTINCT rp.Id) AS QuestionCount, 
        SUM(rp.Score) AS TotalQuestionScore, 
        SUM(rp.ViewCount) AS TotalViews, 
        AVG(rp.AnswerCount) AS AvgAnswersPerQuestion,
        RANK() OVER (PARTITION BY et.TagName ORDER BY SUM(rp.Score) DESC) AS UserRankInTag
    FROM 
        ExplodedTags et
    JOIN 
        RecentPosts rp ON et.PostId = rp.Id
    GROUP BY 
        et.TagName, rp.OwnerUserId
    HAVING 
        COUNT(DISTINCT rp.Id) >= 5
),
AnswerDetails AS (
    SELECT 
        p.ParentId AS QuestionId, 
        p.OwnerUserId AS AnswererId, 
        COUNT(p.Id) AS AnswerCount, 
        SUM(p.Score) AS TotalAnswerScore, 
        AVG(p.CommentCount) AS AvgCommentsPerAnswer,
        MAX(p.CreationDate) AS LatestAnswerDate
    FROM 
        Posts p
    JOIN 
        RecentPosts rp ON p.ParentId = rp.Id
    WHERE 
        p.PostTypeId = 2
    GROUP BY 
        p.ParentId, p.OwnerUserId
),
VoteAggregates AS (
    SELECT 
        v.PostId, 
        SUM(CASE WHEN v.VoteTypeId = 2 THEN 1 ELSE 0 END) AS Upvotes, 
        SUM(CASE WHEN v.VoteTypeId = 3 THEN 1 ELSE 0 END) AS Downvotes,
        COUNT(DISTINCT v.UserId) AS UniqueVoters
    FROM 
        Votes v
    JOIN 
        RecentPosts rp ON v.PostId = rp.Id
    WHERE 
        v.CreationDate >= CURRENT_DATE - INTERVAL '2 years'
    GROUP BY 
        v.PostId
),
BadgeCounts AS (
    SELECT 
        b.UserId, 
        COUNT(CASE WHEN b.Class = 1 THEN 1 END) AS GoldBadges, 
        COUNT(CASE WHEN b.Class = 2 THEN 1 END) AS SilverBadges, 
        COUNT(CASE WHEN b.Class = 3 THEN 1 END) AS BronzeBadges
    FROM 
        Badges b
    WHERE 
        b.Date >= CURRENT_DATE - INTERVAL '2 years'
    GROUP BY 
        b.UserId
),
CommentStats AS (
    SELECT 
        c.PostId, 
        COUNT(c.Id) AS CommentCount, 
        AVG(c.Score) AS AvgCommentScore
    FROM 
        Comments c
    JOIN 
        RecentPosts rp ON c.PostId = rp.Id
    GROUP BY 
        c.PostId
),
UserStats AS (
    SELECT 
        u.Id AS UserId, 
        u.DisplayName, 
        u.Reputation, 
        COALESCE(bc.GoldBadges, 0) + COALESCE(bc.SilverBadges, 0) + COALESCE(bc.BronzeBadges, 0) AS TotalBadges
    FROM 
        Users u
    LEFT JOIN 
        BadgeCounts bc ON u.Id = bc.UserId
    WHERE 
        u.Reputation > 1000
),
CombinedStats AS (
    SELECT 
        tua.TagName, 
        us.DisplayName, 
        us.Reputation, 
        tua.QuestionCount, 
        tua.TotalQuestionScore, 
        tua.TotalViews, 
        tua.AvgAnswersPerQuestion, 
        ad.AnswerCount, 
        ad.TotalAnswerScore, 
        ad.AvgCommentsPerAnswer, 
        va.Upvotes, 
        va.Downvotes, 
        va.UniqueVoters, 
        cs.CommentCount, 
        cs.AvgCommentScore, 
        us.TotalBadges,
        DENSE_RANK() OVER (PARTITION BY tua.TagName ORDER BY tua.TotalQuestionScore + COALESCE(ad.TotalAnswerScore, 0) DESC) AS OverallRank
    FROM 
        TagUserActivity tua
    JOIN 
        UserStats us ON tua.OwnerUserId = us.UserId
    LEFT JOIN 
        AnswerDetails ad ON tua.OwnerUserId = ad.AnswererId
    LEFT JOIN 
        RecentPosts rp ON ad.QuestionId = rp.Id
    LEFT JOIN 
        ExplodedTags et ON rp.Id = et.PostId AND tua.TagName = et.TagName
    LEFT JOIN 
        VoteAggregates va ON rp.Id = va.PostId
    LEFT JOIN 
        CommentStats cs ON rp.Id = cs.PostId
    WHERE 
        tua.UserRankInTag <= 10
)
SELECT 
    TagName, 
    DisplayName, 
    Reputation, 
    QuestionCount, 
    TotalQuestionScore, 
    TotalViews, 
    AvgAnswersPerQuestion, 
    AnswerCount, 
    TotalAnswerScore, 
    AvgCommentsPerAnswer, 
    Upvotes, 
    Downvotes, 
    UniqueVoters, 
    CommentCount, 
    AvgCommentScore, 
    TotalBadges, 
    OverallRank
FROM 
    CombinedStats
WHERE 
    OverallRank <= 5
ORDER BY 
    TagName, OverallRank;
