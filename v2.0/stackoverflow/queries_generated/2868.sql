-- {"query": "2868.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gpt-4.1-mini", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2027, "output_tokens": 1176} 

WITH RecursiveUserBadgeCounts AS (
    SELECT 
        u.Id AS UserId,
        u.DisplayName,
        b.Class,
        COUNT(*) AS BadgeCount
    FROM Users u
    LEFT JOIN Badges b ON u.Id = b.UserId
    GROUP BY u.Id, u.DisplayName, b.Class

    UNION ALL

    SELECT 
        r.UserId,
        r.DisplayName,
        r.Class,
        r.BadgeCount
    FROM RecursiveUserBadgeCounts r
    WHERE r.BadgeCount > 5
),
UserPostAggregates AS (
    SELECT 
        p.OwnerUserId AS UserId,
        COUNT(*) FILTER (WHERE p.PostTypeId = 1) AS QuestionCount,
        COUNT(*) FILTER (WHERE p.PostTypeId = 2) AS AnswerCount,
        AVG(p.Score) FILTER (WHERE p.PostTypeId IN (1,2)) AS AvgPostScore,
        SUM(COALESCE(p.ViewCount,0)) AS TotalViews,
        MAX(p.CreationDate) AS LastPostDate
    FROM Posts p
    WHERE p.OwnerUserId IS NOT NULL AND p.OwnerUserId <> -1
    GROUP BY p.OwnerUserId
),
RankedPostsWithComments AS (
    SELECT 
        p.Id,
        p.PostTypeId,
        p.Title,
        p.OwnerUserId,
        p.CreationDate,
        p.Score,
        p.ViewCount,
        p.Tags,
        c.CommentCount,
        ROW_NUMBER() OVER (PARTITION BY p.OwnerUserId ORDER BY p.CreationDate DESC, p.Score DESC) AS UserPostRank,
        COUNT(*) OVER (PARTITION BY p.OwnerUserId) AS UserPostCount
    FROM Posts p
    LEFT JOIN (
        SELECT PostId, COUNT(*) AS CommentCount
        FROM Comments
        GROUP BY PostId
    ) c ON p.Id = c.PostId
    WHERE p.OwnerUserId IS NOT NULL AND p.OwnerUserId <> -1
),
ComplexPostLinks AS (
    SELECT 
        pl.PostId,
        pl.RelatedPostId,
        lt.Name AS LinkTypeName,
        p1.PostTypeId AS PostTypeId,
        p2.PostTypeId AS RelatedPostTypeId
    FROM PostLinks pl
    JOIN LinkTypes lt ON pl.LinkTypeId = lt.Id
    JOIN Posts p1 ON pl.PostId = p1.Id
    JOIN Posts p2 ON pl.RelatedPostId = p2.Id
    WHERE lt.Name IN ('Linked', 'Duplicate')
),
TopUsersByScore AS (
    SELECT 
        u.Id,
        u.DisplayName,
        u.Reputation,
        upa.QuestionCount,
        upa.AnswerCount,
        upa.AvgPostScore,
        upa.TotalViews,
        COALESCE(SUM(CASE WHEN b.Class = 1 THEN 1 ELSE 0 END),0) AS GoldBadges,
        COALESCE(SUM(CASE WHEN b.Class = 2 THEN 1 ELSE 0 END),0) AS SilverBadges,
        COALESCE(SUM(CASE WHEN b.Class = 3 THEN 1 ELSE 0 END),0) AS BronzeBadges
    FROM Users u
    LEFT JOIN UserPostAggregates upa ON u.Id = upa.UserId
    LEFT JOIN Badges b ON b.UserId = u.Id
    WHERE u.Reputation > 1000
    GROUP BY u.Id, u.DisplayName, u.Reputation, upa.QuestionCount, upa.AnswerCount, upa.AvgPostScore, upa.TotalViews
)
SELECT 
    t.Id AS UserId,
    t.DisplayName,
    t.Reputation,
    COALESCE(t.QuestionCount,0) AS QuestionCount,
    COALESCE(t.AnswerCount,0) AS AnswerCount,
    ROUND(COALESCE(t.AvgPostScore,0),2) AS AvgPostScore,
    COALESCE(t.TotalViews,0) AS TotalViewCount,
    t.GoldBadges,
    t.SilverBadges,
    t.BronzeBadges,
    STRING_AGG(
        DISTINCT CONCAT_WS(' - ',
            rp.Title,
            'Score:', rp.Score,
            'Comments:', COALESCE(rp.CommentCount,0),
            'Tags:', COALESCE(rp.Tags,'<None>')
        ), ' | '
        ORDER BY rp.CreationDate DESC
    ) AS RecentPostsSummary,
    COALESCE(MAX(pl.LinkCount),0) AS MaxPostLinksCount
FROM TopUsersByScore t
LEFT JOIN RankedPostsWithComments rp ON t.Id = rp.OwnerUserId AND rp.UserPostRank <= 5
LEFT JOIN (
    SELECT 
        PostId,
        COUNT(*) AS LinkCount
    FROM ComplexPostLinks
    GROUP BY PostId
) pl ON pl.PostId = rp.Id
WHERE 
    t.QuestionCount > 0
    AND t.AnswerCount > 0
    AND (t.GoldBadges + t.SilverBadges + t.BronzeBadges) >= 3
GROUP BY 
    t.Id, t.DisplayName, t.Reputation, t.QuestionCount, t.AnswerCount, t.AvgPostScore, t.TotalViews, t.GoldBadges, t.SilverBadges, t.BronzeBadges
HAVING AVG(COALESCE(rp.Score,0)) FILTER (WHERE rp.UserPostRank <= 5) > 5
ORDER BY 
    t.Reputation DESC,
    t.GoldBadges DESC,
    AvgPostScore DESC
FETCH FIRST 20 ROWS ONLY;
