-- {"query": "3696.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gpt-oss-120b", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2089, "output_tokens": 2155} 

WITH user_stats AS (
    SELECT 
        u.Id,
        u.DisplayName,
        u.Reputation,
        COALESCE(u.UpVotes,0) - COALESCE(u.DownVotes,0)                AS NetVotes,
        (SELECT COUNT(*) FROM Badges b WHERE b.UserId = u.Id AND b.Class = 1) AS GoldBadges,
        (SELECT COUNT(*) FROM Badges b WHERE b.UserId = u.Id AND b.Class = 2) AS SilverBadges,
        (SELECT COUNT(*) FROM Badges b WHERE b.UserId = u.Id AND b.Class = 3) AS BronzeBadges,
        (SELECT COUNT(*) FROM Posts p WHERE p.OwnerUserId = u.Id AND p.PostTypeId = 1) AS QuestionCount,
        (SELECT COUNT(*) FROM Posts p WHERE p.OwnerUserId = u.Id AND p.PostTypeId = 2) AS AnswerCount
    FROM Users u
    WHERE u.Reputation > 1000
),
tag_stats AS (
    SELECT 
        t.TagName,
        t.Count                                 AS TagUseCount,
        COALESCE(LENGTH(p_body.Body),0)         AS ExcerptLength,
        COALESCE(LENGTH(p_wiki.Body),0)         AS WikiLength
    FROM Tags t
    LEFT JOIN Posts p_body ON p_body.Id = t.ExcerptPostId
    LEFT JOIN Posts p_wiki ON p_wiki.Id = t.WikiPostId
    WHERE t.IsModeratorOnly = 0
),
top_questions AS (
    SELECT 
        p.Id,
        p.Title,
        p.Score,
        p.ViewCount,
        p.CreationDate,
        u.DisplayName                                 AS OwnerName,
        COUNT(v.Id) FILTER (WHERE v.VoteTypeId = 2)   AS UpVoteCount,
        COUNT(v.Id) FILTER (WHERE v.VoteTypeId = 3)   AS DownVoteCount,
        ROW_NUMBER() OVER (ORDER BY p.Score DESC, p.ViewCount DESC) AS rn
    FROM Posts p
    LEFT JOIN Users u ON u.Id = p.OwnerUserId
    LEFT JOIN Votes v ON v.PostId = p.Id
    WHERE p.PostTypeId = 1
      AND p.CreationDate >= DATE '2020-01-01'
      AND p.Tags IS NOT NULL AND p.Tags <> ''
    GROUP BY p.Id, p.Title, p.Score, p.ViewCount, p.CreationDate, u.DisplayName
    HAVING COUNT(v.Id) FILTER (WHERE v.VoteTypeId = 2) > 10
),
recent_closed AS (
    SELECT 
        ph.PostId,
        ph.CreationDate                     AS ClosedDate,
        ph.Comment                          AS CloseReasonId,
        pt.Title,
        COALESCE(u.DisplayName,'Anonymous') AS ClosedBy
    FROM PostHistory ph
    JOIN Posts pt ON pt.Id = ph.PostId
    LEFT JOIN Users u ON u.Id = ph.UserId
    WHERE ph.PostHistoryTypeId = 10
      AND ph.CreationDate >= NOW() - INTERVAL '30 days'
)
SELECT 
    us.Id,
    us.DisplayName,
    us.Reputation,
    us.NetVotes,
    us.GoldBadges,
    us.SilverBadges,
    us.BronzeBadges,
    us.QuestionCount,
    us.AnswerCount,
    COALESCE(ts.TagName,'N/A')           AS TopTag,
    COALESCE(ts.TagUseCount,0)           AS TagUseCount,
    tq.Title                             AS RecentTopQuestion,
    tq.Score                             AS QuestionScore,
    tq.ViewCount,
    rc.Title                             AS RecentlyClosedTitle,
    rc.ClosedDate,
    CASE
        WHEN rc.CloseReasonId IS NULL THEN 'Unknown'
        ELSE (SELECT crt.Name FROM CloseReasonTypes crt WHERE crt.Id = rc.CloseReasonId::smallint)
    END                                 AS CloseReason
FROM user_stats us
LEFT JOIN LATERAL (
    SELECT t.TagName, t.TagUseCount
    FROM tag_stats t
    ORDER BY t.TagUseCount DESC
    LIMIT 1
) ts ON true
LEFT JOIN LATERAL (
    SELECT Title, Score, ViewCount
    FROM top_questions tq
    WHERE tq.rn = (us.Id % 100) + 1         -- deterministic pick per user
    LIMIT 1
) tq ON true
LEFT JOIN recent_closed rc ON rc.PostId = us.Id
WHERE (us.Reputation + us.NetVotes) > 1500
ORDER BY us.Reputation DESC
OFFSET 0 ROWS FETCH NEXT 100 ROWS ONLY
UNION ALL
SELECT NULL,NULL,NULL,NULL,NULL,NULL,NULL,NULL,NULL,NULL,NULL,NULL,NULL,NULL,NULL
WHERE FALSE;
