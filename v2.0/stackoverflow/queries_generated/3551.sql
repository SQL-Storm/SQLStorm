-- {"query": "3551.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gpt-oss-120b", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2089, "output_tokens": 2224} 

/* Complex performance‑benchmark query */
WITH
    /* 1️⃣ Aggregate per‑user statistics */
    UserStats AS (
        SELECT
            u.Id,
            u.DisplayName,
            u.Reputation,
            u.CreationDate,
            COALESCE(b.GoldCnt,0)   AS GoldBadges,
            COALESCE(b.SilverCnt,0) AS SilverBadges,
            COALESCE(b.BronzeCnt,0) AS BronzeBadges,
            qcnt.QuestionCount,
            acnt.AnswerCount,
            avg_score.AvgScore,
            last_post.LastPostDate
        FROM Users u
        LEFT JOIN (
            SELECT
                UserId,
                SUM(CASE WHEN Class = 1 THEN 1 ELSE 0 END) AS GoldCnt,
                SUM(CASE WHEN Class = 2 THEN 1 ELSE 0 END) AS SilverCnt,
                SUM(CASE WHEN Class = 3 THEN 1 ELSE 0 END) AS BronzeCnt
            FROM Badges
            GROUP BY UserId
        ) b ON u.Id = b.UserId
        LEFT JOIN (
            SELECT OwnerUserId, COUNT(*) AS QuestionCount
            FROM Posts
            WHERE PostTypeId = 1
            GROUP BY OwnerUserId
        ) qcnt ON u.Id = qcnt.OwnerUserId
        LEFT JOIN (
            SELECT OwnerUserId, COUNT(*) AS AnswerCount
            FROM Posts
            WHERE PostTypeId = 2
            GROUP BY OwnerUserId
        ) acnt ON u.Id = acnt.OwnerUserId
        LEFT JOIN (
            SELECT OwnerUserId, AVG(Score)::numeric(10,2) AS AvgScore
            FROM Posts
            GROUP BY OwnerUserId
        ) avg_score ON u.Id = avg_score.OwnerUserId
        LEFT JOIN (
            SELECT OwnerUserId, MAX(CreationDate) AS LastPostDate
            FROM Posts
            GROUP BY OwnerUserId
        ) last_post ON u.Id = last_post.OwnerUserId
    ),

    /* 2️⃣ Tag‑level ranking per user (window function + lateral split) */
    TagRank AS (
        SELECT
            t.TagName,
            p.OwnerUserId,
            COUNT(*) AS PostsInTag,
            ROW_NUMBER() OVER (PARTITION BY t.TagName ORDER BY COUNT(*) DESC) AS TagRank
        FROM Posts p
        -- split the <tag><tag> string into separate rows
        CROSS JOIN LATERAL regexp_split_to_table(
            regexp_replace(p.Tags, '^<|>$', '', 'g'),   -- strip leading/trailing '<' '>'
            '><'
        ) AS tagname_raw(tag)
        JOIN Tags t ON t.TagName = tagname_raw.tag
        WHERE p.PostTypeId = 1                                   -- only questions
        GROUP BY t.TagName, p.OwnerUserId
    ),

    /* 3️⃣ Recent voting activity (set operator + filtered aggregates) */
    RecentVotes AS (
        SELECT
            v.UserId,
            COUNT(*) FILTER (WHERE vt.Name = 'UpMod')   AS UpVotes,
            COUNT(*) FILTER (WHERE vt.Name = 'DownMod') AS DownVotes,
            MAX(v.CreationDate)                         AS LastVoteDate
        FROM Votes v
        JOIN VoteTypes vt ON v.VoteTypeId = vt.Id
        WHERE v.CreationDate > CURRENT_DATE - INTERVAL '30 days'
        GROUP BY v.UserId
    ),

    /* 4️⃣ Correlated sub‑query for best answer per user */
    BestAnswer AS (
        SELECT
            a.OwnerUserId,
            a.Id AS AnswerId,
            a.Score AS AnswerScore,
            a.CreationDate AS AnswerDate
        FROM Posts a
        WHERE a.PostTypeId = 2                                   -- answers only
          AND a.Score = (
                SELECT MAX(p2.Score)
                FROM Posts p2
                WHERE p2.OwnerUserId = a.OwnerUserId
                  AND p2.PostTypeId = 2
          )
    )

SELECT
    us.Id,
    us.DisplayName,
    us.Reputation,
    us.GoldBadges,
    us.SilverBadges,
    us.BronzeBadges,
    us.QuestionCount,
    us.AnswerCount,
    us.AvgScore,
    us.LastPostDate,
    rv.UpVotes,
    rv.DownVotes,
    rv.LastVoteDate,
    COALESCE(tr.TagName, '<no‑tag>') AS TopTag,
    tr.PostsInTag,
    tr.TagRank,
    ba.AnswerId,
    ba.AnswerScore,
    ba.AnswerDate
FROM UserStats us
LEFT JOIN RecentVotes rv      ON us.Id = rv.UserId
LEFT JOIN BestAnswer ba       ON us.Id = ba.OwnerUserId
LEFT JOIN LATERAL (
        SELECT TagName, PostsInTag, TagRank
        FROM TagRank tr
        WHERE tr.OwnerUserId = us.Id
        ORDER BY TagRank
        LIMIT 1
) tr ON TRUE
WHERE (us.Reputation > 10000 OR us.GoldBadges > 0)

/* UNION with an aggregated “summary” row using set operator */
UNION ALL
SELECT
    NULL AS Id,
    'Overall Summary' AS DisplayName,
    NULL,
    SUM(GoldBadges),
    SUM(SilverBadges),
    SUM(BronzeBadges),
    SUM(QuestionCount),
    SUM(AnswerCount),
    ROUND(AVG(AvgScore)::numeric,2),
    MAX(LastPostDate),
    SUM(UpVotes),
    SUM(DownVotes),
    MAX(LastVoteDate),
    NULL, NULL, NULL,
    NULL, NULL, NULL
FROM (
    SELECT us.*, rv.UpVotes, rv.DownVotes, rv.LastVoteDate
    FROM UserStats us
    LEFT JOIN RecentVotes rv ON us.Id = rv.UserId
) agg
ORDER BY Reputation DESC NULLS LAST
LIMIT 100;
