-- {"query": "3345.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gpt-oss-120b", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2089, "output_tokens": 2331}
WITH
    q AS (
        SELECT
            p.OwnerUserId AS UserId,
            COUNT(*) AS QuestionCount,
            AVG(p.Score) FILTER (WHERE p.Score IS NOT NULL) AS AvgQuestionScore,
            MAX(p.CreationDate) AS LastQuestionDate
        FROM Posts p
        WHERE p.PostTypeId = 1
        GROUP BY p.OwnerUserId
    ),
    a AS (
        SELECT
            p.OwnerUserId AS UserId,
            COUNT(*) AS AnswerCount,
            AVG(p.Score) AS AvgAnswerScore,
            MAX(p.CreationDate) AS LastAnswerDate
        FROM Posts p
        WHERE p.PostTypeId = 2
        GROUP BY p.OwnerUserId
    ),
    b AS (
        SELECT
            u.Id AS UserId,
            SUM(CASE WHEN bd.Class = 1 THEN 1 ELSE 0 END) AS GoldBadges,
            SUM(CASE WHEN bd.Class = 2 THEN 1 ELSE 0 END) AS SilverBadges,
            SUM(CASE WHEN bd.Class = 3 THEN 1 ELSE 0 END) AS BronzeBadges,
            SUM(CASE WHEN COALESCE(bd.TagBased, FALSE) = TRUE THEN 1 ELSE 0 END) AS TagBasedBadges
        FROM Users u
        LEFT JOIN Badges bd ON bd.UserId = u.Id
        GROUP BY u.Id
    ),
    recent_votes AS (
        SELECT
            v.PostId,
            MAX(v.CreationDate) AS LastVoteDate,
            SUM(CASE WHEN vt.Id = 2 THEN 1 ELSE 0 END) AS UpVotes,
            SUM(CASE WHEN vt.Id = 3 THEN 1 ELSE 0 END) AS DownVotes
        FROM Votes v
        JOIN VoteTypes vt ON vt.Id = v.VoteTypeId
        GROUP BY v.PostId
    ),
    tag_usage AS (
        SELECT
            u.Id AS UserId,
            COUNT(DISTINCT tag) FILTER (WHERE tag IS NOT NULL) AS DistinctTagCount
        FROM Users u
        LEFT JOIN LATERAL (
            SELECT unnest(string_to_array(trim(both '<>' FROM p.Tags), '><')) AS tag
            FROM Posts p
            WHERE p.OwnerUserId = u.Id AND p.PostTypeId = 1 AND p.Tags IS NOT NULL
        ) tags ON TRUE
        GROUP BY u.Id
    ),
    top_questions AS (
        SELECT
            p.Id,
            p.Title,
            p.Score,
            ROW_NUMBER() OVER (ORDER BY p.Score DESC, p.ViewCount DESC) AS rn
        FROM Posts p
        WHERE p.PostTypeId = 1
    )
SELECT
    u.Id                                            AS UserId,
    COALESCE(u.DisplayName, 'Anonymous')            AS DisplayName,
    u.Reputation,
    q.QuestionCount,
    a.AnswerCount,
    b.GoldBadges,
    b.SilverBadges,
    b.BronzeBadges,
    b.TagBasedBadges,
    tag_usage.DistinctTagCount,
    CASE
        WHEN q.LastQuestionDate IS NULL THEN a.LastAnswerDate
        WHEN a.LastAnswerDate IS NULL THEN q.LastQuestionDate
        ELSE GREATEST(q.LastQuestionDate, a.LastAnswerDate)
    END                                            AS LastActivity,
    COALESCE(rv.UpVotes,0) - COALESCE(rv.DownVotes,0) AS NetVotes,
    ROW_NUMBER() OVER (
        PARTITION BY u.Id
        ORDER BY COALESCE(q.AvgQuestionScore,0) + COALESCE(a.AvgAnswerScore,0) DESC
    )                                            AS ScoreRank
FROM Users u
LEFT JOIN q ON q.UserId = u.Id
LEFT JOIN a ON a.UserId = u.Id
LEFT JOIN b ON b.UserId = u.Id
LEFT JOIN tag_usage ON tag_usage.UserId = u.Id
LEFT JOIN LATERAL (
    SELECT rv.UpVotes, rv.DownVotes
    FROM recent_votes rv
    WHERE rv.PostId = (
        SELECT p2.Id
        FROM Posts p2
        WHERE p2.OwnerUserId = u.Id
        ORDER BY p2.CreationDate DESC
        LIMIT 1
    )
) rv ON TRUE
WHERE u.Reputation > 1000

UNION ALL

SELECT
    NULL AS UserId,
    'Top 10 Questions' AS DisplayName,
    NULL AS Reputation,
    NULL AS QuestionCount,
    NULL AS AnswerCount,
    NULL AS GoldBadges,
    NULL AS SilverBadges,
    NULL AS BronzeBadges,
    NULL AS TagBasedBadges,
    NULL AS DistinctTagCount,
    NULL AS LastActivity,
    NULL AS NetVotes,
    NULL AS ScoreRank

UNION ALL

SELECT
    NULL AS UserId,
    tq.Title AS DisplayName,
    NULL AS Reputation,
    NULL AS QuestionCount,
    NULL AS AnswerCount,
    NULL AS GoldBadges,
    NULL AS SilverBadges,
    NULL AS BronzeBadges,
    NULL AS TagBasedBadges,
    NULL AS DistinctTagCount,
    NULL AS LastActivity,
    NULL AS NetVotes,
    NULL AS ScoreRank
FROM top_questions tq
WHERE tq.rn <= 10

ORDER BY
    UserId NULLS LAST,
    ScoreRank NULLS LAST;