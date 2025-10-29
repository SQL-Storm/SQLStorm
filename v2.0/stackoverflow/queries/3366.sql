-- {"query": "3366.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gpt-oss-120b", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2089, "output_tokens": 2952}
WITH
    recent_questions AS (
        SELECT
            p.OwnerUserId,
            p.Id        AS QuestionId,
            p.CreationDate,
            p.Score,
            COALESCE(p.FavoriteCount, 0) AS FavoriteCount,
            p.Tags,
            ROW_NUMBER() OVER (PARTITION BY p.OwnerUserId ORDER BY p.CreationDate DESC) AS rn
        FROM Posts p
        WHERE p.PostTypeId = 1
    ),

    user_badge_counts AS (
        SELECT
            u.Id                                            AS UserId,
            COUNT(CASE WHEN b.Class = 1 THEN 1 END)         AS GoldBadges,
            COUNT(CASE WHEN b.Class = 2 THEN 1 END)         AS SilverBadges,
            COUNT(CASE WHEN b.Class = 3 THEN 1 END)         AS BronzeBadges,
            COUNT(b.UserId)                                 AS TotalBadges
        FROM Users u
        LEFT JOIN Badges b ON b.UserId = u.Id
        GROUP BY u.Id
    ),

    user_vote_stats AS (
        SELECT
            u.Id                                            AS UserId,
            SUM(CASE WHEN v.VoteTypeId = 2 THEN 1 ELSE 0 END) AS UpVotesGiven,
            SUM(CASE WHEN v.VoteTypeId = 3 THEN 1 ELSE 0 END) AS DownVotesGiven,
            SUM(CASE WHEN v.VoteTypeId = 5 THEN 1 ELSE 0 END) AS FavoritesGiven,
            COUNT(v.Id)                                      AS TotalVotesGiven
        FROM Users u
        LEFT JOIN Votes v ON v.UserId = u.Id
        GROUP BY u.Id
    ),

    tag_usage AS (
        SELECT
            u.Id                                                AS UserId,
            tag                                                   AS Tag,
            COUNT(*)                                            AS TagCount
        FROM Users u
        JOIN Posts p ON p.OwnerUserId = u.Id AND p.PostTypeId = 1
        CROSS JOIN LATERAL (
            SELECT TRIM(BOTH '<>' FROM p.Tags) AS tags_trimmed
        ) t0
        CROSS JOIN LATERAL (
            SELECT UNNEST(STRING_TO_ARRAY(t0.tags_trimmed, '><')) AS tag
        ) t1
        WHERE p.Tags IS NOT NULL
        GROUP BY u.Id, tag
    ),

    top_tags AS (
        SELECT
            tu.UserId,
            STRING_AGG(tu.Tag, ', ' ORDER BY tu.TagCount DESC) AS TopTags
        FROM (
            SELECT
                tu_inner.UserId,
                tu_inner.Tag,
                tu_inner.TagCount,
                ROW_NUMBER() OVER (PARTITION BY tu_inner.UserId ORDER BY tu_inner.TagCount DESC) AS rn
            FROM tag_usage tu_inner
        ) tu
        WHERE tu.rn <= 5
        GROUP BY tu.UserId
    ),

    user_activity AS (
        SELECT
            u.Id                                                    AS UserId,
            COALESCE(MAX(p.CreationDate), TIMESTAMP '1970-01-01')    AS LastPostDate,
            COALESCE(MAX(c.CreationDate), TIMESTAMP '1970-01-01')    AS LastCommentDate,
            GREATEST(
                COALESCE(MAX(p.CreationDate), TIMESTAMP '1970-01-01'),
                COALESCE(MAX(c.CreationDate), TIMESTAMP '1970-01-01')
            )                                                       AS LastActivityDate
        FROM Users u
        LEFT JOIN Posts    p ON p.OwnerUserId = u.Id
        LEFT JOIN Comments c ON c.UserId = u.Id
        GROUP BY u.Id
    ),

    post_counts_raw AS (
        SELECT OwnerUserId, COUNT(*) AS QuestionCount, 0 AS AnswerCount
        FROM Posts
        WHERE PostTypeId = 1
        GROUP BY OwnerUserId
        UNION ALL
        SELECT OwnerUserId, 0 AS QuestionCount, COUNT(*) AS AnswerCount
        FROM Posts
        WHERE PostTypeId = 2
        GROUP BY OwnerUserId
    ),

    post_counts AS (
        SELECT
            OwnerUserId AS UserId,
            SUM(QuestionCount) AS TotalQuestions,
            SUM(AnswerCount)   AS TotalAnswers,
            SUM(QuestionCount) + SUM(AnswerCount) AS TotalPosts
        FROM post_counts_raw
        GROUP BY OwnerUserId
    ),

    composite_score AS (
        SELECT
            u.Id                                             AS UserId,
            u.Reputation,
            COALESCE(ub.GoldBadges, 0)                       AS GoldBadges,
            COALESCE(ub.SilverBadges, 0)                     AS SilverBadges,
            COALESCE(ub.BronzeBadges, 0)                     AS BronzeBadges,
            COALESCE(uv.UpVotesGiven, 0)                     AS UpVotesGiven,
            COALESCE(uv.DownVotesGiven, 0)                   AS DownVotesGiven,
            ua.LastActivityDate,
            COALESCE(rq.FavoriteCount, 0)                    AS RecentFavs,
            COALESCE(rq.Score, 0)                            AS RecentScore,
            COALESCE(pc.TotalQuestions, 0)                   AS TotalQuestions,
            COALESCE(pc.TotalAnswers, 0)                     AS TotalAnswers,
            tt.TopTags,
            ROW_NUMBER() OVER (
                ORDER BY
                    ( COALESCE(u.Reputation,0) * 0.4
                    + COALESCE(ub.GoldBadges,0)   * 15
                    + COALESCE(ub.SilverBadges,0) * 5
                    + COALESCE(ub.BronzeBadges,0) * 2
                    + COALESCE(uv.UpVotesGiven,0) * 0.1
                    - COALESCE(uv.DownVotesGiven,0) * 0.2
                    + COALESCE(rq.FavoriteCount,0) * 0.3
                    + COALESCE(rq.Score,0)         * 0.5
                    + COALESCE(pc.TotalPosts,0)   * 0.05
                    ) DESC
            )                                                AS RankByComposite
        FROM Users u
        LEFT JOIN user_badge_counts   ub ON ub.UserId = u.Id
        LEFT JOIN user_vote_stats     uv ON uv.UserId = u.Id
        LEFT JOIN user_activity       ua ON ua.UserId = u.Id
        LEFT JOIN recent_questions    rq ON rq.OwnerUserId = u.Id AND rq.rn = 1
        LEFT JOIN post_counts         pc ON pc.UserId = u.Id
        LEFT JOIN top_tags            tt ON tt.UserId = u.Id
    )

SELECT
    cs.UserId,
    u.DisplayName,
    cs.Reputation,
    cs.GoldBadges,
    cs.SilverBadges,
    cs.BronzeBadges,
    cs.UpVotesGiven,
    cs.DownVotesGiven,
    cs.LastActivityDate,
    cs.RecentFavs,
    cs.RecentScore,
    cs.TotalQuestions,
    cs.TotalAnswers,
    cs.TopTags,
    cs.RankByComposite
FROM composite_score cs
JOIN Users u ON u.Id = cs.UserId
WHERE cs.RankByComposite <= 100
ORDER BY cs.RankByComposite;