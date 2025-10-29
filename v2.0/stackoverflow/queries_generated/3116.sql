-- {"query": "3116.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gpt-oss-120b", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2089, "output_tokens": 2873} 

WITH
    RecentPosts AS (
        SELECT
            p.Id,
            p.PostTypeId,
            p.OwnerUserId,
            p.CreationDate,
            p.Score,
            p.ViewCount,
            p.AnswerCount,
            p.Title,
            p.Tags,
            ROW_NUMBER() OVER (PARTITION BY p.PostTypeId ORDER BY p.CreationDate DESC) AS rn
        FROM Posts p
        WHERE p.CreationDate >= CURRENT_DATE - INTERVAL '30 days'
    ),
    UserAgg AS (
        SELECT
            u.Id AS UserId,
            u.DisplayName,
            u.Reputation,
            COUNT(DISTINCT b.Id) FILTER (WHERE b.Class = 1) AS GoldBadges,
            COUNT(DISTINCT b.Id) FILTER (WHERE b.Class = 2) AS SilverBadges,
            COUNT(DISTINCT b.Id) FILTER (WHERE b.Class = 3) AS BronzeBadges,
            COALESCE(SUM(vs.ScoreDelta),0) AS TotalScoreDelta
        FROM Users u
        LEFT JOIN Badges b ON b.UserId = u.Id
        LEFT JOIN (
            SELECT
                po.OwnerUserId AS UserId,
                CASE vt.Id
                    WHEN 2 THEN 1   -- upvote
                    WHEN 3 THEN -1  -- downvote
                    ELSE 0
                END AS ScoreDelta
            FROM Posts po
            JOIN Votes vt ON vt.PostId = po.Id
            WHERE vt.VoteTypeId IN (2,3)
        ) vs ON vs.UserId = u.Id
        GROUP BY u.Id, u.DisplayName, u.Reputation
    ),
    TagStats AS (
        SELECT
            t.TagName,
            t.Count AS TagUseCount,
            COALESCE(e.ExcerptWordCount,0) AS ExcerptWords,
            COALESCE(w.WikiWordCount,0)   AS WikiWords
        FROM Tags t
        LEFT JOIN LATERAL (
            SELECT COUNT(*) FILTER (WHERE word <> '') AS ExcerptWordCount
            FROM regexp_split_to_table(p.Body, '\s+') AS word
            JOIN Posts p ON p.Id = t.ExcerptPostId
        ) e ON TRUE
        LEFT JOIN LATERAL (
            SELECT COUNT(*) FILTER (WHERE word <> '') AS WikiWordCount
            FROM regexp_split_to_table(p.Body, '\s+') AS word
            JOIN Posts p ON p.Id = t.WikiPostId
        ) w ON TRUE
    ),
    PostScoreStats AS (
        SELECT
            p.Id,
            p.PostTypeId,
            p.Score,
            p.ViewCount,
            COALESCE(vc.UpVotes,0) AS UpVotes,
            COALESCE(vc.DownVotes,0) AS DownVotes,
            CASE 
                WHEN p.PostTypeId = 1 THEN p.AnswerCount
                ELSE NULL
            END AS AnswerCount,
            ROW_NUMBER() OVER (PARTITION BY p.PostTypeId ORDER BY (p.Score + COALESCE(vc.UpVotes,0) - COALESCE(vc.DownVotes,0)) DESC) AS RankByScore
        FROM Posts p
        LEFT JOIN (
            SELECT
                PostId,
                COUNT(*) FILTER (WHERE VoteTypeId = 2) AS UpVotes,
                COUNT(*) FILTER (WHERE VoteTypeId = 3) AS DownVotes
            FROM Votes
            GROUP BY PostId
        ) vc ON vc.PostId = p.Id
        WHERE p.PostTypeId IN (1,2)   -- questions and answers
    )
SELECT
    rp.Id AS PostId,
    rp.Title,
    rp.Tags,
    ua.DisplayName,
    ua.Reputation,
    ua.GoldBadges,
    ua.SilverBadges,
    ua.BronzeBadges,
    ps.Score,
    ps.ViewCount,
    ps.UpVotes,
    ps.DownVotes,
    ps.AnswerCount,
    COALESCE(ts.TagUseCount,0) AS TagPopularity,
    CASE 
        WHEN rp.Tags IS NULL THEN NULL
        ELSE (SELECT string_agg(t.TagName, '|')
              FROM unnest(string_to_array(substring(rp.Tags, 2, length(rp.Tags)-2), '><')) AS t(TagName)
              JOIN TagStats ts ON ts.TagName = t.TagName
              LIMIT 5)
    END AS TopTagList,
    CASE 
        WHEN rp.PostTypeId = 1 THEN 
            (SELECT COUNT(*) FROM Posts a WHERE a.ParentId = rp.Id AND a.PostTypeId = 2 AND a.Score > 0)
        ELSE NULL
    END AS PositiveAnswerCount,
    ROW_NUMBER() OVER (ORDER BY ps.Score DESC, ps.ViewCount DESC) AS GlobalScoreRank,
    NULLIF(ua.TotalScoreDelta,0) AS ScoreDeltaIfAny
FROM RecentPosts rp
JOIN UserAgg ua ON ua.UserId = rp.OwnerUserId
JOIN PostScoreStats ps ON ps.Id = rp.Id
LEFT JOIN TagStats ts ON ts.TagName = ANY (string_to_array(substring(rp.Tags, 2, length(rp.Tags)-2), '><'))
WHERE rp.rn <= 100
ORDER BY ps.Score DESC, rp.CreationDate DESC
LIMIT 50
UNION ALL
SELECT
    q.Id,
    q.Title,
    q.Tags,
    u.DisplayName,
    u.Reputation,
    0 AS GoldBadges,
    0 AS SilverBadges,
    0 AS BronzeBadges,
    q.Score,
    q.ViewCount,
    up.VoteUp,
    up.VoteDown,
    q.AnswerCount,
    NULL,
    NULL,
    NULL,
    ROW_NUMBER() OVER (ORDER BY q.Score DESC) AS GlobalScoreRank,
    NULL
FROM Posts q
JOIN Users u ON u.Id = q.OwnerUserId
LEFT JOIN (
    SELECT
        PostId,
        COUNT(*) FILTER (WHERE VoteTypeId = 2) AS VoteUp,
        COUNT(*) FILTER (WHERE VoteTypeId = 3) AS VoteDown
    FROM Votes
    GROUP BY PostId
) up ON up.PostId = q.Id
WHERE q.PostTypeId = 1
  AND q.CreationDate >= CURRENT_DATE - INTERVAL '7 days'
  AND q.Score > 5
ORDER BY GlobalScoreRank
LIMIT 20;
