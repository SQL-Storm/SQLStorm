-- {"query": "52088.sql", "dataset": "stackoverflow", "version": "v1.1", "prompt": "p2", "model": "grok-code-fast", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2165, "output_tokens": 837} 
WITH UserStats AS (
    SELECT 
        u.Id,
        u.Reputation,
        u.CreationDate AS UserCreationDate,
        COUNT(DISTINCT p.Id) AS TotalPosts,
        SUM(CASE WHEN p.PostTypeId = 1 THEN 1 ELSE 0 END) AS Questions,
        SUM(CASE WHEN p.PostTypeId = 2 THEN 1 ELSE 0 END) AS Answers,
        AVG(p.Score) AS AvgPostScore,
        SUM(p.ViewCount) AS TotalViews,
        COUNT(DISTINCT c.Id) AS TotalComments,
        COUNT(DISTINCT b.Id) AS TotalBadges,
        SUM(CASE WHEN b.Class = 1 THEN 1 ELSE 0 END) AS GoldBadges,
        SUM(CASE WHEN b.Class = 2 THEN 1 ELSE 0 END) AS SilverBadges,
        SUM(CASE WHEN b.Class = 3 THEN 1 ELSE 0 END) AS BronzeBadges,
        SUM(CASE WHEN v.VoteTypeId = 2 THEN 1 ELSE 0 END) AS UpVotesReceived,
        SUM(CASE WHEN v.VoteTypeId = 3 THEN 1 ELSE 0 END) AS DownVotesReceived
    FROM Users u
    LEFT JOIN Posts p ON u.Id = p.OwnerUserId
    LEFT JOIN Comments c ON u.Id = c.UserId
    LEFT JOIN Badges b ON u.Id = b.UserId
    LEFT JOIN Votes v ON p.Id = v.PostId
    GROUP BY u.Id, u.Reputation, u.CreationDate
),
TopUsers AS (
    SELECT *,
           ROW_NUMBER() OVER (ORDER BY Reputation DESC, TotalPosts DESC, TotalBadges DESC) AS Rank
    FROM UserStats
    WHERE Questions > 10 AND Answers > 20 AND TotalBadges > 5
),
PostHistoryStats AS (
    SELECT 
        ph.PostId,
        COUNT(*) AS EditCount,
        MAX(ph.CreationDate) AS LastEdit
    FROM PostHistory ph
    WHERE ph.PostHistoryTypeId IN (4, 5, 6)
    GROUP BY ph.PostId
),
TagStats AS (
    SELECT 
        p.Id AS PostId,
        unnest(string_to_array(substring(p.Tags, 2, length(p.Tags)-2), '><')) AS Tag
    FROM Posts p
    WHERE p.PostTypeId = 1 AND p.Tags IS NOT NULL
),
TagPopularity AS (
    SELECT 
        Tag,
        COUNT(*) AS TagUsage
    FROM TagStats
    GROUP BY Tag
    ORDER BY TagUsage DESC
    LIMIT 100
)
SELECT 
    tu.Id,
    tu.Reputation,
    tu.TotalPosts,
    tu.Questions,
    tu.Answers,
    tu.AvgPostScore,
    tu.TotalViews,
    tu.TotalComments,
    tu.TotalBadges,
    tu.GoldBadges,
    tu.SilverBadges,
    tu.BronzeBadges,
    tu.UpVotesReceived,
    tu.DownVotesReceived,
    tu.Rank,
    phs.EditCount,
    phs.LastEdit,
    STRING_AGG(DISTINCT ts.Tag, ', ') AS PopularTags
FROM TopUsers tu
LEFT JOIN PostHistoryStats phs ON tu.Id = (SELECT OwnerUserId FROM Posts WHERE Id = phs.PostId LIMIT 1)
LEFT JOIN TagStats ts ON EXISTS (SELECT 1 FROM Posts p WHERE p.Id = ts.PostId AND p.OwnerUserId = tu.Id)
LEFT JOIN TagPopularity tp ON tp.Tag = ts.Tag
WHERE tp.TagUsage > 1000
GROUP BY tu.Id, tu.Reputation, tu.TotalPosts, tu.Questions, tu.Answers, tu.AvgPostScore, tu.TotalViews, tu.TotalComments, tu.TotalBadges, tu.GoldBadges, tu.SilverBadges, tu.BronzeBadges, tu.UpVotesReceived, tu.DownVotesReceived, tu.Rank, phs.EditCount, phs.LastEdit
ORDER BY tu.Rank;