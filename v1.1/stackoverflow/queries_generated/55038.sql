-- {"query": "55038.sql", "dataset": "stackoverflow", "version": "v1.1", "prompt": "p2", "model": "gpt-oss-120b", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2048, "output_tokens": 1104} 

WITH 
    TopUsers AS (
        SELECT 
            u.Id,
            u.DisplayName,
            u.Reputation,
            COUNT(b.Id) FILTER (WHERE b.Class = 1) AS GoldBadges,
            COUNT(b.Id) FILTER (WHERE b.Class = 2) AS SilverBadges,
            COUNT(b.Id) FILTER (WHERE b.Class = 3) AS BronzeBadges,
            SUM(CASE WHEN v.VoteTypeId = 2 THEN 1 ELSE 0 END) AS UpVotesGiven,
            SUM(CASE WHEN v.VoteTypeId = 3 THEN 1 ELSE 0 END) AS DownVotesGiven
        FROM Users u
        LEFT JOIN Badges b ON b.UserId = u.Id
        LEFT JOIN Votes v ON v.UserId = u.Id
        GROUP BY u.Id, u.DisplayName, u.Reputation
        HAVING COUNT(p.Id) FILTER (WHERE p.PostTypeId = 1) >= 10
    ),
    TagPopularity AS (
        SELECT
            t.TagName,
            t.Count AS TagUseCount,
            COALESCE(SUM(p.Score), 0) AS TotalScore,
            COALESCE(AVG(p.Score), 0) AS AvgScore,
            COUNT(DISTINCT p.OwnerUserId) AS DistinctAuthors
        FROM Tags t
        JOIN Posts p ON p.Tags LIKE CONCAT('%<', t.TagName, '>%')
        WHERE p.PostTypeId = 1   -- questions only
        GROUP BY t.TagName, t.Count
    ),
    ActiveQuestions AS (
        SELECT
            q.Id,
            q.Title,
            q.CreationDate,
            q.Score,
            q.ViewCount,
            q.FavoriteCount,
            q.AnswerCount,
            q.OwnerUserId,
            ARRAY_AGG(DISTINCT t.TagName) FILTER (WHERE t.TagName IS NOT NULL) AS TagArray,
            COUNT(DISTINCT c.Id) AS CommentCount,
            SUM(CASE WHEN v.VoteTypeId = 2 THEN 1 ELSE 0 END) AS UpVoteCount,
            SUM(CASE WHEN v.VoteTypeId = 3 THEN 1 ELSE 0 END) AS DownVoteCount,
            ROW_NUMBER() OVER (ORDER BY q.Score DESC, q.ViewCount DESC) AS RankByScore
        FROM Posts q
        LEFT JOIN PostLinks pl ON pl.PostId = q.Id AND pl.LinkTypeId = 3   -- duplicate links
        LEFT JOIN Tags t ON q.Tags LIKE CONCAT('%<', t.TagName, '>%')
        LEFT JOIN Comments c ON c.PostId = q.Id
        LEFT JOIN Votes v ON v.PostId = q.Id AND v.VoteTypeId IN (2,3)
        WHERE q.PostTypeId = 1                      -- questions
          AND q.CreationDate >= CURRENT_DATE - INTERVAL '90 days'
          AND pl.Id IS NULL                         -- exclude duplicates
        GROUP BY q.Id, q.Title, q.CreationDate, q.Score, q.ViewCount, q.FavoriteCount, q.AnswerCount, q.OwnerUserId
    )
SELECT
    aq.RankByScore,
    aq.Id AS QuestionId,
    aq.Title,
    aq.CreationDate,
    aq.Score,
    aq.ViewCount,
    aq.FavoriteCount,
    aq.AnswerCount,
    aq.CommentCount,
    aq.UpVoteCount,
    aq.DownVoteCount,
    aq.TagArray,
    u.DisplayName AS OwnerName,
    u.Reputation,
    u.GoldBadges,
    u.SilverBadges,
    u.BronzeBadges,
    tp.TagName,
    tp.TagUseCount,
    tp.TotalScore AS TagTotalScore,
    tp.AvgScore AS TagAvgScore,
    tp.DistinctAuthors AS TagDistinctAuthors
FROM ActiveQuestions aq
JOIN Users u ON u.Id = aq.OwnerUserId
LEFT JOIN LATERAL (
    SELECT 
        t.TagName,
        tp.TagUseCount,
        tp.TotalScore,
        tp.AvgScore,
        tp.DistinctAuthors
    FROM UNNEST(aq.TagArray) AS t(TagName)
    JOIN TagPopularity tp ON tp.TagName = t.TagName
    ORDER BY tp.TotalScore DESC
    LIMIT 3
) tp ON TRUE
ORDER BY aq.RankByScore
LIMIT 100;
