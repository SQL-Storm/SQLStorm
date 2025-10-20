-- {"query": "39019.sql", "dataset": "stackoverflow", "version": "v1.1", "prompt": "p2", "model": "codex-mini-latest", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 1972, "output_tokens": 2085} 

WITH RecentPosts AS (
    SELECT
        p.Id,
        p.PostTypeId,
        p.Title,
        p.CreationDate,
        u.DisplayName         AS Author,
        COUNT(v.Id) FILTER (WHERE v.VoteTypeId = 2) AS UpVotes,
        COUNT(v.Id) FILTER (WHERE v.VoteTypeId = 3) AS DownVotes,
        COUNT(c.Id)           AS CommentsCount,
        COUNT(ph.Id) FILTER (WHERE ph.PostHistoryTypeId IN (5,6)) AS Edits
    FROM Posts p
    LEFT JOIN Users u       ON p.OwnerUserId    = u.Id
    LEFT JOIN Votes v       ON v.PostId         = p.Id
    LEFT JOIN Comments c    ON c.PostId         = p.Id
    LEFT JOIN PostHistory ph ON ph.PostId       = p.Id
    WHERE p.CreationDate >= now() - INTERVAL '90 days'
    GROUP BY p.Id, p.PostTypeId, p.Title, p.CreationDate, u.DisplayName
),
TagAggregation AS (
    SELECT
        unnest(string_to_array(substring(p.Tags, 2, length(p.Tags)-2), '><')) AS Tag,
        p.Id AS PostId
    FROM Posts p
    WHERE p.Tags IS NOT NULL
),
TagStats AS (
    SELECT
        t.Tag,
        COUNT(rp.Id)             AS PostsCount,
        AVG(rp.UpVotes::numeric) AS AvgUpVotes,
        AVG(rp.CommentsCount::numeric) AS AvgComments,
        MAX(rp.Edits)            AS MaxEdits
    FROM TagAggregation t
    JOIN RecentPosts rp       ON rp.Id = t.PostId
    GROUP BY t.Tag
),
Leaderboard AS (
    SELECT
        rp.Author,
        SUM(rp.UpVotes)          AS TotalUp,
        SUM(rp.DownVotes)        AS TotalDown,
        SUM(rp.CommentsCount)    AS TotalComments,
        ROW_NUMBER() OVER (ORDER BY SUM(rp.UpVotes) DESC) AS RankByUpvotes,
        COUNT(b.Id) FILTER (WHERE b.Class = 1) AS GoldBadges,
        COUNT(b.Id) FILTER (WHERE b.Class = 2) AS SilverBadges,
        COUNT(b.Id) FILTER (WHERE b.Class = 3) AS BronzeBadges
    FROM RecentPosts rp
    LEFT JOIN Users u2         ON u2.DisplayName = rp.Author
    LEFT JOIN Badges b         ON b.UserId       = u2.Id
    GROUP BY rp.Author
),
TopTags AS (
    SELECT Tag, PostsCount, AvgUpVotes, AvgComments, MaxEdits
    FROM TagStats
    ORDER BY PostsCount DESC
    LIMIT 10
),
TopUsers AS (
    SELECT Author, TotalUp, TotalDown, TotalComments, RankByUpvotes, GoldBadges, SilverBadges, BronzeBadges
    FROM Leaderboard
    WHERE RankByUpvotes <= 10
)
SELECT
    tt.Tag,
    tu.Author,
    tt.PostsCount,
    tt.AvgUpVotes,
    tt.AvgComments,
    tt.MaxEdits,
    tu.TotalUp,
    tu.TotalDown,
    tu.TotalComments,
    tu.RankByUpvotes,
    tu.GoldBadges,
    tu.SilverBadges,
    tu.BronzeBadges
FROM TopTags tt
CROSS JOIN TopUsers tu
ORDER BY tt.PostsCount DESC, tu.TotalUp DESC;
