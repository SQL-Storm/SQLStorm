WITH RecentUsers AS (
    SELECT 
        u.Id AS UserId,
        u.DisplayName,
        u.Reputation,
        u.CreationDate,
        u.Location,
        DENSE_RANK() OVER (ORDER BY u.CreationDate DESC) AS UserRank
    FROM Users u
    WHERE u.CreationDate > CAST('2024-10-01 12:34:56' AS TIMESTAMP) - INTERVAL '90' DAY
),
ActiveQuestions AS (
    SELECT 
        p.Id AS QuestionId,
        p.Title,
        p.CreationDate,
        p.OwnerUserId,
        p.Score,
        p.ViewCount,
        p.AnswerCount,
        p.Tags,
        COALESCE(p.FavoriteCount,0) AS FavoriteCount
    FROM Posts p
    WHERE p.PostTypeId = 1 -- Questions only
        AND p.CreationDate >= CAST('2024-10-01 12:34:56' AS TIMESTAMP) - INTERVAL '180' DAY
        AND p.Score >= 2
),
QuestionsWithBadges AS (
    SELECT 
        aq.QuestionId,
        COUNT(DISTINCT b.Id) AS BadgeCount,
        SUM(CASE WHEN b.Class = 1 THEN 1 ELSE 0 END) AS GoldBadges,
        SUM(CASE WHEN b.Class = 2 THEN 1 ELSE 0 END) AS SilverBadges,
        SUM(CASE WHEN b.Class = 3 THEN 1 ELSE 0 END) AS BronzeBadges
    FROM ActiveQuestions aq
    JOIN Users u ON aq.OwnerUserId = u.Id
    LEFT JOIN Badges b ON b.UserId = u.Id
    GROUP BY aq.QuestionId
),
CommentScores AS (
    SELECT 
        c.PostId, 
        AVG(c.Score) AS AvgCommentScore,
        COUNT(*) AS CommentCount
    FROM Comments c
    WHERE c.CreationDate >= CAST('2024-10-01 12:34:56' AS TIMESTAMP) - INTERVAL '180' DAY
    GROUP BY c.PostId
),
ClosedQuestions AS (
    SELECT
        ph.PostId,
        MAX(ph.CreationDate) AS ClosedDate,
        cr.Name AS CloseReason
    FROM PostHistory ph
    JOIN PostHistoryTypes pht ON ph.PostHistoryTypeId = pht.Id
    LEFT JOIN CloseReasonTypes cr 
        ON cr.Id = CAST(ph.Comment AS INTEGER)
    WHERE ph.PostHistoryTypeId = 10 -- Post Closed
    GROUP BY ph.PostId, cr.Name
),
VotesAgg AS (
    SELECT
        v.PostId,
        SUM(CASE WHEN v.VoteTypeId = 2 THEN 1 ELSE 0 END) AS UpVotes,
        SUM(CASE WHEN v.VoteTypeId = 3 THEN 1 ELSE 0 END) AS DownVotes,
        SUM(CASE WHEN v.VoteTypeId = 5 THEN 1 ELSE 0 END) AS FavoriteVotes
    FROM Votes v
    GROUP BY v.PostId
)
SELECT 
    aq.QuestionId,
    COALESCE(u.DisplayName, '<community>') AS OwnerDisplayName,
    u.Reputation,
    aq.Title,
    aq.CreationDate,
    aq.Score,
    aq.ViewCount,
    aq.AnswerCount,
    COALESCE(qb.BadgeCount, 0) AS OwnerBadgeCount,
    COALESCE(qb.GoldBadges, 0) AS GoldBadges,
    COALESCE(qb.SilverBadges, 0) AS SilverBadges,
    COALESCE(qb.BronzeBadges, 0) AS BronzeBadges,
    COALESCE(cs.AvgCommentScore, 0) AS AvgRecentCommentScore,
    COALESCE(cs.CommentCount, 0) AS RecentCommentCount,
    (SELECT STRING_AGG(t.tag, ', ' ORDER BY t.tag)
     FROM (
       SELECT TRIM(tag) AS tag
       FROM (
         SELECT UNNEST(
           CASE 
             WHEN aq.Tags IS NULL THEN ARRAY[]::text[]
             ELSE STRING_TO_ARRAY(SUBSTRING(aq.Tags FROM 2 FOR GREATEST(LENGTH(aq.Tags)-2,0)), '><')
           END
         ) AS tag
       ) s
       WHERE tag IS NOT NULL AND tag <> ''
     ) t
    ) AS TagList,
    COALESCE(v.UpVotes, 0) AS UpVotes,
    COALESCE(v.DownVotes, 0) AS DownVotes,
    COALESCE(v.FavoriteVotes, 0) AS FavoriteVotes,
    CASE 
        WHEN COALESCE(v.UpVotes,0) + COALESCE(v.DownVotes,0) = 0 THEN NULL
        ELSE ROUND(100.0 * COALESCE(v.UpVotes,0) / (COALESCE(v.UpVotes,0) + COALESCE(v.DownVotes,0)), 2)
    END AS UpvoteRatio,
    cq.ClosedDate,
    cq.CloseReason,
    CASE 
        WHEN rq.UserId IS NOT NULL THEN 'RecentUser'
        ELSE 'LegacyUser'
    END AS OwnerType
FROM ActiveQuestions aq
LEFT JOIN Users u ON aq.OwnerUserId = u.Id
LEFT JOIN QuestionsWithBadges qb ON aq.QuestionId = qb.QuestionId
LEFT JOIN CommentScores cs ON aq.QuestionId = cs.PostId
LEFT JOIN VotesAgg v ON aq.QuestionId = v.PostId
LEFT JOIN ClosedQuestions cq ON aq.QuestionId = cq.PostId
LEFT JOIN RecentUsers rq ON aq.OwnerUserId = rq.UserId
WHERE 
    (aq.AnswerCount >= 2 OR COALESCE(cs.CommentCount,0) >= 3)
    AND (u.Location ILIKE '%United States%' OR u.Location IS NULL OR u.Location ILIKE '%remote%')
    AND (
        COALESCE(qb.GoldBadges,0) > 0 
        OR (COALESCE(v.UpVotes,0) > 10 AND aq.FavoriteCount > 2)
        OR (COALESCE(cs.AvgCommentScore,0) > 1.5)
        OR (cq.ClosedDate IS NOT NULL AND cq.CloseReason IN ('Duplicate', 'Needs more focus'))
    )
    AND EXISTS (
        SELECT 1 
        FROM PostLinks pl
        JOIN LinkTypes lt ON pl.LinkTypeId = lt.Id
        WHERE pl.PostId = aq.QuestionId 
            AND lt.Name IN ('Linked', 'Duplicate')
    )
GROUP BY
    aq.QuestionId,
    u.DisplayName,
    u.Reputation,
    aq.Title,
    aq.CreationDate,
    aq.Score,
    aq.ViewCount,
    aq.AnswerCount,
    qb.BadgeCount,
    qb.GoldBadges,
    qb.SilverBadges,
    qb.BronzeBadges,
    cs.AvgCommentScore,
    cs.CommentCount,
    v.UpVotes,
    v.DownVotes,
    v.FavoriteVotes,
    cq.ClosedDate,
    cq.CloseReason,
    rq.UserId,
    aq.Tags,
    aq.FavoriteCount
ORDER BY
    COALESCE(qb.GoldBadges,0) DESC,
    COALESCE(v.UpVotes,0) DESC,
    aq.ViewCount DESC
LIMIT 100;