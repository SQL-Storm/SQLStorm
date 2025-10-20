-- {"query": "53051.sql", "dataset": "stackoverflow", "version": "v1.1", "prompt": "p2", "model": "grok-4", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2646, "output_tokens": 699} 

WITH PopularTags AS (
    SELECT 
        t.Id AS TagId,
        t.TagName,
        t.Count AS QuestionCount,
        ROW_NUMBER() OVER (ORDER BY t.Count DESC) AS TagRank
    FROM Tags t
    WHERE t.Count > 1000
    LIMIT 50
),
UserPostStats AS (
    SELECT 
        u.Id AS UserId,
        u.Reputation,
        COUNT(CASE WHEN p.PostTypeId = 1 THEN p.Id END) AS QuestionCount,
        COUNT(CASE WHEN p.PostTypeId = 2 THEN p.Id END) AS AnswerCount,
        SUM(p.Score) AS TotalScore,
        AVG(p.Score) AS AvgScore,
        SUM(p.ViewCount) AS TotalViews
    FROM Users u
    JOIN Posts p ON u.Id = p.OwnerUserId
    WHERE u.Reputation > 10000
    GROUP BY u.Id, u.Reputation
    HAVING COUNT(p.Id) > 100
),
BadgeStats AS (
    SELECT 
        b.UserId,
        COUNT(CASE WHEN b.Class = 1 THEN b.Id END) AS GoldBadges,
        COUNT(CASE WHEN b.Class = 2 THEN b.Id END) AS SilverBadges,
        COUNT(CASE WHEN b.Class = 3 THEN b.Id END) AS BronzeBadges
    FROM Badges b
    GROUP BY b.UserId
),
VoteStats AS (
    SELECT 
        v.PostId,
        SUM(CASE WHEN v.VoteTypeId = 2 THEN 1 ELSE 0 END) AS Upvotes,
        SUM(CASE WHEN v.VoteTypeId = 3 THEN 1 ELSE 0 END) AS Downvotes
    FROM Votes v
    GROUP BY v.PostId
),
TagUserActivity AS (
    SELECT 
        pt.TagId,
        ups.UserId,
        COUNT(p.Id) AS PostsInTag,
        SUM(vs.Upvotes - vs.Downvotes) AS NetVotesInTag
    FROM PopularTags pt
    JOIN Posts p ON p.PostTypeId = 1 AND p.Tags LIKE ('%<' || (SELECT TagName FROM Tags WHERE Id = pt.TagId) || '>%')
    JOIN UserPostStats ups ON p.OwnerUserId = ups.UserId
    LEFT JOIN VoteStats vs ON p.Id = vs.PostId
    GROUP BY pt.TagId, ups.UserId
    HAVING COUNT(p.Id) > 10
)
SELECT 
    pt.TagName,
    pt.QuestionCount,
    u.DisplayName,
    ups.Reputation,
    ups.QuestionCount,
    ups.AnswerCount,
    ups.TotalScore,
    ups.AvgScore,
    ups.TotalViews,
    bs.GoldBadges,
    bs.SilverBadges,
    bs.BronzeBadges,
    tua.PostsInTag,
    tua.NetVotesInTag,
    RANK() OVER (PARTITION BY pt.TagId ORDER BY tua.NetVotesInTag DESC) AS RankInTag
FROM PopularTags pt
JOIN TagUserActivity tua ON pt.TagId = tua.TagId
JOIN UserPostStats ups ON tua.UserId = ups.UserId
JOIN Users u ON ups.UserId = u.Id
LEFT JOIN BadgeStats bs ON u.Id = bs.UserId
WHERE pt.TagRank <= 10
ORDER BY pt.TagRank, RankInTag
LIMIT 100;
