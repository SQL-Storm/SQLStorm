-- {"query": "35009.sql", "dataset": "stackoverflow", "version": "v1.1", "prompt": "p2", "model": "gpt-4.1", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 1986, "output_tokens": 879} 
WITH RecentActiveUsers AS (
    SELECT 
        u.Id AS UserId,
        u.DisplayName,
        u.Reputation,
        u.CreationDate,
        COUNT(p.Id) AS PostsLast30Days,
        COUNT(c.Id) AS CommentsLast30Days,
        COUNT(v.Id) AS VotesLast30Days
    FROM Users u
    LEFT JOIN Posts p ON p.OwnerUserId = u.Id AND p.CreationDate >= cast('2024-10-01' as date) - INTERVAL '30 days'
    LEFT JOIN Comments c ON c.UserId = u.Id AND c.CreationDate >= cast('2024-10-01' as date) - INTERVAL '30 days'
    LEFT JOIN Votes v ON v.UserId = u.Id AND v.CreationDate >= cast('2024-10-01' as date) - INTERVAL '30 days'
    GROUP BY u.Id, u.DisplayName, u.Reputation, u.CreationDate
    HAVING COUNT(p.Id) + COUNT(c.Id) + COUNT(v.Id) > 0
),
TopTags AS (
    SELECT 
        t.TagName,
        SUM(t.Count) AS TotalTagPosts
    FROM Tags t
    GROUP BY t.TagName
    ORDER BY TotalTagPosts DESC
    LIMIT 10
),
UserTagStats AS (
    SELECT
        u.Id AS UserId,
        tt.TagName,
        COUNT(*) AS PostsInTopTag
    FROM Users u
    JOIN Posts p ON p.OwnerUserId = u.Id AND p.PostTypeId = 1
    JOIN TopTags tt ON position('<' || tt.TagName || '>' IN p.Tags) > 0
    GROUP BY u.Id, tt.TagName
),
PopularQuestions AS (
    SELECT
        p.Id AS QuestionId,
        p.Title,
        p.ViewCount,
        p.Score,
        p.CreationDate,
        p.OwnerUserId,
        array_agg(DISTINCT tt.TagName) AS TopTags
    FROM Posts p
    JOIN TopTags tt ON position('<' || tt.TagName || '>' IN p.Tags) > 0
    WHERE p.PostTypeId = 1 AND p.CreationDate >= cast('2024-10-01' as date) - INTERVAL '365 days'
    GROUP BY p.Id, p.Title, p.ViewCount, p.Score, p.CreationDate, p.OwnerUserId
    HAVING p.ViewCount > 1000 AND p.Score >= 5
    ORDER BY p.ViewCount DESC
    LIMIT 100
),
BadgedUsers AS (
    SELECT
        u.Id,
        COUNT(b.Id) FILTER (WHERE b.Class = 1) AS GoldBadges,
        COUNT(b.Id) FILTER (WHERE b.Class = 2) AS SilverBadges,
        COUNT(b.Id) FILTER (WHERE b.Class = 3) AS BronzeBadges
    FROM Users u
    LEFT JOIN Badges b ON b.UserId = u.Id
    GROUP BY u.Id
)
SELECT 
    rau.UserId,
    rau.DisplayName,
    rau.Reputation,
    rau.CreationDate,
    rau.PostsLast30Days,
    rau.CommentsLast30Days,
    rau.VotesLast30Days,
    COALESCE(gb.GoldBadges, 0) AS GoldBadges,
    COALESCE(gb.SilverBadges, 0) AS SilverBadges,
    COALESCE(gb.BronzeBadges, 0) AS BronzeBadges,
    array_agg(DISTINCT uts.TagName) AS TopTagActivity,
    COUNT(DISTINCT pq.QuestionId) AS PopularQuestionsAuthored
FROM RecentActiveUsers rau
LEFT JOIN UserTagStats uts ON uts.UserId = rau.UserId
LEFT JOIN PopularQuestions pq ON pq.OwnerUserId = rau.UserId
LEFT JOIN BadgedUsers gb ON gb.Id = rau.UserId
GROUP BY 
    rau.UserId, rau.DisplayName, rau.Reputation, rau.CreationDate, 
    rau.PostsLast30Days, rau.CommentsLast30Days, rau.VotesLast30Days,
    gb.GoldBadges, gb.SilverBadges, gb.BronzeBadges
ORDER BY 
    PopularQuestionsAuthored DESC,
    rau.PostsLast30Days DESC,
    rau.Reputation DESC
LIMIT 50;