-- {"query": "53060.sql", "dataset": "stackoverflow", "version": "v1.1", "prompt": "p2", "model": "grok-4", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2646, "output_tokens": 1067} 
WITH UserActivity AS (
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
        u.Reputation > 1000
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
        COUNT(CASE WHEN b.Class = 3 THEN 1 END) AS BronzeBadges,
        MAX(b.Date) AS LatestBadgeDate
    FROM 
        Badges b
    GROUP BY 
        b.UserId
),
VoteAnalysis AS (
    SELECT 
        v.PostId,
        SUM(CASE WHEN v.VoteTypeId = 2 THEN 1 ELSE 0 END) AS Upvotes,
        SUM(CASE WHEN v.VoteTypeId = 3 THEN 1 ELSE 0 END) AS Downvotes,
        COUNT(DISTINCT v.UserId) AS UniqueVoters
    FROM 
        Votes v
    WHERE 
        v.CreationDate > '2020-01-01'
    GROUP BY 
        v.PostId
),
TagPopularity AS (
    SELECT 
        t.Id AS TagId,
        t.TagName,
        t.Count AS TagUsage,
        ROW_NUMBER() OVER (ORDER BY t.Count DESC) AS TagRank
    FROM 
        Tags t
    WHERE 
        t.Count > 1000
),
PostTagLinks AS (
    SELECT 
        p.Id AS PostId,
        TRIM(BOTH '<' FROM unnest(string_to_array(substring(p.Tags, 2, length(p.Tags)-2), '><'))) AS TagName
    FROM 
        Posts p
    WHERE 
        p.PostTypeId = 1 AND p.Tags IS NOT NULL
),
UserTagExpertise AS (
    SELECT 
        ua.UserId,
        ptl.TagName,
        COUNT(DISTINCT ptl.PostId) AS TaggedPosts,
        SUM(va.Upvotes) AS TagUpvotes
    FROM 
        UserActivity ua
    JOIN 
        Posts p ON ua.UserId = p.OwnerUserId AND p.PostTypeId = 2
    JOIN 
        Posts q ON p.ParentId = q.Id
    JOIN 
        PostTagLinks ptl ON q.Id = ptl.PostId
    JOIN 
        VoteAnalysis va ON p.Id = va.PostId
    GROUP BY 
        ua.UserId, ptl.TagName
    HAVING 
        COUNT(DISTINCT ptl.PostId) > 5 AND SUM(va.Upvotes) > 50
),
RankedExperts AS (
    SELECT 
        ute.UserId,
        ute.TagName,
        ute.TaggedPosts,
        ute.TagUpvotes,
        tp.TagRank,
        ROW_NUMBER() OVER (PARTITION BY ute.TagName ORDER BY ute.TagUpvotes DESC) AS ExpertiseRank
    FROM 
        UserTagExpertise ute
    JOIN 
        TagPopularity tp ON ute.TagName = tp.TagName
    WHERE 
        tp.TagRank <= 50
)
SELECT 
    ua.UserId,
    u.DisplayName,
    ua.Reputation,
    ua.PostCount,
    ua.TotalScore,
    ua.AvgViewCount,
    ua.QuestionCount,
    ua.AnswerCount,
    bs.GoldBadges,
    bs.SilverBadges,
    bs.BronzeBadges,
    bs.LatestBadgeDate,
    STRING_AGG(CONCAT(re.TagName, ': ', re.TagUpvotes, ' upvotes (Rank ', re.ExpertiseRank, ')'), '; ') AS TopTagsExpertise,
    (SELECT AVG(re.TagUpvotes) FROM RankedExperts re WHERE re.UserId = ua.UserId) AS AvgTagUpvotes
FROM 
    UserActivity ua
JOIN 
    Users u ON ua.UserId = u.Id
LEFT JOIN 
    BadgeSummary bs ON ua.UserId = bs.UserId
LEFT JOIN 
    RankedExperts re ON ua.UserId = re.UserId AND re.ExpertiseRank <= 3
WHERE 
    ua.TotalScore > 1000
GROUP BY 
    ua.UserId, u.DisplayName, ua.Reputation, ua.PostCount, ua.TotalScore, ua.AvgViewCount, ua.QuestionCount, ua.AnswerCount,
    bs.GoldBadges, bs.SilverBadges, bs.BronzeBadges, bs.LatestBadgeDate
ORDER BY 
    ua.Reputation DESC, ua.TotalScore DESC
LIMIT 100;