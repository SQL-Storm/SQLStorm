-- {"query": "35038.sql", "dataset": "stackoverflow", "version": "v1.1", "prompt": "p2", "model": "gpt-4.1", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 1986, "output_tokens": 929} 
WITH
TopQuestions AS (
    SELECT
        p.Id AS QuestionId,
        p.Title,
        p.CreationDate,
        p.Score,
        p.ViewCount,
        p.OwnerUserId,
        u.DisplayName AS OwnerDisplayName
    FROM
        Posts p
        JOIN Users u ON p.OwnerUserId = u.Id
    WHERE
        p.PostTypeId = 1
        AND p.CreationDate > NOW() - INTERVAL '18 months'
        AND p.Score > 10
        AND p.ViewCount > 5000
    ORDER BY
        p.Score DESC,
        p.ViewCount DESC
    LIMIT 100
),
AnswerStats AS (
    SELECT
        a.ParentId AS QuestionId,
        COUNT(*) AS AnswerCount,
        MAX(a.Score) AS TopAnswerScore,
        AVG(a.Score) AS AvgAnswerScore
    FROM
        Posts a
    WHERE
        a.PostTypeId = 2
    GROUP BY
        a.ParentId
),
CommentCounts AS (
    SELECT
        c.PostId AS QuestionId,
        COUNT(*) AS CommentCount,
        MAX(c.Score) AS TopCommentScore,
        AVG(c.Score) AS AvgCommentScore
    FROM
        Comments c
    GROUP BY
        c.PostId
),
BadgeCounts AS (
    SELECT
        b.UserId,
        SUM(CASE WHEN b.Class = 1 THEN 1 ELSE 0 END) AS GoldBadges,
        SUM(CASE WHEN b.Class = 2 THEN 1 ELSE 0 END) AS SilverBadges,
        SUM(CASE WHEN b.Class = 3 THEN 1 ELSE 0 END) AS BronzeBadges
    FROM
        Badges b
    GROUP BY
        b.UserId
),
RelatedLinks AS (
    SELECT
        pl.PostId AS QuestionId,
        COUNT(*) FILTER (WHERE pl.LinkTypeId = 1) AS NumLinked,
        COUNT(*) FILTER (WHERE pl.LinkTypeId = 3) AS NumDuplicates
    FROM
        PostLinks pl
    GROUP BY
        pl.PostId
),
VoteAggregates AS (
    SELECT
        v.PostId AS QuestionId,
        SUM(CASE WHEN v.VoteTypeId = 2 THEN 1 ELSE 0 END) AS UpVotes,
        SUM(CASE WHEN v.VoteTypeId = 3 THEN 1 ELSE 0 END) AS DownVotes,
        SUM(CASE WHEN v.VoteTypeId = 5 THEN 1 ELSE 0 END) AS Favorites
    FROM Votes v
    GROUP BY v.PostId
)
SELECT
    tq.QuestionId,
    tq.Title,
    tq.CreationDate,
    tq.Score,
    tq.ViewCount,
    tq.OwnerDisplayName,
    u.Reputation,
    u.CreationDate AS UserCreationDate,
    COALESCE(bc.GoldBadges,0) AS GoldBadges,
    COALESCE(bc.SilverBadges,0) AS SilverBadges,
    COALESCE(bc.BronzeBadges,0) AS BronzeBadges,
    COALESCE(a.AnswerCount,0) AS AnswerCount,
    COALESCE(a.TopAnswerScore,0) AS TopAnswerScore,
    COALESCE(a.AvgAnswerScore,0) AS AvgAnswerScore,
    COALESCE(c.CommentCount,0) AS CommentCount,
    COALESCE(c.TopCommentScore,0) AS TopCommentScore,
    COALESCE(c.AvgCommentScore,0) AS AvgCommentScore,
    COALESCE(rl.NumLinked,0) AS NumLinked,
    COALESCE(rl.NumDuplicates,0) AS NumDuplicates,
    COALESCE(v.UpVotes,0) AS UpVotes,
    COALESCE(v.DownVotes,0) AS DownVotes,
    COALESCE(v.Favorites,0) AS Favorites
FROM
    TopQuestions tq
    JOIN Users u ON tq.OwnerUserId = u.Id
    LEFT JOIN BadgeCounts bc ON bc.UserId = tq.OwnerUserId
    LEFT JOIN AnswerStats a ON a.QuestionId = tq.QuestionId
    LEFT JOIN CommentCounts c ON c.QuestionId = tq.QuestionId
    LEFT JOIN RelatedLinks rl ON rl.QuestionId = tq.QuestionId
    LEFT JOIN VoteAggregates v ON v.QuestionId = tq.QuestionId
ORDER BY
    tq.Score DESC,
    tq.ViewCount DESC,
    tq.CreationDate DESC;