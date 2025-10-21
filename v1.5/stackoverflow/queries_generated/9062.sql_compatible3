WITH
RecentQuestions AS (
    SELECT
        p.Id,
        p.Title,
        p.OwnerUserId,
        p.CreationDate,
        p.Score,
        ROW_NUMBER() OVER (PARTITION BY p.OwnerUserId ORDER BY p.Score DESC, p.CreationDate) AS rn_top_q
    FROM Posts p
    WHERE p.PostTypeId = 1
      AND p.CreationDate >= TIMESTAMP '2024-10-01 12:34:56' - INTERVAL '180 days'
),
TopAnswers AS (
    SELECT
        p.ParentId AS QuestionId,
        p.Id       AS AnswerId,
        p.OwnerUserId,
        p.Score,
        RANK() OVER (PARTITION BY p.ParentId ORDER BY p.Score DESC, p.CreationDate) AS rnk_ans
    FROM Posts p
    WHERE p.PostTypeId = 2
      AND p.CreationDate >= TIMESTAMP '2024-10-01 12:34:56' - INTERVAL '180 days'
),
VoteTallies AS (
    SELECT
        v.PostId,
        SUM(CASE WHEN v.VoteTypeId = 2 THEN 1 ELSE 0 END) AS UpVotes,
        SUM(CASE WHEN v.VoteTypeId = 3 THEN 1 ELSE 0 END) AS DownVotes,
        SUM(CASE WHEN v.VoteTypeId NOT IN (2,3) THEN 1 ELSE 0 END) AS OtherVotes
    FROM Votes v
    GROUP BY v.PostId
),
UserActivity AS (
    SELECT
        u.Id           AS UserId,
        u.DisplayName,
        COUNT(DISTINCT rq.Id)                                  AS AskedQuestions,
        COUNT(DISTINCT ta.AnswerId)                            AS AnsweredQuestions,
        SUM(COALESCE(vt.UpVotes,0) - COALESCE(vt.DownVotes,0)) AS NetVoteScore
    FROM Users u
    LEFT JOIN RecentQuestions rq
      ON rq.OwnerUserId = u.Id
    LEFT JOIN TopAnswers ta
      ON ta.OwnerUserId = u.Id AND ta.rnk_ans = 1
    LEFT JOIN VoteTallies vt
      ON vt.PostId = COALESCE(ta.AnswerId, rq.Id)
    GROUP BY u.Id, u.DisplayName
),
TagStats AS (
    SELECT
        LOWER(tag)        AS TagName,
        COUNT(DISTINCT p.Id) AS QuestionCount,
        AVG(p.Score)        AS AvgScore
    FROM Posts p
         CROSS JOIN UNNEST(string_to_array(substring(p.Tags FROM 2 FOR char_length(p.Tags) - 2), '><')) AS tag
    WHERE p.PostTypeId = 1
    GROUP BY LOWER(tag)
),
BadgeSummary AS (
    SELECT
        b.UserId,
        COUNT(*)                                         AS BadgeCount,
        SUM(CASE WHEN b.Class = 1 THEN 1 ELSE 0 END)      AS GoldBadges,
        SUM(CASE WHEN b.Class = 2 THEN 1 ELSE 0 END)      AS SilverBadges,
        SUM(CASE WHEN b.Class = 3 THEN 1 ELSE 0 END)      AS BronzeBadges
    FROM Badges b
    WHERE b.Date >= TIMESTAMP '2024-10-01 12:34:56' - INTERVAL '1 year'
    GROUP BY b.UserId
)
SELECT
    ua.UserId,
    ua.DisplayName,
    ua.AskedQuestions,
    ua.AnsweredQuestions,
    ua.NetVoteScore,
    ts.TagName,
    ts.QuestionCount,
    ROUND(ts.AvgScore,2)                                     AS AvgTagScore,
    bs.BadgeCount,
    bs.GoldBadges,
    (SELECT COUNT(*) FROM Comments c
     WHERE c.UserId = ua.UserId
       AND c.CreationDate >= TIMESTAMP '2024-10-01 12:34:56' - INTERVAL '180 days'
    )                                                       AS RecentComments,
    CASE
        WHEN ua.AnsweredQuestions > 0
          THEN ROUND( CAST(ua.NetVoteScore AS NUMERIC) / ua.AnsweredQuestions, 2 )
        ELSE NULL
    END                                                      AS VotePerAnswer
FROM UserActivity ua
FULL OUTER JOIN TagStats ts
    ON ts.TagName = ANY(
       SELECT LOWER(word)
       FROM UNNEST(string_to_array(ua.DisplayName, ' ')) AS word
    )
LEFT JOIN BadgeSummary bs
    ON bs.UserId = ua.UserId
WHERE (ua.AskedQuestions > 5 OR ua.AnsweredQuestions > 10)
  AND (ts.QuestionCount > 50 OR ts.AvgScore > 5)
UNION ALL
SELECT
    NULL,
    'SUMMARY TOTALS',
    SUM(ua.AskedQuestions),
    SUM(ua.AnsweredQuestions),
    SUM(ua.NetVoteScore),
    NULL,
    NULL,
    NULL,
    SUM(bs.BadgeCount),
    SUM(bs.GoldBadges),
    SUM(
      ( SELECT COUNT(*) FROM Comments c2 WHERE c2.UserId = ua.UserId )
    ),
    NULL
FROM UserActivity ua
LEFT JOIN BadgeSummary bs ON bs.UserId = ua.UserId
EXCEPT
SELECT
    ua.UserId,
    ua.DisplayName,
    ua.AskedQuestions,
    ua.AnsweredQuestions,
    ua.NetVoteScore,
    ts2.TagName,
    ts2.QuestionCount,
    ROUND(ts2.AvgScore,2),
    bs2.BadgeCount,
    bs2.GoldBadges,
    NULL,
    NULL
FROM UserActivity ua
LEFT JOIN TagStats ts2
    ON ts2.TagName = 'sql'
LEFT JOIN BadgeSummary bs2
    ON bs2.UserId = ua.UserId
WHERE ua.NetVoteScore < 0
ORDER BY 1 NULLS LAST, 2, 3 DESC;