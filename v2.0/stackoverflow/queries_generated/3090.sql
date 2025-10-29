-- {"query": "3090.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gpt-oss-120b", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2089, "output_tokens": 2511} 

WITH UserStats AS (
    SELECT 
        u.Id,
        u.DisplayName,
        u.Reputation,
        COUNT(DISTINCT b.Id)                                 AS BadgeCount,
        SUM(CASE WHEN b.Class = 1 THEN 1 ELSE 0 END)         AS GoldBadges,
        SUM(CASE WHEN b.Class = 2 THEN 1 ELSE 0 END)         AS SilverBadges,
        SUM(CASE WHEN b.Class = 3 THEN 1 ELSE 0 END)         AS BronzeBadges,
        COUNT(*) FILTER (WHERE p.PostTypeId = 1)             AS QuestionCount,
        COUNT(*) FILTER (WHERE p.PostTypeId = 2)             AS AnswerCount,
        COALESCE(SUM(p.Score),0)                             AS TotalPostScore,
        MAX(p.CreationDate)                                 AS LastPostDate
    FROM Users u
    LEFT JOIN Badges b   ON b.UserId = u.Id
    LEFT JOIN Posts  p   ON p.OwnerUserId = u.Id
    GROUP BY u.Id, u.DisplayName, u.Reputation
),
TopTagUsage AS (
    SELECT 
        t.TagName,
        COUNT(*)                                    AS Uses,
        ROW_NUMBER() OVER (ORDER BY COUNT(*) DESC) AS rn
    FROM Posts p
    CROSS JOIN LATERAL (
        SELECT unnest(string_to_array(trim(both '<>' FROM p.Tags), '><')) AS tag
    ) AS tags
    JOIN Tags t ON t.TagName = tags.tag
    WHERE p.PostTypeId = 1
    GROUP BY t.TagName
),
RecentCloseVotes AS (
    SELECT 
        ph.PostId,
        COUNT(*)                AS CloseVoteCount,
        MAX(ph.CreationDate)    AS LastCloseVote
    FROM PostHistory ph
    WHERE ph.PostHistoryTypeId = 10
    GROUP BY ph.PostId
),
AnswerStats AS (
    SELECT 
        a.ParentId                                 AS QuestionId,
        COUNT(*)                                   AS AnswerCount,
        AVG(a.Score)                               AS AvgScore,
        MAX(a.Score) FILTER (WHERE a.Score = (
            SELECT MAX(score) FROM Posts WHERE ParentId = a.ParentId
        ))                                         AS TopAnswerScore,
        SUM(CASE WHEN a.Id = p.AcceptedAnswerId THEN 1 ELSE 0 END) AS AcceptedAnswers
    FROM Posts a
    JOIN Posts p ON p.Id = a.ParentId
    WHERE a.PostTypeId = 2
    GROUP BY a.ParentId
),
Combined AS (
    SELECT 
        u.Id,
        u.DisplayName,
        us.Reputation,
        us.GoldBadges,
        us.SilverBadges,
        us.BronzeBadges,
        us.QuestionCount,
        us.AnswerCount,
        us.TotalPostScore,
        us.LastPostDate,
        COALESCE(rc.CloseVoteCount,0)                AS RecentCloseVotes,
        COALESCE(rc.LastCloseVote, TIMESTAMP '1970-01-01') AS LastCloseVoteDate,
        COALESCE(a.AnswerCount,0)                    AS CurrentAnswers,
        COALESCE(a.AvgScore,0)                       AS AvgAnswerScore,
        COALESCE(a.TopAnswerScore,0)                 AS TopAnswerScore,
        CASE WHEN a.AcceptedAnswers > 0 THEN 1 ELSE 0 END AS HasAcceptedAnswer,
        CASE 
            WHEN us.Reputation > 20000 THEN 'Elite' 
            WHEN us.Reputation > 5000  THEN 'Veteran' 
            ELSE 'Member' 
        END                                          AS ReputationTier,
        CASE 
            WHEN POSITION('java' IN LOWER(p.Tags)) > 0 THEN 1 
            ELSE 0 
        END                                          AS HasJavaTag
    FROM Users u
    LEFT JOIN UserStats us ON us.Id = u.Id
    LEFT JOIN LATERAL (
        SELECT Id 
        FROM Posts p2 
        WHERE p2.OwnerUserId = u.Id 
        ORDER BY p2.CreationDate DESC 
        LIMIT 1
    ) recent_post ON TRUE
    LEFT JOIN RecentCloseVotes rc ON rc.PostId = recent_post.Id
    LEFT JOIN LATERAL (
        SELECT Id 
        FROM Posts qp 
        WHERE qp.OwnerUserId = u.Id AND qp.PostTypeId = 1 
        ORDER BY qp.CreationDate DESC 
        LIMIT 1
    ) recent_question ON TRUE
    LEFT JOIN AnswerStats a ON a.QuestionId = recent_question.Id
    LEFT JOIN Posts p ON p.OwnerUserId = u.Id AND p.PostTypeId = 1
)
SELECT *
FROM Combined
WHERE ReputationTier IN ('Elite','Veteran')
  AND (GoldBadges + SilverBadges + BronzeBadges) > 10
  AND (CurrentAnswers = 0 OR AvgAnswerScore > 2)
  AND (LastPostDate > CURRENT_DATE - INTERVAL '180 days')
UNION ALL
SELECT 
    NULL                     AS Id,
    'Aggregate'              AS DisplayName,
    SUM(Reputation)          AS Reputation,
    SUM(GoldBadges)          AS GoldBadges,
    SUM(SilverBadges)        AS SilverBadges,
    SUM(BronzeBadges)        AS BronzeBadges,
    SUM(QuestionCount)      AS QuestionCount,
    SUM(AnswerCount)        AS AnswerCount,
    SUM(TotalPostScore)     AS TotalPostScore,
    MAX(LastPostDate)       AS LastPostDate,
    SUM(RecentCloseVotes)   AS RecentCloseVotes,
    MAX(LastCloseVoteDate)  AS LastCloseVoteDate,
    SUM(CurrentAnswers)     AS CurrentAnswers,
    AVG(AvgAnswerScore)     AS AvgAnswerScore,
    MAX(TopAnswerScore)     AS TopAnswerScore,
    MAX(HasAcceptedAnswer)  AS HasAcceptedAnswer,
    NULL                    AS ReputationTier,
    NULL                    AS HasJavaTag
FROM Combined
EXCEPT
SELECT *
FROM Combined
WHERE ReputationTier = 'Member';
