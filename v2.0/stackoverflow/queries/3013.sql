-- {"query": "3013.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gpt-oss-120b", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2089, "output_tokens": 1987}
WITH
    UserStats AS (
        SELECT
            u.Id,
            u.DisplayName,
            u.Reputation,
            COALESCE(u.UpVotes, 0) - COALESCE(u.DownVotes, 0) AS NetVotes,
            (SELECT COUNT(*) FROM Badges b WHERE b.UserId = u.Id AND b.Class = 1) AS GoldBadges,
            (SELECT COUNT(*) FROM Badges b WHERE b.UserId = u.Id AND b.Class = 2) AS SilverBadges,
            (SELECT COUNT(*) FROM Badges b WHERE b.UserId = u.Id AND b.Class = 3) AS BronzeBadges,
            (SELECT MAX(p.CreationDate) FROM Posts p WHERE p.OwnerUserId = u.Id) AS LastPostDate,
            (SELECT MAX(c.CreationDate) FROM Comments c WHERE c.UserId = u.Id) AS LastCommentDate
        FROM Users u
    ),
    PostAgg AS (
        SELECT
            p.OwnerUserId AS UserId,
            COUNT(CASE WHEN p.PostTypeId = 1 THEN 1 END) AS QuestionCount,
            COUNT(CASE WHEN p.PostTypeId = 2 THEN 1 END) AS AnswerCount,
            AVG(CASE WHEN p.PostTypeId = 2 THEN p.Score END) AS AvgAnswerScore,
            MAX(p.ViewCount) AS MaxViewCount,
            -- STRING_AGG syntax varies; using standard SQL LISTAGG if available, otherwise fallback to concatenation may be needed per dialect.
            STRING_AGG(DISTINCT p.Tags, ';') AS AllTags
        FROM Posts p
        WHERE p.OwnerUserId IS NOT NULL
        GROUP BY p.OwnerUserId
    ),
    VoteAgg AS (
        SELECT
            v.PostId,
            SUM(CASE WHEN v.VoteTypeId = 2 THEN 1 ELSE 0 END) AS UpVotes,
            SUM(CASE WHEN v.VoteTypeId = 3 THEN 1 ELSE 0 END) AS DownVotes
        FROM Votes v
        GROUP BY v.PostId
    ),
    RankedUsers AS (
        SELECT
            us.Id,
            us.DisplayName,
            us.Reputation,
            us.NetVotes,
            us.GoldBadges,
            us.SilverBadges,
            us.BronzeBadges,
            pa.QuestionCount,
            pa.AnswerCount,
            pa.AvgAnswerScore,
            pa.MaxViewCount,
            pa.AllTags,
            GREATEST(
                COALESCE(us.LastPostDate, TIMESTAMP '1970-01-01'),
                COALESCE(us.LastCommentDate, TIMESTAMP '1970-01-01')
            ) AS RecentActivity,
            ROW_NUMBER() OVER (ORDER BY us.Reputation DESC, us.NetVotes DESC) AS Rank
        FROM UserStats us
        LEFT JOIN PostAgg pa ON pa.UserId = us.Id
        WHERE us.Reputation > 1000
          AND (us.GoldBadges > 0 OR us.SilverBadges > 1)
          AND (pa.QuestionCount IS NULL OR pa.QuestionCount >= 5)
    )
SELECT
    ru.Id,
    ru.DisplayName,
    ru.Reputation,
    ru.NetVotes,
    ru.GoldBadges,
    ru.SilverBadges,
    ru.BronzeBadges,
    COALESCE(ru.QuestionCount, 0) AS QuestionCount,
    COALESCE(ru.AnswerCount, 0) AS AnswerCount,
    ROUND(CAST(ru.AvgAnswerScore AS DECIMAL), 2) AS AvgAnswerScore,
    ru.MaxViewCount,
    CASE WHEN ru.AllTags IS NULL THEN 'NoTags' ELSE ru.AllTags END AS TagList,
    ru.RecentActivity,
    ru.Rank
FROM RankedUsers ru
WHERE ru.Rank <= 100

UNION ALL

SELECT
    NULL      AS Id,
    '---'     AS DisplayName,
    NULL      AS Reputation,
    NULL      AS NetVotes,
    NULL      AS GoldBadges,
    NULL      AS SilverBadges,
    NULL      AS BronzeBadges,
    NULL      AS QuestionCount,
    NULL      AS AnswerCount,
    NULL      AS AvgAnswerScore,
    NULL      AS MaxViewCount,
    NULL      AS TagList,
    NULL      AS RecentActivity,
    NULL      AS Rank
WHERE NOT EXISTS (SELECT 1 FROM RankedUsers WHERE Rank <= 100)

ORDER BY Rank NULLS LAST, Reputation DESC, Id;