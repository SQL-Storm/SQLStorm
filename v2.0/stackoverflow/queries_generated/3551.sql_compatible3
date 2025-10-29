WITH
    UserStats AS (
        SELECT
            u.Id,
            u.DisplayName,
            u.Reputation,
            u.CreationDate,
            COALESCE(b.GoldCnt, 0)   AS GoldBadges,
            COALESCE(b.SilverCnt, 0) AS SilverBadges,
            COALESCE(b.BronzeCnt, 0) AS BronzeBadges,
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
            SELECT OwnerUserId, AVG(Score) AS AvgScore
            FROM Posts
            GROUP BY OwnerUserId
        ) avg_score ON u.Id = avg_score.OwnerUserId
        LEFT JOIN (
            SELECT OwnerUserId, MAX(CreationDate) AS LastPostDate
            FROM Posts
            GROUP BY OwnerUserId
        ) last_post ON u.Id = last_post.OwnerUserId
    ),
    TagRank AS (
        SELECT
            t.TagName,
            tag_owner.OwnerUserId,
            COUNT(*) AS PostsInTag,
            ROW_NUMBER() OVER (PARTITION BY t.TagName ORDER BY COUNT(*) DESC) AS TagRank
        FROM (
            -- generic tag-splitting approach using a recursive CTE to be more portable
            SELECT p.Id AS PostId,
                   p.OwnerUserId,
                   tag
            FROM Posts p
            JOIN LATERAL (
                -- normalize tags: remove surrounding angle brackets if present
                SELECT CASE WHEN p.Tags IS NULL OR p.Tags = '' THEN NULL
                            WHEN LEFT(p.Tags,1) = '<' AND RIGHT(p.Tags,1) = '>' THEN SUBSTRING(p.Tags FROM 2 FOR CHAR_LENGTH(p.Tags)-2)
                            ELSE p.Tags
                       END AS tags_clean
            ) tc ON TRUE
            JOIN LATERAL (
                WITH RECURSIVE split(seq, rest, tag) AS (
                    SELECT 1,
                           tc.tags_clean || '><',
                           NULL
                    WHERE tc.tags_clean IS NOT NULL
                    UNION ALL
                    SELECT seq + 1,
                           CASE WHEN POSITION('><' IN rest) > 0 THEN SUBSTRING(rest FROM POSITION('><' IN rest) + 2) ELSE '' END,
                           TRIM(SUBSTRING(rest FROM 1 FOR CASE WHEN POSITION('><' IN rest) > 0 THEN POSITION('><' IN rest) - 1 ELSE CHAR_LENGTH(rest) END))
                    FROM split
                    WHERE rest <> ''
                )
                SELECT tag FROM split WHERE tag IS NOT NULL AND tag <> ''
            ) tagsplit ON TRUE
            WHERE p.Tags IS NOT NULL
        ) tag_owner
        JOIN Tags t ON t.TagName = tag_owner.tag
        JOIN Posts p2 ON p2.Id = tag_owner.PostId
        WHERE p2.PostTypeId = 1
        GROUP BY t.TagName, tag_owner.OwnerUserId
    ),
    RecentVotes AS (
        SELECT
            v.UserId,
            SUM(CASE WHEN vt.Name = 'UpMod' THEN 1 ELSE 0 END) AS UpVotes,
            SUM(CASE WHEN vt.Name = 'DownMod' THEN 1 ELSE 0 END) AS DownVotes,
            MAX(v.CreationDate) AS LastVoteDate
        FROM Votes v
        JOIN VoteTypes vt ON v.VoteTypeId = vt.Id
        WHERE v.CreationDate > (CAST('2024-10-01' AS date) - INTERVAL '30 days')
        GROUP BY v.UserId
    ),
    BestAnswer AS (
        SELECT
            a.OwnerUserId,
            a.Id AS AnswerId,
            a.Score AS AnswerScore,
            a.CreationDate AS AnswerDate
        FROM Posts a
        WHERE a.PostTypeId = 2
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
    COALESCE(tr.TagName, '<no-tag>') AS TopTag,
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

UNION ALL

SELECT
    NULL AS Id,
    'Overall Summary' AS DisplayName,
    NULL AS Reputation,
    SUM(GoldBadges) AS GoldBadges,
    SUM(SilverBadges) AS SilverBadges,
    SUM(BronzeBadges) AS BronzeBadges,
    SUM(QuestionCount) AS QuestionCount,
    SUM(AnswerCount) AS AnswerCount,
    ROUND(AVG(AvgScore)::numeric, 2) AS AvgScore,
    MAX(LastPostDate) AS LastPostDate,
    SUM(UpVotes) AS UpVotes,
    SUM(DownVotes) AS DownVotes,
    MAX(LastVoteDate) AS LastVoteDate,
    NULL AS TopTag,
    NULL AS PostsInTag,
    NULL AS TagRank,
    NULL AS AnswerId,
    NULL AS AnswerScore,
    NULL AS AnswerDate
FROM (
    SELECT us.Id, us.DisplayName, us.Reputation, us.GoldBadges, us.SilverBadges, us.BronzeBadges,
           us.QuestionCount, us.AnswerCount, us.AvgScore, us.LastPostDate,
           rv.UpVotes, rv.DownVotes, rv.LastVoteDate
    FROM UserStats us
    LEFT JOIN RecentVotes rv ON us.Id = rv.UserId
) agg
ORDER BY Reputation DESC NULLS LAST
LIMIT 100;