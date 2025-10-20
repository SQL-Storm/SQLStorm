-- {"query": "35078.sql", "dataset": "stackoverflow", "version": "v1.1", "prompt": "p2", "model": "gpt-4.1", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 1986, "output_tokens": 755} 
WITH RecentActiveUsers AS (
    SELECT
        u.Id,
        u.DisplayName,
        u.Reputation,
        u.LastAccessDate,
        COUNT(p.Id) AS PostsCount,
        SUM(CASE WHEN p.PostTypeId = 1 THEN 1 ELSE 0 END) AS QuestionsCount,
        SUM(CASE WHEN p.PostTypeId = 2 THEN 1 ELSE 0 END) AS AnswersCount
    FROM
        Users u
    LEFT JOIN
        Posts p ON u.Id = p.OwnerUserId
    WHERE
        u.LastAccessDate >= cast('2024-10-01 12:34:56' as timestamp) - INTERVAL '30 days'
    GROUP BY
        u.Id, u.DisplayName, u.Reputation, u.LastAccessDate
    HAVING
        COUNT(p.Id) > 5
), TopLinkedQuestions AS (
    SELECT
        p.Id,
        p.Title,
        p.Score,
        p.ViewCount,
        COUNT(pl.Id) AS LinksCount
    FROM
        Posts p
    JOIN
        PostLinks pl ON p.Id = pl.RelatedPostId
    WHERE
        p.PostTypeId = 1
        AND p.CreationDate >= cast('2024-10-01 12:34:56' as timestamp) - INTERVAL '6 months'
    GROUP BY
        p.Id, p.Title, p.Score, p.ViewCount
    HAVING
        COUNT(pl.Id) > 3
), UserBadges AS (
    SELECT
        b.UserId,
        COUNT(*) FILTER (WHERE b.Class = 1) AS GoldBadges,
        COUNT(*) FILTER (WHERE b.Class = 2) AS SilverBadges,
        COUNT(*) FILTER (WHERE b.Class = 3) AS BronzeBadges,
        MAX(b.Date) AS LastBadgeDate
    FROM
        Badges b
    GROUP BY
        b.UserId
), CommentStats AS (
    SELECT
        c.UserId,
        COUNT(c.Id) AS CommentCount,
        AVG(c.Score) AS AvgCommentScore,
        MAX(c.CreationDate) AS LastCommentDate
    FROM
        Comments c
    WHERE
        c.CreationDate >= cast('2024-10-01 12:34:56' as timestamp) - INTERVAL '90 days'
    GROUP BY
        c.UserId
)
SELECT
    rau.Id AS UserId,
    rau.DisplayName,
    rau.Reputation,
    rau.LastAccessDate,
    rau.PostsCount,
    rau.QuestionsCount,
    rau.AnswersCount,
    COALESCE(ub.GoldBadges, 0) AS GoldBadges,
    COALESCE(ub.SilverBadges, 0) AS SilverBadges,
    COALESCE(ub.BronzeBadges, 0) AS BronzeBadges,
    ub.LastBadgeDate,
    cs.CommentCount,
    cs.AvgCommentScore,
    cs.LastCommentDate,
    tq.Title AS MostLinkedRecentQuestion,
    tq.Score AS QuestionScore,
    tq.ViewCount AS QuestionViewCount,
    tq.LinksCount AS QuestionLinksCount
FROM
    RecentActiveUsers rau
LEFT JOIN
    UserBadges ub ON rau.Id = ub.UserId
LEFT JOIN
    CommentStats cs ON rau.Id = cs.UserId
LEFT JOIN LATERAL (
    SELECT
        tq.Title,
        tq.Score,
        tq.ViewCount,
        tq.LinksCount
    FROM
        TopLinkedQuestions tq
    JOIN
        Posts p ON tq.Id = p.Id AND p.OwnerUserId = rau.Id
    ORDER BY
        tq.LinksCount DESC, tq.Score DESC
    LIMIT 1
) tq ON TRUE
ORDER BY
    rau.Reputation DESC,
    rau.PostsCount DESC
LIMIT 50;