-- {"query": "35097.sql", "dataset": "stackoverflow", "version": "v1.1", "prompt": "p2", "model": "gpt-4.1", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 1986, "output_tokens": 644} 
WITH top_tags AS (
    SELECT
        TagName,
        Count
    FROM Tags
    WHERE IsModeratorOnly = 0
    ORDER BY Count DESC
    LIMIT 10
),
questions_with_top_tags AS (
    SELECT
        p.Id AS QuestionId,
        p.Title,
        p.Tags,
        p.Score,
        p.ViewCount,
        u.DisplayName AS OwnerName,
        u.Reputation AS OwnerReputation,
        p.CreationDate
    FROM Posts p
    INNER JOIN Users u ON p.OwnerUserId = u.Id
    WHERE p.PostTypeId = 1
      AND (
          SELECT COUNT(*)
          FROM top_tags t
          WHERE p.Tags LIKE CONCAT('%<', t.TagName, '>%')
      ) > 0
),
answer_stats AS (
    SELECT
        q.QuestionId,
        COUNT(a.Id) AS AnswerCount,
        MAX(a.Score) AS HighestAnswerScore,
        AVG(a.Score) AS AvgAnswerScore
    FROM questions_with_top_tags q
    LEFT JOIN Posts a ON a.ParentId = q.QuestionId AND a.PostTypeId = 2
    GROUP BY q.QuestionId
),
favorite_counts AS (
    SELECT
        PostId,
        COUNT(*) AS FavoriteCount
    FROM Votes
    WHERE VoteTypeId = 5
    GROUP BY PostId
),
recent_comments AS (
    SELECT
        c.PostId,
        COUNT(*) AS RecentCommentCount
    FROM Comments c
    WHERE c.CreationDate > NOW() - INTERVAL '30 days'
    GROUP BY c.PostId
),
badge_counts AS (
    SELECT
        b.UserId,
        COUNT(*) FILTER (WHERE b.Class = 1) AS GoldBadges,
        COUNT(*) FILTER (WHERE b.Class = 2) AS SilverBadges,
        COUNT(*) FILTER (WHERE b.Class = 3) AS BronzeBadges
    FROM Badges b
    GROUP BY b.UserId
)
SELECT
    q.QuestionId,
    q.Title,
    q.Score AS QuestionScore,
    q.ViewCount,
    q.OwnerName,
    q.OwnerReputation,
    bc.GoldBadges,
    bc.SilverBadges,
    bc.BronzeBadges,
    q.CreationDate,
    a.AnswerCount,
    a.HighestAnswerScore,
    a.AvgAnswerScore,
    COALESCE(f.FavoriteCount, 0) AS Favorites,
    COALESCE(rc.RecentCommentCount, 0) AS RecentCommentCount,
    ARRAY(
        SELECT t.TagName
        FROM top_tags t
        WHERE q.Tags LIKE CONCAT('%<', t.TagName, '>%')
    ) AS TopTags
FROM questions_with_top_tags q
LEFT JOIN answer_stats a ON q.QuestionId = a.QuestionId
LEFT JOIN favorite_counts f ON q.QuestionId = f.PostId
LEFT JOIN recent_comments rc ON q.QuestionId = rc.PostId
LEFT JOIN badge_counts bc ON q.OwnerName = bc.UserId
ORDER BY q.ViewCount DESC, a.AnswerCount DESC, q.Score DESC
LIMIT 50;