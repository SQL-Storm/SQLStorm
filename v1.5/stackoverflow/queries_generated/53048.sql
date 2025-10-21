-- {"query": "53048.sql", "dataset": "stackoverflow", "version": "v1.1", "prompt": "p2", "model": "grok-4", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2646, "output_tokens": 917} 

WITH RecentPosts AS (
    SELECT 
        p.Id, 
        p.PostTypeId, 
        p.OwnerUserId, 
        p.Score, 
        p.ViewCount, 
        p.CreationDate, 
        p.Tags,
        u.Reputation,
        ROW_NUMBER() OVER (PARTITION BY p.OwnerUserId ORDER BY p.Score DESC) AS PostRank
    FROM 
        Posts p
    JOIN 
        Users u ON p.OwnerUserId = u.Id
    WHERE 
        p.CreationDate >= CURRENT_DATE - INTERVAL '2 years'
        AND p.Score > 0
),
UnnestedTags AS (
    SELECT 
        rp.Id, 
        rp.OwnerUserId, 
        rp.Reputation, 
        rp.Score, 
        rp.ViewCount, 
        rp.PostRank,
        unnest(string_to_array(substring(rp.Tags, 2, length(rp.Tags) - 2), '><')) AS Tag
    FROM 
        RecentPosts rp
    WHERE 
        rp.PostTypeId = 1  -- Questions only
),
TagAggregates AS (
    SELECT 
        ut.Tag, 
        COUNT(DISTINCT ut.Id) AS QuestionCount,
        AVG(ut.Score) AS AvgScore,
        SUM(ut.ViewCount) AS TotalViews,
        MAX(ut.Reputation) AS MaxReputation
    FROM 
        UnnestedTags ut
    GROUP BY 
        ut.Tag
    HAVING 
        COUNT(DISTINCT ut.Id) > 500
),
TopTags AS (
    SELECT 
        Tag, 
        QuestionCount, 
        AvgScore, 
        TotalViews, 
        MaxReputation,
        RANK() OVER (ORDER BY QuestionCount DESC, AvgScore DESC) AS TagRank
    FROM 
        TagAggregates
),
UserStatsPerTag AS (
    SELECT 
        ut.Tag, 
        ut.OwnerUserId, 
        COUNT(DISTINCT ut.Id) AS UserQuestionCount,
        SUM(ut.Score) AS UserTotalScore,
        AVG(ut.ViewCount) AS UserAvgViews,
        MAX(CASE WHEN ut.PostRank = 1 THEN ut.Score ELSE 0 END) AS TopPostScore,
        COUNT(DISTINCT v.Id) AS VotesReceived,
        COUNT(DISTINCT c.Id) AS CommentsReceived,
        COUNT(DISTINCT b.Id) AS BadgesEarned
    FROM 
        UnnestedTags ut
    LEFT JOIN 
        Votes v ON ut.Id = v.PostId AND v.VoteTypeId IN (2, 3)  -- Upvotes and Downvotes
    LEFT JOIN 
        Comments c ON ut.Id = c.PostId
    LEFT JOIN 
        Badges b ON ut.OwnerUserId = b.UserId AND b.Date >= CURRENT_DATE - INTERVAL '2 years'
    GROUP BY 
        ut.Tag, ut.OwnerUserId
    HAVING 
        COUNT(DISTINCT ut.Id) >= 10
),
TopUsers AS (
    SELECT 
        us.Tag, 
        us.OwnerUserId, 
        us.UserQuestionCount, 
        us.UserTotalScore, 
        us.UserAvgViews, 
        us.TopPostScore, 
        us.VotesReceived, 
        us.CommentsReceived, 
        us.BadgesEarned,
        ROW_NUMBER() OVER (PARTITION BY us.Tag ORDER BY us.UserTotalScore DESC, us.UserQuestionCount DESC) AS UserRank
    FROM 
        UserStatsPerTag us
)
SELECT 
    tt.Tag, 
    tt.QuestionCount, 
    tt.AvgScore, 
    tt.TotalViews, 
    tt.MaxReputation,
    u.DisplayName AS TopUserName, 
    tu.UserQuestionCount, 
    tu.UserTotalScore, 
    tu.UserAvgViews, 
    tu.TopPostScore, 
    tu.VotesReceived, 
    tu.CommentsReceived, 
    tu.BadgesEarned,
    (SELECT COUNT(*) FROM PostHistory ph WHERE ph.PostId IN (SELECT Id FROM RecentPosts WHERE Tags LIKE '%' || tt.Tag || '%') AND ph.PostHistoryTypeId IN (4,5,6)) AS EditCount
FROM 
    TopTags tt
JOIN 
    TopUsers tu ON tt.Tag = tu.Tag AND tu.UserRank = 1
JOIN 
    Users u ON tu.OwnerUserId = u.Id
WHERE 
    tt.TagRank <= 20
ORDER BY 
    tt.TagRank;
