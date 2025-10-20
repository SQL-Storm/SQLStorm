-- {"query": "55016.sql", "dataset": "stackoverflow", "version": "v1.1", "prompt": "p2", "model": "gpt-oss-120b", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2048, "output_tokens": 1266} 
WITH recent_questions AS (
    SELECT
        p.Id            AS QuestionId,
        p.Title,
        p.CreationDate,
        p.Tags
    FROM Posts p
    WHERE p.PostTypeId = 1
      AND p.CreationDate >= (cast('2024-10-01 12:34:56' as timestamp) - INTERVAL '1 year')
),
question_tags AS (
    SELECT
        q.QuestionId,
        TRIM(t) AS TagName
    FROM recent_questions q,
         LATERAL (
             SELECT UNNEST(STRING_TO_ARRAY(SUBSTRING(q.Tags FROM 2 FOR LENGTH(q.Tags)-2), '><')) AS t
         ) AS taglist
),
answers AS (
    SELECT
        a.Id          AS AnswerId,
        a.ParentId    AS QuestionId,
        a.OwnerUserId,
        a.Score,
        a.CreationDate
    FROM Posts a
    WHERE a.PostTypeId = 2
),
answer_votes AS (
    SELECT
        v.PostId                     AS AnswerId,
        COUNT(*) FILTER (WHERE v.VoteTypeId = 2) AS UpVotes,
        COUNT(*) FILTER (WHERE v.VoteTypeId = 3) AS DownVotes
    FROM Votes v
    WHERE v.VoteTypeId IN (2, 3)
    GROUP BY v.PostId
),
user_badges AS (
    SELECT
        b.UserId,
        COUNT(*) FILTER (WHERE b.Class = 1) AS GoldBadges,
        COUNT(*) FILTER (WHERE b.Class = 2) AS SilverBadges,
        COUNT(*) FILTER (WHERE b.Class = 3) AS BronzeBadges
    FROM Badges b
    GROUP BY b.UserId
),
user_stats AS (
    SELECT
        qt.TagName,
        u.Id                        AS UserId,
        u.DisplayName,
        u.Reputation,
        ub.GoldBadges,
        ub.SilverBadges,
        ub.BronzeBadges,
        COUNT(a.AnswerId)           AS AnswerCount,
        AVG(a.Score)                AS AvgAnswerScore,
        SUM(av.UpVotes)             AS TotalUpVotes,
        SUM(av.DownVotes)           AS TotalDownVotes,
        ROW_NUMBER() OVER (PARTITION BY qt.TagName
                           ORDER BY COUNT(a.AnswerId) DESC,
                                    AVG(a.Score) DESC) AS TagRank
    FROM question_tags qt
    JOIN answers a          ON a.QuestionId = qt.QuestionId
    JOIN answer_votes av    ON av.AnswerId = a.AnswerId
    JOIN Users u            ON u.Id = a.OwnerUserId
    LEFT JOIN user_badges ub ON ub.UserId = u.Id
    GROUP BY
        qt.TagName,
        u.Id,
        u.DisplayName,
        u.Reputation,
        ub.GoldBadges,
        ub.SilverBadges,
        ub.BronzeBadges
)
SELECT
    TagName,
    UserId,
    DisplayName,
    Reputation,
    GoldBadges,
    SilverBadges,
    BronzeBadges,
    AnswerCount,
    ROUND(AvgAnswerScore, 2) AS AvgAnswerScore,
    TotalUpVotes,
    TotalDownVotes,
    TagRank
FROM user_stats
WHERE TagRank <= 5                -- top 5 contributors per tag
ORDER BY TagName, TagRank;