-- {"query": "3221.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gpt-oss-120b", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2089, "output_tokens": 2471}
WITH
cte_user_stats AS (
    SELECT
        u.Id,
        u.DisplayName,
        u.Reputation,
        COALESCE(u.UpVotes, 0) - COALESCE(u.DownVotes, 0) AS NetVotes,
        COUNT(b.Id) FILTER (WHERE b.Class = 1) AS GoldBadges,
        COUNT(b.Id) FILTER (WHERE b.Class = 2) AS SilverBadges,
        COUNT(b.Id) FILTER (WHERE b.Class = 3) AS BronzeBadges,
        MAX(p.CreationDate) AS LastPostDate
    FROM Users u
    LEFT JOIN Badges b ON b.UserId = u.Id
    LEFT JOIN Posts p ON p.OwnerUserId = u.Id
    GROUP BY u.Id, u.DisplayName, u.Reputation, u.UpVotes, u.DownVotes
),
cte_top_questions AS (
    SELECT
        q.Id,
        q.Title,
        q.Tags,
        q.Score,
        q.ViewCount,
        q.CreationDate,
        q.OwnerUserId,
        ROW_NUMBER() OVER (PARTITION BY q.OwnerUserId ORDER BY q.Score DESC) AS rn
    FROM Posts q
    WHERE q.PostTypeId = 1
      AND q.Tags IS NOT NULL
      AND q.CreationDate >= DATE '2023-01-01'
),
cte_user_answers AS (
    SELECT
        a.Id,
        a.ParentId AS QuestionId,
        a.OwnerUserId,
        a.Score,
        a.CreationDate,
        ROW_NUMBER() OVER (PARTITION BY a.OwnerUserId ORDER BY a.Score DESC) AS rn_ans
    FROM Posts a
    WHERE a.PostTypeId = 2
),
cte_tag_explode AS (
    SELECT
        q.Id AS QuestionId,
        TRIM(BOTH '<>' FROM UNNEST(string_to_array(SUBSTRING(q.Tags FROM 2 FOR (CHAR_LENGTH(q.Tags)-2)), '><'))) AS Tag
    FROM Posts q
    WHERE q.PostTypeId = 1
),
cte_user_answer_summary AS (
    SELECT
        tq.OwnerUserId,
        COUNT(a.Id) AS AnswerCount,
        MAX(a.Score) AS TopAnswerScore
    FROM cte_top_questions tq
    LEFT JOIN Posts a
        ON a.ParentId = tq.Id
       AND a.PostTypeId = 2
    GROUP BY tq.OwnerUserId
),
main_result AS (
SELECT
    us.Id AS UserId,
    us.DisplayName,
    us.Reputation,
    us.NetVotes,
    us.GoldBadges,
    us.SilverBadges,
    us.BronzeBadges,
    COALESCE(ua.AnswerCount, 0) AS AnswerCountOnTopQuestions,
    COALESCE(ua.TopAnswerScore, 0) AS TopAnswerScore,
    CASE
        WHEN us.LastPostDate IS NULL THEN 'Never posted'
        WHEN us.LastPostDate < (TIMESTAMP '2024-10-01 12:34:56' - INTERVAL '1' YEAR) THEN 'Inactive'
        ELSE 'Active'
    END AS ActivityStatus,
    STRING_AGG(DISTINCT te.Tag, ',') FILTER (WHERE te.Tag IS NOT NULL) AS TagsParticipated,
    (SELECT COUNT(*) FROM Votes v WHERE v.UserId = us.Id AND v.VoteTypeId = 2) AS UpVotesGiven,
    (SELECT COUNT(*) FROM PostHistory ph WHERE ph.UserId = us.Id AND ph.PostHistoryTypeId = 10) AS CloseVotesCast
FROM cte_user_stats us
LEFT JOIN cte_user_answer_summary ua ON ua.OwnerUserId = us.Id
LEFT JOIN cte_tag_explode te
    ON te.QuestionId IN (
        SELECT q.Id FROM cte_top_questions q WHERE q.OwnerUserId = us.Id
    )
WHERE us.Reputation > 1000
  AND (us.GoldBadges + us.SilverBadges) > 5
  AND (us.NetVotes > 0 OR us.LastPostDate IS NOT NULL)
GROUP BY
    us.Id, us.DisplayName, us.Reputation, us.NetVotes,
    us.GoldBadges, us.SilverBadges, us.BronzeBadges,
    ua.AnswerCount, ua.TopAnswerScore, us.LastPostDate
HAVING COUNT(DISTINCT te.Tag) >= 3
)
SELECT * FROM main_result
UNION ALL
SELECT
    NULL AS UserId,
    '--- Summary ---' AS DisplayName,
    NULL::numeric AS Reputation,
    NULL::numeric AS NetVotes,
    NULL::integer AS GoldBadges,
    NULL::integer AS SilverBadges,
    NULL::integer AS BronzeBadges,
    SUM(COALESCE(ua.AnswerCount, 0)) AS AnswerCountOnTopQuestions,
    MAX(COALESCE(ua.TopAnswerScore, 0)) AS TopAnswerScore,
    NULL AS ActivityStatus,
    NULL AS TagsParticipated,
    NULL::integer AS UpVotesGiven,
    NULL::integer AS CloseVotesCast
FROM cte_user_stats us
LEFT JOIN cte_user_answer_summary ua ON ua.OwnerUserId = us.Id
WHERE us.Reputation > 1000
  AND (us.GoldBadges + us.SilverBadges) > 5
  AND (us.NetVotes > 0 OR us.LastPostDate IS NOT NULL)
ORDER BY Reputation DESC
LIMIT 50;