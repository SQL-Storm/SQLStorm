-- {"query": "34040.sql", "dataset": "stackoverflow", "version": "v1.1", "prompt": "p2", "model": "gpt-4.1-mini", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 1986, "output_tokens": 1153} 

WITH UserBadgeStats AS (
    SELECT 
        u.Id AS UserId,
        u.DisplayName,
        COUNT(CASE WHEN b.Class = 1 THEN 1 END) AS GoldBadges,
        COUNT(CASE WHEN b.Class = 2 THEN 1 END) AS SilverBadges,
        COUNT(CASE WHEN b.Class = 3 THEN 1 END) AS BronzeBadges,
        AVG(p.Score) AS AvgQuestionScore,
        MAX(p.ViewCount) AS MaxQuestionViewCount,
        COUNT(DISTINCT p.Id) FILTER (WHERE p.PostTypeId = 1) AS QuestionCount,
        COUNT(DISTINCT a.Id) AS AnswerCount
    FROM 
        Users u
    LEFT JOIN 
        Badges b ON b.UserId = u.Id
    LEFT JOIN 
        Posts p ON p.OwnerUserId = u.Id AND p.PostTypeId = 1
    LEFT JOIN 
        Posts a ON a.OwnerUserId = u.Id AND a.PostTypeId = 2
    GROUP BY 
        u.Id, u.DisplayName
),
TopUsers AS (
    SELECT 
        UserId, DisplayName, GoldBadges, SilverBadges, BronzeBadges, AvgQuestionScore, MaxQuestionViewCount, QuestionCount, AnswerCount
    FROM 
        UserBadgeStats
    WHERE 
        GoldBadges >= 3 AND QuestionCount > 10
    ORDER BY 
        AvgQuestionScore DESC NULLS LAST 
    LIMIT 20
),
PopularTags AS (
    SELECT 
        t.TagName,
        t.Count,
        p.Id AS QuestionId,
        p.OwnerUserId,
        p.Score,
        p.ViewCount
    FROM 
        Tags t
    JOIN 
        Posts p ON p.PostTypeId = 1 AND p.Tags LIKE '%' || '<' || t.TagName || '>' || '%'
    WHERE 
        t.Count >= 100000
),
TagUserStats AS (
    SELECT 
        pt.UserId,
        pt.TagName,
        COUNT(pt.QuestionId) AS TagQuestionCount,
        AVG(pt.Score) AS AvgTagScore,
        MAX(pt.ViewCount) AS MaxTagViewCount
    FROM 
        PopularTags pt
    GROUP BY 
        pt.UserId, pt.TagName
),
UserLinkStats AS (
    SELECT 
        pl.PostId,
        pl.RelatedPostId,
        pl.LinkTypeId,
        p.OwnerUserId AS QuestionOwnerUserId,
        rp.OwnerUserId AS RelatedPostOwnerUserId
    FROM 
        PostLinks pl
    JOIN 
        Posts p ON p.Id = pl.PostId AND p.PostTypeId = 1
    JOIN 
        Posts rp ON rp.Id = pl.RelatedPostId
),
UserActivitySummary AS (
    SELECT 
        u.Id AS UserId,
        COUNT(DISTINCT p.Id) AS TotalPosts,
        COUNT(DISTINCT c.Id) AS TotalComments,
        COUNT(DISTINCT v.Id) FILTER (WHERE v.VoteTypeId = 2) AS UpVotes,
        COUNT(DISTINCT v.Id) FILTER (WHERE v.VoteTypeId = 3) AS DownVotes,
        COUNT(DISTINCT ph.Id) FILTER (WHERE ph.PostHistoryTypeId IN (10, 11)) AS CloseReopenEvents
    FROM 
        Users u
    LEFT JOIN 
        Posts p ON p.OwnerUserId = u.Id
    LEFT JOIN 
        Comments c ON c.UserId = u.Id
    LEFT JOIN 
        Votes v ON v.UserId = u.Id
    LEFT JOIN 
        PostHistory ph ON ph.UserId = u.Id
    GROUP BY 
        u.Id
)
SELECT 
    tu.UserId,
    tu.DisplayName,
    tu.GoldBadges,
    tu.SilverBadges,
    tu.BronzeBadges,
    tu.AvgQuestionScore,
    tu.MaxQuestionViewCount,
    tu.QuestionCount,
    tu.AnswerCount,
    COALESCE(tus.TagName, 'No Popular Tag') AS PopularTag,
    COALESCE(tus.TagQuestionCount, 0) AS TagQuestionCount,
    COALESCE(tus.AvgTagScore, 0) AS AvgTagScore,
    COALESCE(tus.MaxTagViewCount, 0) AS MaxTagViewCount,
    uas.TotalPosts,
    uas.TotalComments,
    uas.UpVotes,
    uas.DownVotes,
    uas.CloseReopenEvents,
    COUNT(uls.PostId) FILTER (WHERE uls.LinkTypeId = 3) AS DuplicateLinksMade,
    COUNT(uls.PostId) FILTER (WHERE uls.LinkTypeId = 1) AS LinkedPostsMade
FROM 
    TopUsers tu
LEFT JOIN 
    TagUserStats tus ON tus.UserId = tu.UserId
LEFT JOIN 
    UserActivitySummary uas ON uas.UserId = tu.UserId
LEFT JOIN 
    UserLinkStats uls ON uls.QuestionOwnerUserId = tu.UserId
GROUP BY
    tu.UserId, tu.DisplayName, tu.GoldBadges, tu.SilverBadges, tu.BronzeBadges, tu.AvgQuestionScore, tu.MaxQuestionViewCount,
    tu.QuestionCount, tu.AnswerCount, tus.TagName, tus.TagQuestionCount, tus.AvgTagScore, tus.MaxTagViewCount,
    uas.TotalPosts, uas.TotalComments, uas.UpVotes, uas.DownVotes, uas.CloseReopenEvents
ORDER BY 
    tu.AvgQuestionScore DESC,
    tus.TagQuestionCount DESC
LIMIT 20;
