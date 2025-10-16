-- {"query": "5064.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gpt-4.1", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2027, "output_tokens": 1170} 
WITH RecentUsers AS (
    SELECT 
        u.Id AS UserId,
        u.DisplayName,
        u.Reputation,
        u.CreationDate,
        u.Location,
        DENSE_RANK() OVER (ORDER BY u.CreationDate DESC) AS UserRank
    FROM Users u
    WHERE u.CreationDate > NOW() - INTERVAL '90 days'
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
        AND p.CreationDate >= NOW() - INTERVAL '180 days'
        AND p.Score >= 2
),
QuestionsWithBadges AS (
    SELECT 
        aq.QuestionId,
        count(DISTINCT b.Id) AS BadgeCount,
        sum(CASE WHEN b.Class = 1 THEN 1 ELSE 0 END) AS GoldBadges,
        sum(CASE WHEN b.Class = 2 THEN 1 ELSE 0 END) AS SilverBadges,
        sum(CASE WHEN b.Class = 3 THEN 1 ELSE 0 END) AS BronzeBadges
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
    WHERE c.CreationDate >= NOW() - INTERVAL '180 days'
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
        ON cr.Id = CAST(ph.Comment AS int)
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
    qb.GoldBadges,
    qb.SilverBadges,
    qb.BronzeBadges,
    COALESCE(cs.AvgCommentScore, 0) AS AvgRecentCommentScore,
    cs.CommentCount AS RecentCommentCount,
    array_to_string(array(
        SELECT tag FROM unnest(string_to_array(substring(aq.Tags,2,length(aq.Tags)-2), '><')) AS tag
        WHERE tag IS NOT NULL AND tag <> ''
        ORDER BY tag ASC
    ), ', ') AS TagList,
    v.UpVotes,
    v.DownVotes,
    v.FavoriteVotes,
    CASE 
        WHEN v.UpVotes + v.DownVotes = 0 THEN NULL
        ELSE ROUND(100.0 * v.UpVotes / (v.UpVotes + v.DownVotes), 2)
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
        qb.GoldBadges > 0 
        OR (v.UpVotes > 10 AND aq.FavoriteCount > 2)
        OR (cs.AvgCommentScore > 1.5)
        OR (cq.ClosedDate IS NOT NULL AND cq.CloseReason IN ('Duplicate', 'Needs more focus'))
    )
    AND (
        EXISTS (
            SELECT 1 
            FROM PostLinks pl
            JOIN LinkTypes lt ON pl.LinkTypeId = lt.Id
            WHERE pl.PostId = aq.QuestionId 
                AND lt.Name IN ('Linked', 'Duplicate')
        )
    )
ORDER BY
    qb.GoldBadges DESC NULLS LAST,
    v.UpVotes DESC NULLS LAST,
    aq.ViewCount DESC
LIMIT 100;