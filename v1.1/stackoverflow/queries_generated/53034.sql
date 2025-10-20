-- {"query": "53034.sql", "dataset": "stackoverflow", "version": "v1.1", "prompt": "p2", "model": "grok-4", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2646, "output_tokens": 941} 

WITH PopularTags AS (
    SELECT 
        TagName,
        Count AS TagCount,
        ROW_NUMBER() OVER (ORDER BY Count DESC) AS Rank
    FROM 
        Tags
    WHERE 
        Count > 1000
    LIMIT 10
),
UserPostStats AS (
    SELECT 
        u.Id AS UserId,
        u.DisplayName,
        u.Reputation,
        COUNT(DISTINCT p.Id) AS TotalPosts,
        SUM(p.Score) AS TotalScore,
        AVG(p.Score) AS AvgScore,
        MAX(p.CreationDate) AS LastPostDate
    FROM 
        Users u
    JOIN 
        Posts p ON u.Id = p.OwnerUserId
    WHERE 
        p.PostTypeId IN (1, 2)  -- Questions and Answers
        AND p.CreationDate >= '2020-01-01'
    GROUP BY 
        u.Id, u.DisplayName, u.Reputation
    HAVING 
        COUNT(DISTINCT p.Id) > 50
),
UserBadges AS (
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
UserVotes AS (
    SELECT 
        v.UserId,
        COUNT(CASE WHEN v.VoteTypeId = 2 THEN 1 END) AS UpVotesGiven,
        COUNT(CASE WHEN v.VoteTypeId = 3 THEN 1 END) AS DownVotesGiven
    FROM 
        Votes v
    JOIN 
        Posts p ON v.PostId = p.Id
    WHERE 
        v.CreationDate >= '2020-01-01'
    GROUP BY 
        v.UserId
),
UserTagActivity AS (
    SELECT 
        p.OwnerUserId AS UserId,
        unnest(string_to_array(substring(p.Tags, 2, length(p.Tags)-2), '><')) AS Tag,
        COUNT(p.Id) AS PostsInTag,
        SUM(p.Score) AS ScoreInTag
    FROM 
        Posts p
    WHERE 
        p.PostTypeId = 1  -- Questions
        AND p.Tags IS NOT NULL
    GROUP BY 
        p.OwnerUserId, Tag
),
TopUsersPerTag AS (
    SELECT 
        uta.UserId,
        uta.Tag,
        uta.PostsInTag,
        uta.ScoreInTag,
        ROW_NUMBER() OVER (PARTITION BY uta.Tag ORDER BY uta.ScoreInTag DESC) AS RankInTag
    FROM 
        UserTagActivity uta
    JOIN 
        PopularTags pt ON uta.Tag = pt.TagName
    WHERE 
        uta.PostsInTag > 10
)
SELECT 
    ups.UserId,
    ups.DisplayName,
    ups.Reputation,
    ups.TotalPosts,
    ups.TotalScore,
    ups.AvgScore,
    ups.LastPostDate,
    COALESCE(ub.GoldBadges, 0) AS GoldBadges,
    COALESCE(ub.SilverBadges, 0) AS SilverBadges,
    COALESCE(ub.BronzeBadges, 0) AS BronzeBadges,
    COALESCE(uv.UpVotesGiven, 0) AS UpVotesGiven,
    COALESCE(uv.DownVotesGiven, 0) AS DownVotesGiven,
    STRING_AGG(CONCAT(tut.Tag, ': ', tut.PostsInTag, ' posts, ', tut.ScoreInTag, ' score'), '; ') AS TopTagActivities
FROM 
    UserPostStats ups
LEFT JOIN 
    UserBadges ub ON ups.UserId = ub.UserId
LEFT JOIN 
    UserVotes uv ON ups.UserId = uv.UserId
LEFT JOIN 
    TopUsersPerTag tut ON ups.UserId = tut.UserId AND tut.RankInTag <= 3
GROUP BY 
    ups.UserId,
    ups.DisplayName,
    ups.Reputation,
    ups.TotalPosts,
    ups.TotalScore,
    ups.AvgScore,
    ups.LastPostDate,
    ub.GoldBadges,
    ub.SilverBadges,
    ub.BronzeBadges,
    uv.UpVotesGiven,
    uv.DownVotesGiven
ORDER BY 
    ups.Reputation DESC,
    ups.TotalScore DESC
LIMIT 100;
