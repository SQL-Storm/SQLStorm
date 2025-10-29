-- {"query": "3276.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gpt-oss-120b", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2089, "output_tokens": 1516}
WITH recent_answers AS (
    SELECT
        p.Id                                    AS AnswerId,
        p.ParentId                              AS QuestionId,
        p.OwnerUserId                           AS AnswerOwnerId,
        p.CreationDate,
        p.Score                                 AS AnswerScore,
        p.Body,
        COALESCE(u.Reputation, 0)               AS OwnerReputation,
        COALESCE(u.DisplayName, 'Anonymous')    AS OwnerDisplayName
    FROM Posts p
    LEFT JOIN Users u ON u.Id = p.OwnerUserId
    WHERE p.PostTypeId = 2
      AND p.CreationDate >= (CAST('2024-10-01' AS DATE) - INTERVAL '1 year')
),

question_tags AS (
    SELECT
        ra.AnswerId,
        ra.QuestionId,
        CAST(tag AS VARCHAR(35))                 AS TagName
    FROM recent_answers ra
    JOIN Posts q ON q.Id = ra.QuestionId AND q.PostTypeId = 1
    CROSS JOIN LATERAL (
        SELECT UNNEST(string_to_array(
            SUBSTRING(q.Tags FROM 2 FOR LENGTH(q.Tags) - 2),
            '><'
        )) AS tag
    ) t
    WHERE q.Tags IS NOT NULL
),

user_badge_counts AS (
    SELECT
        b.UserId,
        SUM(CASE WHEN b.Class = 1 THEN 1 ELSE 0 END) AS GoldBadges,
        SUM(CASE WHEN b.Class = 2 THEN 1 ELSE 0 END) AS SilverBadges,
        SUM(CASE WHEN b.Class = 3 THEN 1 ELSE 0 END) AS BronzeBadges
    FROM Badges b
    GROUP BY b.UserId
),

answer_vote_stats AS (
    SELECT
        v.PostId,
        SUM(CASE WHEN v.VoteTypeId = 2 THEN 1 ELSE 0 END) AS UpVotes,
        SUM(CASE WHEN v.VoteTypeId = 3 THEN 1 ELSE 0 END) AS DownVotes,
        SUM(CASE WHEN v.VoteTypeId = 1 THEN 1 ELSE 0 END) AS AcceptedVotes,
        COUNT(*)                                 AS TotalVotes
    FROM Votes v
    WHERE v.VoteTypeId IN (1,2,3)
    GROUP BY v.PostId
),

ranked_user_tag_stats AS (
    SELECT
        qt.TagName,
        ra.AnswerOwnerId,
        u.DisplayName,
        u.Reputation,
        COUNT(*)                                   AS AnswersInPeriod,
        AVG(ra.AnswerScore)                        AS AvgAnswerScore,
        SUM(COALESCE(vs.UpVotes,0) - COALESCE(vs.DownVotes,0)) AS NetVoteScore,
        COALESCE(bc.GoldBadges,0)                  AS GoldBadges,
        COALESCE(bc.SilverBadges,0)                AS SilverBadges,
        COALESCE(bc.BronzeBadges,0)                AS BronzeBadges,
        ROW_NUMBER() OVER (
            PARTITION BY qt.TagName
            ORDER BY COUNT(*) DESC, AVG(ra.AnswerScore) DESC
        )                                          AS RankInTag
    FROM recent_answers ra
    JOIN question_tags qt ON qt.AnswerId = ra.AnswerId
    LEFT JOIN Users u ON u.Id = ra.AnswerOwnerId
    LEFT JOIN answer_vote_stats vs ON vs.PostId = ra.AnswerId
    LEFT JOIN user_badge_counts bc ON bc.UserId = ra.AnswerOwnerId
    GROUP BY
        qt.TagName,
        ra.AnswerOwnerId,
        u.DisplayName,
        u.Reputation,
        bc.GoldBadges,
        bc.SilverBadges,
        bc.BronzeBadges
),

top_users_per_tag AS (
    SELECT *
    FROM ranked_user_tag_stats
    WHERE RankInTag <= 5
),

overall_site_stats AS (
    SELECT
        'Overall'                                    AS Scope,
        NULL                                         AS TagName,
        COUNT(*)                                     AS TotalPosts,
        SUM(CASE WHEN p.PostTypeId = 1 THEN 1 ELSE 0 END) AS TotalQuestions,
        SUM(CASE WHEN p.PostTypeId = 2 THEN 1 ELSE 0 END) AS TotalAnswers,
        AVG(p.Score)                                AS AvgPostScore,
        SUM(CASE WHEN p.ClosedDate IS NOT NULL THEN 1 ELSE 0 END) AS ClosedPosts,
        COUNT(DISTINCT p.OwnerUserId)               AS DistinctAuthors
    FROM Posts p
    WHERE p.CreationDate >= (CAST('2024-10-01' AS DATE) - INTERVAL '1 year')
),

combined AS (
    SELECT
        t.TagName,
        t.AnswerOwnerId          AS UserId,
        t.DisplayName,
        t.Reputation,
        t.AnswersInPeriod,
        t.AvgAnswerScore,
        t.NetVoteScore,
        t.GoldBadges,
        t.SilverBadges,
        t.BronzeBadges,
        t.RankInTag,
        NULL                     AS Scope,
        NULL                     AS TotalPosts,
        NULL                     AS TotalQuestions,
        NULL                     AS TotalAnswers,
        NULL                     AS AvgPostScore,
        NULL                     AS ClosedPosts,
        NULL                     AS DistinctAuthors
    FROM top_users_per_tag t

    UNION ALL

    SELECT
        o.TagName,
        NULL                     AS UserId,
        NULL                     AS DisplayName,
        NULL                     AS Reputation,
        NULL                     AS AnswersInPeriod,
        NULL                     AS AvgAnswerScore,
        NULL                     AS NetVoteScore,
        NULL                     AS GoldBadges,
        NULL                     AS SilverBadges,
        NULL                     AS BronzeBadges,
        NULL                     AS RankInTag,
        o.Scope,
        o.TotalPosts,
        o.TotalQuestions,
        o.TotalAnswers,
        o.AvgPostScore,
        o.ClosedPosts,
        o.DistinctAuthors
    FROM overall_site_stats o
)

SELECT *
FROM combined
ORDER BY
    COALESCE(TagName, 'ZZZZ'),
    CASE WHEN UserId IS NULL THEN 0 ELSE 1 END,
    RankInTag;