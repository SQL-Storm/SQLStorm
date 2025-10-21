-- {"query": "54037.sql", "dataset": "stackoverflow", "version": "v1.1", "prompt": "p2", "model": "gpt-oss-20b", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2048, "output_tokens": 2169} 
WITH processed_posts AS (
    SELECT
        p.Id AS PostId,
        p.Title,
        p.ViewCount,
        p.Score,
        p.CreationDate,
        p.Tags,
        u.Reputation AS UserRep,
        u.Id AS UserId,
        v.VoteTypeId,
        c.Id AS CommentId,
        b.Id AS BadgeId,
        b.Class AS BadgeClass
    FROM Posts p
    LEFT JOIN Users u ON u.Id = p.OwnerUserId
    LEFT JOIN Votes v ON v.PostId = p.Id
    LEFT JOIN Comments c ON c.PostId = p.Id
    LEFT JOIN Badges b ON b.UserId = u.Id
    WHERE p.PostTypeId = 1
),
aggregated AS (
    SELECT
        PostId,
        Title,
        ViewCount,
        Score,
        COUNT(DISTINCT CASE WHEN VoteTypeId = 2 THEN UserId END) AS upvotes,
        COUNT(DISTINCT CASE WHEN VoteTypeId = 3 THEN UserId END) AS downvotes,
        COUNT(DISTINCT CommentId) AS comment_count,
        COUNT(DISTINCT BadgeId) AS badge_count,
        AVG(UserRep) AS avg_reputation,
        MAX(UserRep) AS max_reputation,
        SUM(CASE WHEN BadgeClass = 1 THEN 1 ELSE 0 END) AS gold_badges,
        SUM(CASE WHEN BadgeClass = 2 THEN 1 ELSE 0 END) AS silver_badges,
        SUM(CASE WHEN BadgeClass = 3 THEN 1 ELSE 0 END) AS bronze_badges
    FROM processed_posts
    GROUP BY PostId, Title, ViewCount, Score
),
ranked AS (
    SELECT
        *,
        ROW_NUMBER() OVER (ORDER BY ViewCount DESC, upvotes DESC) AS rn
    FROM aggregated
)
SELECT
    PostId,
    Title,
    ViewCount,
    Score,
    upvotes,
    downvotes,
    comment_count,
    badge_count,
    gold_badges,
    silver_badges,
    bronze_badges,
    avg_reputation,
    max_reputation
FROM ranked
WHERE rn <= 1000
ORDER BY ViewCount DESC, upvotes DESC;